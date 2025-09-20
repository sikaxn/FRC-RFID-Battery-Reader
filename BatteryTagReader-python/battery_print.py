# battery_print.py
# (only showing the full file for convenience)

import os, sys, tempfile, datetime, json, shutil, subprocess, webbrowser
from typing import Dict, Any, List

def _fmt_time_YYMMDDHHMM(t: str) -> str:
    if not t or t == "0000000000":
        return "Date not available"
    try:
        dt = datetime.datetime.strptime(t, "%y%m%d%H%M")
        return dt.strftime("%Y-%m-%d %H:%M")
    except Exception:
        return t

NOTE_LABELS = {0:"Normal",1:"Practice",2:"Scrap",3:"Other"}

def _guess_chrome_cmd() -> List[str]:
    if sys.platform.startswith("win"):
        for c in (r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                  r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"):
            if os.path.exists(c): return [c]
    elif sys.platform == "darwin":
        app = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        if os.path.exists(app): return [app]
    else:
        for name in ("google-chrome","chrome","chromium-browser","chromium"):
            if shutil.which(name): return [name]
    return []

def _escape(s: str) -> str:
    return s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")

def _render_usage_rows(u: List[Dict[str, Any]], max_rows: int = 36) -> str:
    parts = []
    rows = sorted(u or [], key=lambda x: int(x.get("i", 0)), reverse=True)
    extra = 0
    if len(rows) > max_rows:
        extra = len(rows) - max_rows
        rows = rows[:max_rows]
    for ent in rows:
        i = ent.get("i", 0)
        t = _fmt_time_YYMMDDHHMM(str(ent.get("t", "")))
        d = int(ent.get("d", 0))
        device = "Robot" if d == 1 else ("Charger" if d == 2 else "Unknown")
        e = ent.get("e", 0)
        v = ent.get("v", 0)
        row_class = " class='charger-row'" if d == 2 else ""
        parts.append(
            f"<tr{row_class}><td class='num'>{i}</td>"
            f"<td>{_escape(t)}</td><td>{_escape(device)}</td>"
            f"<td class='num'>{e}</td><td class='num'>{v}</td></tr>"
        )
    if not parts:
        parts.append("<tr><td colspan='5' class='muted'>No usage records.</td></tr>")
    if extra:
        parts.append(f"<tr><td colspan='5' class='muted'>(+{extra} more not shown)</td></tr>")
    return "\n".join(parts)


def generate_html(doc: Dict[str, Any], *, uid: str = "UNKNOWN") -> str:
    sn = str(doc.get("sn", ""))
    fu = _fmt_time_YYMMDDHHMM(str(doc.get("fu", "0000000000")))
    cc = int(doc.get("cc", 0))
    n  = int(doc.get("n", 0))
    note = NOTE_LABELS.get(n, "Normal")
    usage = doc.get("u", [])

    total_reads = sum(1 for x in usage if int(x.get("d", 0)) == 1)
    total_charges = sum(1 for x in usage if int(x.get("d", 0)) == 2)
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # High-contrast, single-letter page layout
    html = f"""<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8" />
<title>Battery Report — { _escape(sn) }</title>
<meta name="viewport" content="width=device-width, initial-scale=1" />
<style>
  :root {{
    --fg:#000; 
    --muted:#222; 
    --line:#000; 
    --bg:#fff;
  }}
  * {{ box-sizing:border-box; }}
  html, body {{ background:var(--bg); color:var(--fg); }}
  body {{
    margin:24px;
    font:12px/1.35 system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif;
  }}
  h1 {{ margin:0 0 6px; font-size:16px; font-weight:700; }}
  h2 {{ margin:14px 0 6px; font-size:13px; font-weight:700; }}
  .grid {{
    display:grid; 
    grid-template-columns: 160px 1fr 120px 1fr; 
    gap:6px 10px; 
    padding:8px; 
    border:1px solid var(--line); 
  }}
  .k {{ color:var(--muted); text-align:right; }}
  .code {{ font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }}
  table {{ width:100%; border-collapse:collapse; }}
  th, td {{ border-top:1px solid var(--line); padding:4px 6px; vertical-align:top; }}
  thead th {{ text-align:left; border-top:none; font-size:11px; font-weight:700; }}
  .num {{ text-align:right; font-variant-numeric: tabular-nums; }}
  .muted {{ color:#444; }}
  .foot {{ margin-top:8px; font-size:11px; color:#111; }}
  .charger-row {{ background:#000; color:#fff;}}
  @page {{
    size: letter;
    margin: 0.5in;
  }}
  @media print {{
    body {{ margin:0; }}
    /* make sure borders render in print */
    * {{ -webkit-print-color-adjust: exact; print-color-adjust: exact; }}
  }}
</style>
<script>
  window.addEventListener('load', function() {{
    setTimeout(function() {{ window.print(); }}, 100);
  }});
</script>
</head>
<body>
  <h1>Battery Report</h1>
  <div class="grid">
    <div class="k">Serial Number (sn):</div><div class="code">{_escape(sn)}</div>
    <div class="k">UID:</div><div class="code">{_escape(uid)}</div>
    <div class="k">First Use (fu):</div><div>{_escape(fu)}</div>
    <div class="k">Cycle Count (cc):</div><div class="code">{cc}</div>
    <div class="k">Note (n):</div><div class="code">{n} — {_escape(note)}</div>
  </div>

  <h2>Usage</h2>
  <table>
    <thead>
      <tr>
        <th style="width:48px">#</th>
        <th style="width:160px">Time</th>
        <th style="width:110px">Device</th>
        <th class="num" style="width:90px">e</th>
        <th class="num" style="width:90px">v</th>
      </tr>
    </thead>
    <tbody>
      {_render_usage_rows(usage, max_rows=36)}
    </tbody>
  </table>

  <h2>Stats</h2>
  <div class="grid" style="grid-template-columns: 160px 1fr 160px 1fr;">
    <div class="k">Robot records:</div><div class="code">{total_reads}</div>
    <div class="k">Charger records:</div><div class="code">{total_charges}</div>
    <div class="k">Total records (u):</div><div class="code">{len(usage)}</div>
    <div class="k">Generated:</div><div>{_escape(now)}</div>
  </div>

  <div class="foot">
    This report only represents the data currently stored on the NFC tag.
  </div>
</body>
</html>"""
    return html

def save_html(html: str, *, filename: str | None = None) -> str:
    fd, path = tempfile.mkstemp(prefix="battery_report_", suffix=".html") if filename is None else (None, filename)
    if fd is not None: os.close(fd)
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)
    return path

def open_in_chrome(html_path: str) -> None:
    cmd = _guess_chrome_cmd()
    if cmd:
        try:
            import subprocess
            subprocess.Popen(cmd + [html_path])
            return
        except Exception:
            pass
    webbrowser.open(f"file://{html_path}", new=2)

def render_and_open(doc: Dict[str, Any], *, uid: str = "UNKNOWN", filename: str | None = None) -> str:
    html = generate_html(doc, uid=uid)
    path = save_html(html, filename=filename)
    open_in_chrome(path)
    return path
