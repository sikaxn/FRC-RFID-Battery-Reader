#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Read NDEF Text from a MIFARE Classic 1K using ACR122U via PC/SC (pyscard),
authenticating with NFC Forum NDEF key (D3F7D3F7D3F7) as Key A.

Requires:
    pip install pyscard ndeflib
"""

import sys
import time
from typing import List, Optional, Tuple

try:
    from smartcard.System import readers
    from smartcard.util import toHexString
except Exception:
    print("pyscard is required. Install with: pip install pyscard")
    raise

try:
    import ndef
except Exception:
    print("ndeflib is required. Install with: pip install ndeflib")
    raise


# -----------------------------
# Configuration
# -----------------------------
# Your provided default key:
NDEF_KEY = bytes([0xD3, 0xF7, 0xD3, 0xF7, 0xD3, 0xF7])  # NFC Forum NDEF Key (usually Key A)
# Fallback common key:
FFFF_KEY = bytes([0xFF] * 6)

# Load NDEF key to slot 0, FF..FF to slot 1
KEYS_TO_LOAD = [
    (0, NDEF_KEY),
    (1, FFFF_KEY),
]

# Try auth in this order per block: Key A slot0, Key A slot1, Key B slot0, Key B slot1
AUTH_ORDER = [
    (0x60, 0),  # Key A, slot 0 (NDEF key)
    (0x60, 1),  # Key A, slot 1 (FF..FF)
    (0x61, 0),  # Key B, slot 0
    (0x61, 1),  # Key B, slot 1
]

START_BLOCK = 4
END_BLOCK = 63


# -----------------------------
# APDUs
# -----------------------------

def apdu_load_key_to_slot(slot: int, key6: bytes) -> List[int]:
    if len(key6) != 6:
        raise ValueError("Key must be 6 bytes")
    # FF 82 00 <slot> 06 <6-byte key>
    return [0xFF, 0x82, 0x00, slot & 0xFF, 0x06] + list(key6)

def apdu_authenticate_block(block_number: int, key_type: int, key_slot: int) -> List[int]:
    # FF 86 00 00 05 01 00 <block> <key_type> <slot>
    return [0xFF, 0x86, 0x00, 0x00, 0x05,
            0x01, 0x00, block_number & 0xFF, key_type & 0xFF, key_slot & 0xFF]

def apdu_read_block(block_number: int) -> List[int]:
    # FF B0 00 <block> 10
    return [0xFF, 0xB0, 0x00, block_number & 0xFF, 0x10]

def apdu_get_uid() -> List[int]:
    # FF CA 00 00 00
    return [0xFF, 0xCA, 0x00, 0x00, 0x00]


# -----------------------------
# Helpers
# -----------------------------

def is_sector_trailer(block_number: int) -> bool:
    return (block_number % 4) == 3  # 3,7,11,...,63

def pick_reader(prefer_name_contains=("ACS", "ACR122")):
    rlist = readers()
    if not rlist:
        print("No PC/SC readers found. Is the ACR122U driver installed?")
        sys.exit(1)
    for r in rlist:
        if any(s in str(r) for s in prefer_name_contains):
            return r
    return rlist[0]

def transmit(conn, apdu: List[int]) -> Tuple[List[int], int, int]:
    data, sw1, sw2 = conn.transmit(apdu)
    return data, sw1, sw2

def require_ok(sw1: int, sw2: int, step: str):
    if not (sw1 == 0x90 and sw2 == 0x00):
        raise RuntimeError(f"{step} failed, SW1SW2={sw1:02X}{sw2:02X}")

def try_auth_then_read(conn, block: int) -> Optional[bytes]:
    """
    Try AUTH in AUTH_ORDER; return 16-byte block if success, else None.
    """
    for key_type, slot in AUTH_ORDER:
        data, sw1, sw2 = transmit(conn, apdu_authenticate_block(block, key_type, slot))
        if sw1 == 0x90 and sw2 == 0x00:
            data, sw1, sw2 = transmit(conn, apdu_read_block(block))
            if sw1 == 0x90 and sw2 == 0x00 and len(data) == 16:
                return bytes(data)
    return None

def read_blocks_range(conn, start: int, end_inclusive: int) -> bytes:
    buf = bytearray()
    for blk in range(start, end_inclusive + 1):
        if is_sector_trailer(blk):
            continue  # skip trailer
        b = try_auth_then_read(conn, blk)
        if b is None:
            raise RuntimeError(f"Failed to authenticate/read block {blk} with available keys")
        buf += b
    return bytes(buf)

def find_ndef_tlv(payload: bytes) -> Optional[bytes]:
    """
    Find NDEF TLV: 0x03 <len> <ndef...> [0xFE]
    Supports short len and extended (0xFF + 2-byte len).
    """
    i = 0
    L = len(payload)
    while i < L:
        t = payload[i]
        if t == 0x00:  # NULL TLV
            i += 1
            continue
        if t == 0xFE:  # Terminator
            break
        if i + 1 >= L:
            break

        if t == 0x03:  # NDEF TLV
            if payload[i+1] != 0xFF:
                length = payload[i+1]
                vstart = i + 2
            else:
                if i + 3 >= L:
                    break
                length = (payload[i+2] << 8) | payload[i+3]
                vstart = i + 4

            vend = vstart + length
            if vend <= L:
                return payload[vstart:vend]
            return None

        # Skip other TLVs
        if payload[i+1] != 0xFF:
            length = payload[i+1]
            i += 2 + length
        else:
            if i + 3 >= L:
                break
            length = (payload[i+2] << 8) | payload[i+3]
            i += 4 + length
    return None

def decode_and_print_ndef(ndef_bytes: bytes) -> int:
    count_text = 0
    for rec in ndef.message_decoder(ndef_bytes):
        print(f"- NDEF Record: type={rec.type}")
        if isinstance(rec, ndef.TextRecord):
            count_text += 1
            print(f"  TextRecord: '{rec.text}' (lang={rec.language}, enc={rec.encoding})")
        else:
            if hasattr(rec, "uri"):
                print(f"  URI: {rec.uri}")
            elif hasattr(rec, "data"):
                print(f"  Data length: {len(rec.data)}")
    return count_text


# -----------------------------
# Main
# -----------------------------

def main():
    print("Enumerating PC/SC readers...")
    r = pick_reader()
    print(f"Using reader: {r}")

    conn = r.createConnection()

    # Wait for card
    while True:
        try:
            conn.connect()
            break
        except Exception:
            print("Waiting for card... (present the tag)")
            time.sleep(0.8)

    # UID (optional)
    try:
        uid_data, sw1, sw2 = transmit(conn, apdu_get_uid())
        if sw1 == 0x90 and sw2 == 0x00:
            print("Card UID:", toHexString(uid_data))
        else:
            print(f"UID read not available (SW={sw1:02X}{sw2:02X})")
    except Exception:
        pass

    # Load keys
    for slot, key in KEYS_TO_LOAD:
        data, sw1, sw2 = transmit(conn, apdu_load_key_to_slot(slot, key))
        require_ok(sw1, sw2, f"LOAD_KEY to slot {slot}")
    print("Loaded keys:",
          ", ".join([f"slot {slot}={' '.join(f'{b:02X}' for b in key)}" for slot, key in KEYS_TO_LOAD]))

    # Read data blocks and find NDEF TLV
    print(f"Reading blocks {START_BLOCK}..{END_BLOCK} (skipping trailers)...")
    raw = read_blocks_range(conn, START_BLOCK, END_BLOCK)
    print(f"Read {len(raw)} bytes.")

    ndef_bytes = find_ndef_tlv(raw)
    if not ndef_bytes:
        print("No NDEF TLV found in read range. The tag may not be NDEF-formatted or data is elsewhere.")
        # Optional: dump first 64 bytes for debugging
        for i in range(0, min(64, len(raw)), 16):
            print(f"@{i:04d}: {raw[i:i+16].hex(' ')}")
        sys.exit(3)

    print(f"Found NDEF message ({len(ndef_bytes)} bytes). Decoding...")
    count_text = decode_and_print_ndef(ndef_bytes)
    if count_text == 0:
        print("No NDEF TextRecord found (maybe URI or other types above).")
    else:
        print(f"Done. Printed {count_text} NDEF TextRecord(s).")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted.")
