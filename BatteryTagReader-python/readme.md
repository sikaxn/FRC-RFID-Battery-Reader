1. To run: `pip install -r requirements.txt` and then run `python main.py` (or double-click `main.py` on Windows).

2. Compatible reader: **ACR122U** tested. Other **USB CCID** readers that support MIFARE Classic block commands (FF 82/86/B0/D6) should also work.


### 1) Install runtime + drivers, start pcscd

```bash
sudo apt update
sudo apt install -y pcscd pcsc-tools libccid libacsccid1 python3-tk
sudo systemctl enable --now pcscd
```

### 2) Make sure the kernel NFC driver isn’t blocking PC/SC

```bash
# If these modules are loaded, unload them now:
lsmod | grep -E 'pn533|nfc' || true
sudo modprobe -r pn533_usb pn533 nfc 2>/dev/null || true

# Restart pcscd after unloading:
sudo systemctl restart pcscd
```

(If that fixes it, make it permanent so the kernel doesn’t grab the reader again:)

```bash
echo 'blacklist pn533_usb' | sudo sudo tee /etc/modprobe.d/blacklist-pn533.conf
# Optional, if it still reappears:
# echo 'blacklist pn533' | sudo tee -a /etc/modprobe.d/blacklist-pn533.conf
# echo 'blacklist nfc'   | sudo tee -a /etc/modprobe.d/blacklist-pn533.conf
sudo update-initramfs -u
```

### 3) Replug the reader, verify PC/SC sees it

```bash
sudo systemctl restart pcscd
pcsc_scan
```

You should now see the reader listed and ATR changes when you tap a tag. If you do, your app will work:

```bash
python3 -c "from smartcard.System import readers; print(readers())"
python3 main.py
```

---

## Still nothing? Grab a quick diagnostic

This will print why pcscd can’t claim the device (e.g., “interface busy” means the kernel driver was still attached).

```bash
sudo systemctl stop pcscd
sudo pcscd -f -d
```

Now replug the ACR122U and watch the log for \~10 seconds. If you see messages about being unable to claim the interface or wrong driver, send me the last \~30 lines and I’ll pinpoint the next step.

---

### Notes

* `libacsccid1` provides ACS’s PC/SC bundle for the ACR122U; `libccid` is the generic CCID driver. Having **both** installed works well on Ubuntu.
* You **don’t** need special user permissions to *see* the reader via `pcsc_scan` (pcscd runs as root), but if you ever run into permission problems, add your user to `plugdev`:

  ```bash
  sudo usermod -aG plugdev $USER
  # log out and back in
  ```
* If you previously installed libnfc, it can auto-load the kernel NFC modules; blacklisting (above) prevents conflicts with PC/SC.
