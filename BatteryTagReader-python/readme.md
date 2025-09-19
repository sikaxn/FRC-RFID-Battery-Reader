# Battery NFC — Runbook (Windows / macOS / Ubuntu)

## Prereqs (all OSes)

* PC/SC NFC reader that supports MIFARE Classic via FF 82/86/B0/D6 (tested: **ACS ACR122U**).
* Project folder with: `main.py`, `battery_gui.py`, `battery_reader.py`, `battery_json.py`, `battery_log.py`, `requirements.txt`.

Tip (multiple readers): set a hint

* Windows (PowerShell): `setx BATTERY_READER_HINT "acr122"`
* macOS/Linux (bash): `export BATTERY_READER_HINT="acr122"`

---

## Windows 10/11 (no virtualenv)

1. Install **Python 3.10+** from python.org (check “Add Python to PATH”).
2. Ensure the **Smart Card** service is running; plug in **ACR122U** (drivers auto-install).
3. Install deps:

   ```powershell
   pip install -r requirements.txt
   ```
4. Run:

   ```powershell
   python main.py         # GUI
   ```

---

## macOS (Intel/Apple Silicon) — with virtualenv

1. Install **Python 3.10+** from python.org (recommended so Tkinter works).
2. Install build/tool deps (SWIG is required for `pyscard`):

   ```bash
   xcode-select --install           # command line tools
   brew install swig pcsc-tools     # swig is REQUIRED; pcsc-tools is optional but handy
   ```
3. Create & activate venv:

   ```bash
   cd <project>
   python3 -m venv .venv
   source .venv/bin/activate
   ```
4. Install deps (in venv):

   ```bash
   pip install -r requirements.txt
   ```
5. Run (in venv):

   ```bash
   python main.py
   ```

Sanity check:

```bash
python -c "from smartcard.System import readers; print(readers())"
```

---

## Ubuntu / Debian — with virtualenv

1. PC/SC runtime, CCID driver, Tk:

   ```bash
   sudo apt update
   sudo apt install -y pcscd pcsc-tools libccid libpcsclite1 python3-tk
   sudo systemctl enable --now pcscd
   ```
2. (ACR122U) Avoid kernel NFC grabbing the device:

   ```bash
   sudo modprobe -r pn533_usb pn533 nfc 2>/dev/null || true
   sudo systemctl restart pcscd
   ```
3. Create & activate venv:

   ```bash
   cd <project>
   python3 -m venv .venv
   source .venv/bin/activate
   ```
4. Install deps:

   ```bash
   pip install -r requirements.txt
   ```
5. Run:

   ```bash
   python main.py
   ```

Sanity check:

```bash
python -c "from smartcard.System import readers; print(readers())"
pcsc_scan
```

