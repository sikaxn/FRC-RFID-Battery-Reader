from smartcard.System import readers

COMMON_KEYS = [
    [0xFF]*6,
    [0xA0,0xA1,0xA2,0xA3,0xA4,0xA5],
    [0xD3,0xF7,0xD3,0xF7,0xD3,0xF7],
    [0x00]*6,
]

NDEF_KEY = [0xD3,0xF7,0xD3,0xF7,0xD3,0xF7]
KEY_A = 0x60
KEY_B = 0x61

def connect_reader():
    r = readers()
    if not r:
        raise Exception("No PC/SC readers found.")
    conn = r[0].createConnection()
    conn.connect()
    print(f"Using reader: {r[0]}")
    return conn

def apdu(conn, data):
    _, sw1, sw2 = conn.transmit(data)
    return (sw1, sw2)

def load_key(conn, key, slot=0x00):
    cmd = [0xFF, 0x82, 0x00, slot, 0x06] + key
    return apdu(conn, cmd) == (0x90,0x00)

def auth_block(conn, block, key_type, key, slot=0x00):
    if not load_key(conn, key, slot): return False
    cmd = [0xFF,0x86,0x00,0x00,0x05,
           0x01,0x00,block,key_type,slot]
    return apdu(conn, cmd) == (0x90,0x00)

def try_auth(conn, block):
    for key in COMMON_KEYS:
        if auth_block(conn, block, KEY_A, key):
            return (KEY_A, key)
    for key in COMMON_KEYS:
        if auth_block(conn, block, KEY_B, key):
            return (KEY_B, key)
    return (None,None)

def write_block(conn, block, buf16):
    if len(buf16)!=16: raise ValueError("Block must be 16 bytes")
    cmd = [0xFF,0xD6,0x00,block,0x10] + buf16
    return apdu(conn, cmd) == (0x90,0x00)

def trailer_block(sector):
    return sector*4+3

def wipe_sector(conn, sector):
    """
    Reset sector: zero data blocks, reset trailer.
    """
    tblock = trailer_block(sector)
    kt,key = try_auth(conn, tblock)
    if not kt:
        print(f"Cannot auth sector {sector}, skipping.")
        return False

    # Wipe data blocks
    for i in range(3):
        blk = sector*4+i
        if blk==0: continue # UID block not writable
        if not auth_block(conn, blk, kt, key):
            print(f"Cannot auth block {blk}, skip wipe.")
            continue
        if not write_block(conn, blk, [0x00]*16):
            print(f"Failed wipe block {blk}.")

    # Write trailer
    if not auth_block(conn, tblock, kt, key):
        print(f"Cannot auth trailer {tblock}, skip re-key.")
        return False
    trailer_bytes = NDEF_KEY + [0xFF,0x07,0x80,0x69] + [0xFF]*6
    if not write_block(conn, tblock, trailer_bytes):
        print(f"Failed to reset trailer {tblock}.")
        return False

    print(f"Sector {sector} wiped and re-keyed.")
    return True

def rebuild_mad(conn):
    # Sector 0, blocks 1 & 2
    blk1 = [0xD3,0xF7,0xD3,0xF7,0xD3,0xF7,0x03,0xE1] + [0x00]*8
    blk2 = [0x00]*16
    for blk,data in [(1,blk1),(2,blk2)]:
        kt,key = try_auth(conn, blk)
        if not kt: 
            print(f"Cannot auth MAD block {blk}, skipping.")
            continue
        if auth_block(conn, blk, kt, key):
            if write_block(conn, blk, data):
                print(f"Rewrote MAD block {blk}.")
            else:
                print(f"Failed to write MAD block {blk}.")

def write_ndef_ready(conn):
    text = "ready".encode("utf-8")
    ndef = [0xD1,0x01,len(text)+3,0x54,0x02,ord('e'),ord('n')] + list(text)
    tlv = [0x03,len(ndef)] + ndef + [0xFE]
    tlv_bytes = tlv + [0x00]*(48-len(tlv))

    for i in range(3):
        blk = 4+i
        kt,key = try_auth(conn, blk)
        if not kt: raise Exception(f"Auth failed block {blk}")
        if not auth_block(conn, blk, kt, key): raise Exception(f"Re-auth failed block {blk}")
        if not write_block(conn, blk, tlv_bytes[i*16:(i+1)*16]):
            raise Exception(f"Write failed block {blk}")
    print("Wrote NDEF TLV 'ready' into sector 1 blocks 4–6.")

def main():
    conn = connect_reader()

    print("Wiping all sectors (except UID)…")
    for s in range(16):
        wipe_sector(conn, s)

    print("Rebuilding MAD…")
    rebuild_mad(conn)

    print("Writing initial NDEF message…")
    write_ndef_ready(conn)

    print("Full wipe + re-init complete.")

if __name__=="__main__":
    main()
