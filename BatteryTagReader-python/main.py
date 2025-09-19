#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
main.py — entrypoint.
By default launches the Tk GUI. Use `--cli` for one-shot read to stdout.
Under --cli, handles both MIME JSON and Text 'T' records; on failure prints RAW.
"""

import argparse, sys


def _cli():
    from battery_reader import with_reader, read_user_area, find_ndef_value
    from battery_reader import _parse_first_record as _pfr, _decode_text_record_payload as _txt  # reuse

    with with_reader("") as (conn, uid, rname):
        raw = read_user_area(conn)
        try:
            _, v_off, v_len = find_ndef_value(raw)
            tnf, tbytes, payload = _pfr(raw[v_off:v_off+v_len])
            if tnf == 0x02 and tbytes == b"application/json":
                print(payload.decode("utf-8"))
            elif tnf == 0x01 and tbytes == b"T":
                print(_txt(payload))
            else:
                print(payload.decode("utf-8", errors="replace").rstrip("\x00"))
        except Exception:
            # Print RAW best effort text
            try:
                _, v_off, v_len = find_ndef_value(raw)
                raw_val = raw[v_off:v_off+v_len]
            except Exception:
                raw_val = raw
            print(raw_val.decode("utf-8", errors="replace").rstrip("\x00"), file=sys.stdout)

def _gui():
    from battery_gui import App
    App().mainloop()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cli", action="store_true", help="Run one-shot CLI read to stdout")
    args = ap.parse_args()
    if args.cli:
        _cli()
    else:
        _gui()

if __name__ == "__main__":
    main()
