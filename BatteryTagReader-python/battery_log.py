#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
battery_log.py — append Android-style log entries to a JSON array file.

Format (matches Android):
[
  {
    "time": "YYYY-MM-DD HH:MM",   # local time, no seconds
    "type": "read" | "write",
    "data": { ... }               # parsed JSON; or {"msg": <raw>, "time": "<ISO>"} if not JSON
  },
  ...
]

Path defaults to ./log.json; override with BATTERY_ANDROID_LOG_FILE.
"""

import os, json, datetime
from typing import Any, List

_LOG_PATH = os.environ.get("BATTERY_ANDROID_LOG_FILE", "log.json")

def _now_local_minute() -> str:
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

def _iso_seconds() -> str:
    return datetime.datetime.now().isoformat(timespec="seconds")

def _load_log(path: str) -> List[Any]:
    if not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        # Corrupt or empty — start fresh but don't blow up GUI flow
        return []

def _save_log(path: str, arr: List[Any]) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(arr, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, path)

def log_android_event(event_type: str, raw_text: str, *, path: str = None) -> None:
    """
    event_type: 'read' or 'write' (case-insensitive).
    raw_text: the raw JSON string we read or wrote.
    """
    et = (event_type or "").lower()
    if et not in ("read", "write"):
        et = "read"

    # Parse data if it's valid JSON; else store a message object like your Android app does.
    try:
        parsed = json.loads(raw_text)
        data_obj = parsed
    except Exception:
        data_obj = {"msg": str(raw_text), "time": _iso_seconds()}

    entry = {
        "time": _now_local_minute(),
        "type": et,
        "data": data_obj,
    }

    fp = path or _LOG_PATH
    arr = _load_log(fp)
    arr.append(entry)
    _save_log(fp, arr)
