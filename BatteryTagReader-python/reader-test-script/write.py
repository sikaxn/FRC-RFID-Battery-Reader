#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Write a JSON string {"msg":"hello world","time":"YYYY-MM-DDTHH:MM:SS"} as an NDEF TextRecord
to a MIFARE Classic 1K via ACR122U, replacing any existing NDEF message.

- Authenticates with Key A = D3F7D3F7D3F7 (NDEF key).
- Overwrites blocks 4–15 with a fresh NDEF TLV.
- Pads unused space with 0x00.

Requires:
    pip install pyscard ndeflib
"""

import sys, time, datetime
from smartcard.System import readers
from smartcard.util import toHexString

import ndef

# -----------------------------
# Config
# -----------------------------
NDEF_KEY = bytes([0xD3, 0xF7, 0xD3, 0xF7, 0xD3, 0xF7])
START_BLOCK = 4
END_BLOCK = 15   # up to sector 3 (skipping trailers)
KEY_SLOT = 0


# -----------------------------
# APDUs
# -----------------------------

def apdu_load_key_to_slot(slot: int, key6: bytes):
    return [0xFF, 0x82, 0x00, slot, 0x06] + list(key6)

def apdu_authenticate_block(block_number: int, key_type: int, key_slot: int):
    return [0xFF, 0x86, 0x00, 0x00, 0x05,
            0x01, 0x00, block_number & 0xFF, key_type & 0xFF, key_slot & 0xFF]

def apdu_read_block(block_number: int):
    return [0xFF, 0xB0, 0x00, block_number & 0xFF, 0x10]

def apdu_update_block(block_number: int, data16: bytes):
    if len(data16) != 16:
        raise ValueError("Data must be exactly 16 bytes")
    return [0xFF, 0xD6, 0x00, block_number & 0xFF, 0x10] + list(data16)

def apdu_get_uid():
    return [0xFF, 0xCA, 0x00, 0x00, 0x00]


# -----------------------------
# Helpers
# -----------------------------

def transmit(conn, apdu):
    data, sw1, sw2 = conn.transmit(apdu)
    return data, sw1, sw2

def require_ok(sw1, sw2, step=""):
    if not (sw1 == 0x90 and sw2 == 0x00):
        raise RuntimeError(f"{step} failed: SW1SW2={sw1:02X}{sw2:02X}")

def is_sector_trailer(block):
    return (block % 4) == 3

def auth_block(conn, block, slot=KEY_SLOT, key_type=0x60):
    _, sw1, sw2 = transmit(conn, apdu_authenticate_block(block, key_type, slot))
    require_ok(sw1, sw2, f"AUTH block {block}")

def write_block(conn, block, data16: bytes):
    auth_block(conn, block)
    _, sw1, sw2 = transmit(conn, apdu_update_block(block, data16))
    require_ok(sw1, sw2, f"WRITE block {block}")


# -----------------------------
# Build NDEF message
# -----------------------------

def build_json_ndef() -> bytes:
    now = datetime.datetime.now().replace(microsecond=0).isoformat()
    json_text = f'{{"msg":"hello world","time":"{now}"}}'

    record = ndef.TextRecord(json_text, language="en")
    ndef_msg = b"".join(ndef.message_encoder([record]))

    # Wrap in TLV (0x03 <len> <msg> 0xFE)
    tlv = bytearray()
    tlv.append(0x03)
    if len(ndef_msg) < 0xFF:
        tlv.append(len(ndef_msg))
    else:
        tlv.append(0xFF)
        tlv.extend(divmod(len(ndef_msg), 256))
    tlv.extend(ndef_msg)
    tlv.append(0xFE)

    return bytes(tlv)


# -----------------------------
# Main
# -----------------------------

def main():
    print("Enumerating PC/SC readers...")
    rlist = readers()
    if not rlist:
        print("No readers found")
        sys.exit(1)
    r = rlist[0]
    print(f"Using reader: {r}")
    conn = r.createConnection()

    while True:
        try:
            conn.connect()
            break
        except:
            print("Waiting for card...")
            time.sleep(1)

    # Load NDEF key into slot 0
    _, sw1, sw2 = transmit(conn, apdu_load_key_to_slot(KEY_SLOT, NDEF_KEY))
    require_ok(sw1, sw2, "LOAD_KEY")

    # Get UID
    uid, sw1, sw2 = transmit(conn, apdu_get_uid())
    if sw1 == 0x90 and sw2 == 0x00:
        print("Card UID:", toHexString(uid))

    # Build payload
    tlv = build_json_ndef()
    print("Writing NDEF payload:", tlv)

    # Compute how many user bytes we can overwrite
    user_blocks = [b for b in range(START_BLOCK, END_BLOCK+1) if not is_sector_trailer(b)]
    max_bytes = len(user_blocks) * 16
    buf = bytearray(tlv)
    if len(buf) > max_bytes:
        raise RuntimeError(f"NDEF message too large ({len(buf)} > {max_bytes})")

    # Pad with 0x00
    buf.extend([0x00] * (max_bytes - len(buf)))

    # Write block by block
    for i, blk in enumerate(user_blocks):
        chunk = buf[i*16:(i+1)*16]
        write_block(conn, blk, chunk)
        print(f"Wrote block {blk}: {chunk.hex()}")

    print("Done writing NDEF JSON to card.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted.")
