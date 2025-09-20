#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
battery_gui.py — Android-like GUI for NFC battery tags.

Flow & buttons:
- Read Tag
- Mock Robot            → add robot usage (d=1), write, then re-read
- Charged               → add charger usage (d=2), cc += 1, write, then re-read
- Set Status            → set note type `n` (0..3), write, then re-read
- Init New              → prompt SN, init empty doc, write, then re-read

UI:
- Usage list (most recent first), color-coded: charger=green, robot=blue
- Note type badge (color-coded): 0 normal, 1 practice, 2 scrap, 3 other
- Raw payload shown if JSON/record parse fails, also printed to console

Logging:
- Matches Android app log format via battery_log.log_android_event
"""
import datetime
import threading
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog, scrolledtext, filedialog
from battery_print import render_and_open   # ← new


from battery_log import log_android_event  # <-- Android-style logger

from battery_reader import with_reader
from battery_json import (
    loads as json_loads,
    dumps_compact,
    dumps_pretty,
    add_usage,
    set_meta,
    ensure_schema,
    now_yyMMddHHmm_utc,
)

NOTE_LABELS = {
    0: ("Normal",  "#e5e7eb", "#111827"),  # gray bg, dark text
    1: ("Practice","#dbeafe", "#1e3a8a"),  # blue-ish
    2: ("Scrap",   "#fee2e2", "#991b1b"),  # red-ish
    3: ("Other",   "#fef9c3", "#78350f"),  # yellow-ish
}

USAGE_COLOR = {
    1: ("Robot",   "#e0f2fe", "#0369a1"),  # blue bg, dark blue text
    2: ("Charger", "#dcfce7", "#166534"),  # green bg, dark green text
}

def _fmt_usage_time(tstr: str) -> str:
    """Format YYMMDDHHMM in local time; show 'Date not available' if all zeros."""
    if not tstr or tstr == "0000000000":
        return "Date not available"
    try:
        dt = datetime.datetime.strptime(tstr, "%y%m%d%H%M")
        return dt.strftime("%Y-%m-%d %H:%M")
    except Exception:
        return tstr


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Battery NFC")
        self.geometry("840x640")
        self.doc = None
        self.uid = "UNKNOWN"
        self.raw_fallback = None
        self._build_ui()

    # ---------- UI ----------
    def _build_ui(self):
        # Top bar
        top = ttk.Frame(self)
        top.pack(fill=tk.X, padx=10, pady=8)

        ttk.Button(top, text="Read Tag", command=self.read_tag).pack(side=tk.LEFT)
        ttk.Button(top, text="Mock Robot", command=self.mock_robot).pack(side=tk.LEFT, padx=6)
        ttk.Button(top, text="Charged", command=self.charged).pack(side=tk.LEFT)
        ttk.Button(top, text="Set Status", command=self.set_status).pack(side=tk.LEFT, padx=6)
        ttk.Button(top, text="Init New", command=self.init_new).pack(side=tk.LEFT)
        


        ttk.Separator(self, orient="horizontal").pack(fill=tk.X, padx=10, pady=6)

        # Meta row
        meta = ttk.LabelFrame(self, text="Meta")
        meta.pack(fill=tk.X, padx=10, pady=6)

        self.sn = tk.StringVar()
        self.fu = tk.StringVar()
        self.cc = tk.IntVar()
        self.nt = tk.IntVar()

        for i, (lab, var) in enumerate([
            ("SN", self.sn),
            ("FirstUse (YYMMDDHHMM)", self.fu),
            ("Cycle Count", self.cc),
            ("Note (0-3)", self.nt),
        ]):
            ttk.Label(meta, text=lab).grid(row=0, column=2*i, padx=6, pady=4, sticky="e")
            ttk.Entry(meta, textvariable=var, width=18).grid(row=0, column=2*i+1, padx=6, pady=4, sticky="w")

        # Note badge + UID
        badge_row = ttk.Frame(self)
        badge_row.pack(fill=tk.X, padx=10, pady=4)
        ttk.Label(badge_row, text="UID:").pack(side=tk.LEFT)
        self.uid_lbl = ttk.Label(badge_row, text="--")
        self.uid_lbl.pack(side=tk.LEFT, padx=(2, 12))

        self.note_badge = tk.Label(badge_row, text="Note: -", padx=8, pady=2)
        self.note_badge.pack(side=tk.LEFT)

        # Main split: usage list (left) and JSON (right)
        split = ttk.Frame(self)
        split.pack(fill=tk.BOTH, expand=True, padx=10, pady=6)

        # Usage list
        left = ttk.Frame(split)
        left.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 6))

        hdr = ttk.Label(left, text="Usage (most recent first):")
        hdr.pack(anchor="w", pady=(0, 4))

        cols = ("i", "time", "device", "extra")
        self.tree = ttk.Treeview(left, columns=cols, show="headings", height=16)
        self.tree.heading("i", text="#")
        self.tree.heading("time", text="Time")
        self.tree.heading("device", text="Device")
        self.tree.heading("extra", text="e/v")

        self.tree.column("i", width=40, anchor="center")
        self.tree.column("time", width=160, anchor="center")
        self.tree.column("device", width=100, anchor="center")
        self.tree.column("extra", width=120, anchor="center")

        # style tags for color
        self.tree.tag_configure("robot", background="#e0f2fe")    # blue-ish
        self.tree.tag_configure("charger", background="#dcfce7")  # green-ish

        self.tree.pack(fill=tk.BOTH, expand=True)

        # JSON text on the right
        right = ttk.Frame(split)
        right.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        ttk.Label(right, text="JSON").pack(anchor="w")
        self.txt = scrolledtext.ScrolledText(right, font=("Consolas", 10))
        self.txt.pack(fill=tk.BOTH, expand=True)

        # Status bar
        self.status = tk.StringVar(value="Ready.")
        ttk.Label(self, textvariable=self.status, anchor="w").pack(fill=tk.X, padx=10, pady=6)

        # File actions (optional)
        filebar = ttk.Frame(self)
        filebar.pack(fill=tk.X, padx=10, pady=(0, 8))
        ttk.Button(filebar, text="Load JSON...", command=self.load_json_file).pack(side=tk.LEFT)
        ttk.Button(filebar, text="Save JSON...", command=self.save_json_file).pack(side=tk.LEFT, padx=6)
        ttk.Button(filebar, text="Print", command=self.print_report).pack(side=tk.LEFT, padx=6)  # ← new

    # ---------- print Actions ---------- 
    def print_report(self):
        if not self.doc:
            messagebox.showinfo("Info", "Read a valid JSON tag first or Load JSON.")
            return
        try:
            path = render_and_open(self.doc, uid=self.uid)
            self.status.set(f"Report generated: {path}")
        except Exception as e:
            messagebox.showerror("Print Error", str(e))

    # ---------- NFC Actions ----------
    def read_tag(self):
        """Read, parse JSON (Text or MIME). Show RAW if parsing fails, and log."""
        def _do(rd):
            self.uid = rd.get_uid_hex()
            try:
                s = rd.read_ndef_text()      # supports Text('T') & MIME JSON
                self.doc = json_loads(s)     # parse JSON
                self.raw_fallback = None
                # Log Android-style
                log_android_event("read", s)
            except Exception:
                raw = rd.read_raw_text()
                print("[RAW CARD TEXT BEGIN]"); print(raw); print("[RAW CARD TEXT END]")
                self.doc = None
                self.raw_fallback = raw
                # Log even if JSON parse failed
                log_android_event("read", raw)
        self._run_reader(_do, done=self._render_all, label="Reading...")

    def _write_and_refresh(self, write_fn):
        """Run a writer fn(rd), then re-read the card to refresh UI."""
        def _do(rd):
            self.uid = rd.get_uid_hex()
            write_fn(rd)
        def _after():
            # After writing, re-read as if pressing Read Tag
            self.read_tag()
        self._run_reader(_do, done=_after, label="Writing...")

    # Mock Robot: add usage (d=1)
    def mock_robot(self):
        if not self._ensure_doc_or_warn():
            return
        new_doc = add_usage(self.doc, d=1)
        payload = dumps_compact(new_doc)
        def writer(rd, p=payload):
            log_android_event("write", p)            # log before write
            rd.write_ndef_text(p, mode="text")
        self._write_and_refresh(writer)

    # Charged: add usage (d=2) AND cc += 1
    def charged(self):
        if not self._ensure_doc_or_warn():
            return
        nd = add_usage(self.doc, d=2)
        nd = set_meta(nd, cc=nd.get("cc", 0) + 1)
        payload = dumps_compact(nd)
        def writer(rd, p=payload):
            log_android_event("write", p)            # log before write
            rd.write_ndef_text(p, mode="text")
        self._write_and_refresh(writer)

    # Set Status: set note type n (0..3)
    def set_status(self):
        if not self._ensure_doc_or_warn():
            return
        try:
            value = simpledialog.askinteger(
                "Set Status",
                "Note type (n):\n0 = normal\n1 = practice only\n2 = scrap\n3 = other",
                minvalue=0, maxvalue=3, parent=self
            )
        except Exception:
            value = None
        if value is None:
            return
        nd = set_meta(self.doc, n=int(value))
        payload = dumps_compact(nd)
        def writer(rd, p=payload):
            log_android_event("write", p)            # log before write
            rd.write_ndef_text(p, mode="text")
        self._write_and_refresh(writer)

    # Init New: prompt SN, init empty doc, write, re-read
    def init_new(self):
        sn = simpledialog.askstring("Init New Tag", "Serial Number:", parent=self)
        if not sn:
            return
        new_doc = ensure_schema({"sn": str(sn), "fu": now_yyMMddHHmm_utc(), "cc": 0, "n": 0, "u": []})
        payload = dumps_compact(new_doc)
        def writer(rd, p=payload):
            log_android_event("write", p)            # log before write
            rd.write_ndef_text(p, mode="text")
        self._write_and_refresh(writer)

    # ---------- File helpers ----------
    def load_json_file(self):
        p = filedialog.askopenfilename(filetypes=[("JSON", "*.json"), ("All", "*.*")])
        if not p:
            return
        with open(p, "r", encoding="utf-8") as f:
            s = f.read()
        try:
            self.doc = json_loads(s)
            self.raw_fallback = None
            self._render_all()
            self.status.set("Loaded JSON from file.")
        except Exception as e:
            messagebox.showerror("Error", f"Invalid JSON file:\n{e}")

    def save_json_file(self):
        if not self.doc:
            messagebox.showinfo("Info", "Nothing to save.")
            return
        p = filedialog.asksaveasfilename(defaultextension=".json", filetypes=[("JSON", "*.json")])
        if not p:
            return
        with open(p, "w", encoding="utf-8") as f:
            f.write(dumps_pretty(self.doc))
        self.status.set("Saved JSON to file.")

    # ---------- Rendering ----------
    def _render_all(self):
        # UID label
        self.uid_lbl.config(text=self.uid)

        # Note badge
        n = self.nt.get()
        try:
            n = int(n)
        except Exception:
            n = 0
        label, bg, fg = NOTE_LABELS.get(n, NOTE_LABELS[0])
        self.note_badge.config(text=f"Note: {label} ({n})", bg=bg, fg=fg)

        # JSON or RAW
        self.txt.delete("1.0", tk.END)
        if self.doc:
            # update meta entries
            self.sn.set(self.doc.get("sn", ""))
            self.fu.set(self.doc.get("fu", "0000000000"))
            self.cc.set(self.doc.get("cc", 0))
            self.nt.set(self.doc.get("n", 0))
            self.txt.insert(tk.END, dumps_pretty(self.doc))
            self.status.set(f"UID {self.uid} loaded (JSON).")
        elif self.raw_fallback is not None:
            self.sn.set("")
            self.fu.set("0000000000")
            self.cc.set(0)
            self.nt.set(0)
            self.txt.insert(tk.END, self.raw_fallback)
            self.status.set(f"UID {self.uid} loaded (RAW).")
        else:
            self.status.set("Ready.")

        # Usage list (most recent first)
        for i in self.tree.get_children():
            self.tree.delete(i)
        doc = self.doc or {}
        usage = list(reversed(doc.get("u", [])))  # newest first
        for ent in usage:
            i = ent.get("i", 0)
            t = ent.get("t", "")
            d = ent.get("d", 0)  # 1=robot, 2=charger
            e = ent.get("e", 0)
            v = ent.get("v", 0)
            tag = "charger" if d == 2 else ("robot" if d == 1 else "")
            dev_name = USAGE_COLOR.get(d, ("Unknown", "#fff", "#000"))[0]
            self.tree.insert("", "end", values=(i, _fmt_usage_time(t), dev_name, f"e={e}, v={v}"), tags=(tag,))

    # ---------- helpers ----------
    def _ensure_doc_or_warn(self) -> bool:
        if not self.doc:
            messagebox.showinfo("Info", "Read a valid JSON tag first or Load JSON.")
            return False
        return True

    def _run_reader(self, fn, done=None, label="Working..."):
        self.status.set(label + " Present a card…")

        def worker():
            try:
                with_reader(fn)
                self.after(0, (lambda: done()) if callable(done) else (lambda: None))
            except Exception as ex:
                err = str(ex)  # bind value so lambda doesn't reference a cleared exception
                self.after(0, lambda m=err: messagebox.showerror("Error", m))
            finally:
                self.after(0, lambda: self.status.set("Ready."))

        threading.Thread(target=worker, daemon=True).start()


if __name__ == "__main__":
    App().mainloop()
