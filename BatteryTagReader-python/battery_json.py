#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
battery_json.py — helpers for your battery JSON format.

Schema:
{
  "sn":"A0000",
  "fu":"YYMMDDHHMM",
  "cc":5,
  "n":0,                  # note type (0..3)
  "u":[{"i":1,"t":"YYMMDDHHMM","d":1,"e":0,"v":0}, ...]
}
"""

from __future__ import annotations
from typing import Dict, Any, List
import json, datetime

MAX_USAGE = 14

def now_yyMMddHHmm_utc() -> str:
    return datetime.datetime.utcnow().strftime("%y%m%d%H%M")

def ensure_schema(obj: Dict[str, Any]) -> Dict[str, Any]:
    base = {"sn":"", "fu":"0000000000", "cc":0, "n":0, "u":[]}
    base.update(obj or {})
    base["sn"] = str(base.get("sn",""))
    base["fu"] = str(base.get("fu","0000000000"))
    base["cc"] = int(base.get("cc",0))
    base["n"]  = int(base.get("n",0))
    U: List[Dict[str,Any]] = []
    for ent in base.get("u",[]):
        try:
            U.append({
                "i": int(ent.get("i",0)),
                "t": str(ent.get("t","0000000000")),
                "d": int(ent.get("d",0)),
                "e": int(ent.get("e",0)),
                "v": int(ent.get("v",0)),
            })
        except Exception:
            continue
    U.sort(key=lambda x: x.get("i",0))
    base["u"]=U[-MAX_USAGE:]
    return base

def add_usage(obj: Dict[str,Any], *, t:str|None=None, d:int=1, e:int=0, v:int=0) -> Dict[str,Any]:
    doc = ensure_schema(obj)
    usage = list(doc["u"])
    next_id = (max([u["i"] for u in usage]) + 1) if usage else 1
    usage.append({"i":next_id, "t": t or now_yyMMddHHmm_utc(), "d": int(d), "e": int(e), "v": int(v)})
    doc["u"] = usage[-MAX_USAGE:]
    return doc

def set_meta(doc: Dict[str,Any], *, sn:str|None=None, fu:str|None=None, cc:int|None=None, n:int|None=None) -> Dict[str,Any]:
    d = ensure_schema(doc)
    if sn is not None: d["sn"]=str(sn)
    if fu is not None: d["fu"]=str(fu)
    if cc is not None: d["cc"]=int(cc)
    if n  is not None: d["n"]=int(n)
    return d

def dumps_compact(doc: Dict[str,Any]) -> str:
    return json.dumps(ensure_schema(doc), ensure_ascii=False, separators=(",",":"))

def dumps_pretty(doc: Dict[str,Any]) -> str:
    return json.dumps(ensure_schema(doc), ensure_ascii=False, indent=2)

# aliases/back-compat
def pretty(doc: Dict[str,Any]) -> str:
    return dumps_pretty(doc)

def to_json_bytes(doc: Dict[str,Any]) -> bytes:
    """Compact UTF-8 bytes for writing to NDEF."""
    return dumps_compact(doc).encode("utf-8")

def loads(text: str) -> Dict[str,Any]:
    return ensure_schema(json.loads(text))
