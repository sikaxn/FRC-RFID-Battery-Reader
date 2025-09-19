#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
battery_reader.py
ACR122U + MIFARE Classic helpers (pyscard).

- Reads JSON from either Well-known Text 'T' or MIME 'application/json'.
- Writes a Text 'T' NDEF by default (Android compatible).
- Uses the FULL user area (blocks 4–63, skipping sector trailers) so large JSON fits.

Exposes:
- with_reader(...)  -> context manager or convenience runner
- ReaderOps:
    get_uid_hex()
    read_ndef_text()                  -> str (UTF-8 JSON string from first record)
    read_raw_text()                   -> best-effort payload/TLV/user-area as text
    write_ndef_text(text, mode='text')  # 'text' (default) | 'mime'

Utilities:
- read_user_area(), find_ndef_value(), build_ndef_for_text/json(), write_user_area_with_tlv()
"""

from typing import List, Optional, Tuple, Iterator, Callable, Any
from contextlib import contextmanager
from dataclasses import dataclass
import time

from smartcard.System import readers

# ---------- Config ----------
NDEF_KEY = bytes([0xD3, 0xF7, 0xD3, 0xF7, 0xD3, 0xF7])  # NFC Forum NDEF key (Key A)
FFFF_KEY = bytes([0xFF]*6)

KEYS_TO_LOAD = [
    (0, NDEF_KEY),   # slot 0
    (1, FFFF_KEY),   # slot 1
]

AUTH_ORDER = [
    (0x60, 0),  # Key A, slot 0
    (0x60, 1),  # Key A, slot 1
    (0x61, 0),  # Key B, slot 0
    (0x61, 1),  # Key B, slot 1
]

# Use the FULL user area, sector 1..15 (skip sector trailers)
START_BLOCK = 4
END_BLOCK   = 63  # <— full span; we skip trailers dynamically

# ---------- APDUs ----------
def apdu_load_key_to_slot(slot: int, key6: bytes) -> List[int]:
    if len(key6) != 6: raise ValueError("Key must be 6 bytes")
    return [0xFF, 0x82, 0x00, slot & 0xFF, 0x06] + list(key6)

def apdu_authenticate_block(block_number: int, key_type: int, key_slot: int) -> List[int]:
    return [0xFF, 0x86, 0x00, 0x00, 0x05, 0x01, 0x00, block_number & 0xFF, key_type & 0xFF, key_slot & 0xFF]

def apdu_read_block(block_number: int) -> List[int]:
    return [0xFF, 0xB0, 0x00, block_number & 0xFF, 0x10]

def apdu_update_block(block_number: int, data16: bytes) -> List[int]:
    if len(data16) != 16: raise ValueError("Data must be exactly 16 bytes")
    return [0xFF, 0xD6, 0x00, block_number & 0xFF, 0x10] + list(data16)

def apdu_get_uid() -> List[int]:
    return [0xFF, 0xCA, 0x00, 0x00, 0x00]

# ---------- helpers ----------
def is_sector_trailer(block_number: int) -> bool:
    return (block_number % 4) == 3  # 3,7,11,...

def transmit(conn, apdu: List[int]):
    data, sw1, sw2 = conn.transmit(apdu)
    return data, sw1, sw2

def require_ok(sw1: int, sw2: int, step: str):
    if not (sw1 == 0x90 and sw2 == 0x00):
        raise RuntimeError(f"{step} failed, SW={sw1:02X}{sw2:02X}")

def pick_reader(prefer=("ACS", "ACR122")):
    rlist = readers()
    if not rlist:
        raise RuntimeError("No PC/SC readers found")
    for r in rlist:
        if any(s in str(r) for s in prefer):
            return r
    return rlist[0]

def try_auth_then_read(conn, block: int) -> Optional[bytes]:
    for key_type, slot in AUTH_ORDER:
        _, sw1, sw2 = transmit(conn, apdu_authenticate_block(block, key_type, slot))
        if sw1 == 0x90 and sw2 == 0x00:
            data, sw1, sw2 = transmit(conn, apdu_read_block(block))
            if sw1 == 0x90 and sw2 == 0x00 and len(data) == 16:
                return bytes(data)
    return None

# ---------- user area (full span) ----------
def read_user_area(conn, start_block: int = START_BLOCK, end_block: int = END_BLOCK) -> bytes:
    buf = bytearray()
    for blk in range(start_block, end_block + 1):
        if is_sector_trailer(blk):
            continue
        b = try_auth_then_read(conn, blk)
        if b is None:
            raise RuntimeError(f"Auth/read failed at block {blk}")
        buf += b
    return bytes(buf)

def find_ndef_value(data: bytes) -> Tuple[int, int, int]:
    """Return (tlv_start, value_offset, value_length) for TLV 0x03."""
    i = 0; L = len(data)
    while i < L:
        t = data[i]
        if t == 0x00: i += 1; continue     # NULL TLV
        if t == 0xFE: break                # Terminator
        if i + 1 >= L: break
        if data[i+1] != 0xFF:
            length = data[i+1]; vstart = i + 2; hdr = 2
        else:
            if i + 3 >= L: break
            length = (data[i+2] << 8) | data[i+3]; vstart = i + 4; hdr = 4
        if t == 0x03:
            return (i, vstart, length)
        i += hdr + length
    raise RuntimeError("NDEF TLV (0x03) not found")

# ---------- NDEF build (Text/MIME) ----------
def _build_ndef_record_application_json(payload: bytes) -> bytes:
    t = b"application/json"
    if len(payload) >= 256:
        # MB=1, ME=1, CF=0, SR=0, IL=0, TNF=0x02 => 0xC2
        hdr = 0xC2
        return bytes([hdr, len(t)]) + len(payload).to_bytes(4, "big") + t + payload
    else:
        # MB=1, ME=1, CF=0, SR=1, IL=0, TNF=0x02 => 0xD2
        hdr = 0xD2
        return bytes([hdr, len(t), len(payload)]) + t + payload

def _build_ndef_record_text(payload_utf8: bytes, lang: str = "en") -> bytes:
    """
    RTD Text payload = [status][lang][text]
    status: bit7=UTF16 flag (0 for UTF-8), bits0..5 = lang len
    """
    type_t = b"T"
    lang_b = lang.encode("ascii", errors="ignore")[:32]
    status = len(lang_b) & 0x3F  # UTF-8 (bit7=0)
    text = bytes([status]) + lang_b + payload_utf8
    if len(text) >= 256:
        # MB=1, ME=1, SR=0, TNF=0x01 => 0xC1
        hdr = 0xC1
        return bytes([hdr, len(type_t)]) + len(text).to_bytes(4, "big") + type_t + text
    else:
        # MB=1, ME=1, SR=1, TNF=0x01 => 0xD1
        hdr = 0xD1
        return bytes([hdr, len(type_t), len(text)]) + type_t + text


def _tlv_wrap(ndef_msg: bytes) -> bytes:
    # TLV 0x03 <len | 0xFF LL> <ndef_msg> 0xFE
    tlv = bytearray([0x03])
    if len(ndef_msg) < 0xFF:
        tlv.append(len(ndef_msg))
    else:
        tlv.append(0xFF)
        tlv += len(ndef_msg).to_bytes(2, "big")
    tlv += ndef_msg + b"\xFE"
    return bytes(tlv)


def build_ndef_for_json(json_bytes: bytes) -> bytes:
    return _tlv_wrap(_build_ndef_record_application_json(json_bytes))

def build_ndef_for_text(text_utf8: bytes, lang: str = "en") -> bytes:
    return _tlv_wrap(_build_ndef_record_text(text_utf8, lang=lang))

def write_user_area_with_tlv(conn, tlv: bytes,
                             start_block: int = START_BLOCK, end_block: int = END_BLOCK):
    # Build full user buffer and pad with 0x00
    user_blocks = [b for b in range(start_block, end_block + 1) if not is_sector_trailer(b)]
    cap = len(user_blocks) * 16  # 48 blocks × 16 = 768 bytes on 1K
    if len(tlv) > cap:
        raise RuntimeError(f"NDEF too large ({len(tlv)} > {cap})")
    buf = tlv + b"\x00" * (cap - len(tlv))
    # Write each block (auth then FF D6)
    for i, blk in enumerate(user_blocks):
        chunk = buf[i*16:(i+1)*16]
        _, sw1, sw2 = transmit(conn, apdu_authenticate_block(blk, 0x60, 0))  # try Key A slot 0
        if not (sw1 == 0x90 and sw2 == 0x00):
            wrote = False
            for key_type, slot in AUTH_ORDER:
                _, sw1, sw2 = transmit(conn, apdu_authenticate_block(blk, key_type, slot))
                if sw1 == 0x90 and sw2 == 0x00:
                    _, sw1, sw2 = transmit(conn, apdu_update_block(blk, chunk))
                    if sw1 == 0x90 and sw2 == 0x00:
                        wrote = True
                        break
            if not wrote:
                raise RuntimeError(f"Write failed at block {blk}")
        else:
            _, sw1, sw2 = transmit(conn, apdu_update_block(blk, chunk))
            require_ok(sw1, sw2, f"WRITE block {blk}")

# ---------- NDEF parse ----------
def _parse_first_record(ndef_value: bytes) -> Tuple[int, bytes, bytes]:
    if len(ndef_value) < 3:
        raise ValueError("NDEF too short")
    hdr = ndef_value[0]
    tnf = hdr & 0x07
    sr  = (hdr >> 4) & 1
    il  = (hdr >> 3) & 1
    idx = 1
    tlen = ndef_value[idx]; idx += 1
    if sr:
        plen = ndef_value[idx]; idx += 1
    else:
        if idx + 4 > len(ndef_value): raise ValueError("Truncated NDEF (LEN32)")
        plen = int.from_bytes(ndef_value[idx:idx+4], "big"); idx += 4
    if il:
        if idx >= len(ndef_value): raise ValueError("Truncated NDEF (IL)")
        idlen = ndef_value[idx]; idx += 1
    else:
        idlen = 0
    if idx + tlen > len(ndef_value): raise ValueError("Truncated TYPE")
    type_bytes = ndef_value[idx:idx+tlen]; idx += tlen
    idx += idlen
    if idx + plen > len(ndef_value): raise ValueError("Truncated PAYLOAD")
    payload = ndef_value[idx:idx+plen]
    return tnf, type_bytes, payload


def _decode_text_record_payload(payload: bytes) -> str:
    if not payload:
        return ""
    status = payload[0]
    is_utf16 = (status & 0x80) != 0
    lang_len = status & 0x3F
    if 1 + lang_len > len(payload):
        return payload.decode("utf-8", errors="replace")
    text_bytes = payload[1 + lang_len :]
    encoding = "utf-16" if is_utf16 else "utf-8"
    return text_bytes.decode(encoding, errors="replace")


# ---------- context manager + convenience runner ----------
@dataclass
class ReaderOps:
    _conn: any
    _uid: str
    _name: str

    def get_uid_hex(self) -> str:
        return self._uid

    def read_ndef_text(self) -> str:
        data = read_user_area(self._conn)               # <— full area
        _, off, ln = find_ndef_value(data)
        tnf, tbytes, payload = _parse_first_record(data[off:off+ln])
        if tnf == 0x01 and tbytes == b"T":
            return _decode_text_record_payload(payload) # Android style
        if tnf == 0x02 and tbytes == b"application/json":
            return payload.decode("utf-8", errors="strict")
        raise ValueError("Unsupported first NDEF record (not Text or JSON-MIME)")

    def read_raw_text(self) -> str:
        """Best-effort: decode first record payload (Text/MIME) else TLV/user area."""
        data = read_user_area(self._conn)
        try:
            _, off, ln = find_ndef_value(data)
            tnf, tbytes, payload = _parse_first_record(data[off:off+ln])
            if tnf == 0x01 and tbytes == b"T":
                return _decode_text_record_payload(payload)
            return payload.decode("utf-8", errors="replace").rstrip("\x00")
        except Exception:
            return data.decode("utf-8", errors="replace").rstrip("\x00")

    def write_ndef_text(self, text: str, *, mode: str = "text"):
        """
        mode: 'text' | 'mime'
        Default 'text' matches Android TextRecord writers.
        Writes across blocks 4–63 (skipping trailers) so long JSON fits.
        """
        payload = text.encode("utf-8")
        if mode == "mime":
            tlv = build_ndef_for_json(payload)
        else:
            tlv = build_ndef_for_text(payload, lang="en")
        write_user_area_with_tlv(self._conn, tlv, start_block=START_BLOCK, end_block=END_BLOCK)

@contextmanager
def _reader_ctx(reader_hint: str = ""):
    r = None
    if reader_hint:
        for cand in readers():
            if reader_hint.lower() in str(cand).lower():
                r = cand; break
    if r is None:
        r = pick_reader()
    conn = r.createConnection()
    while True:
        try:
            conn.connect(); break
        except Exception:
            time.sleep(0.25)
    for slot, key in KEYS_TO_LOAD:
        _, sw1, sw2 = transmit(conn, apdu_load_key_to_slot(slot, key))
        require_ok(sw1, sw2, f"LOAD_KEY slot {slot}")
    try:
        uid, sw1, sw2 = transmit(conn, apdu_get_uid())
        uid_hex = "".join(f"{b:02X}" for b in uid) if (sw1 == 0x90 and sw2 == 0x00) else "UNKNOWN"
    except Exception:
        uid_hex = "UNKNOWN"
    try:
        yield (conn, uid_hex, str(r))
    finally:
        try: conn.disconnect()
        except Exception: pass

def with_reader(arg: Optional[Callable[[Any], Any]] = None):
    if callable(arg):
        fn = arg
        with _reader_ctx("") as (conn, uid, name):
            rd = ReaderOps(conn, uid, name)
            return fn(rd)
    else:
        hint = arg or ""
        return _reader_ctx(hint)
