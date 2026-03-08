# 🚀 Xray-core VLESS + Reality Auto-Installer

A one-command installer for a **VLESS + XTLS-Reality** proxy server powered by [Xray-core](https://github.com/XTLS/Xray-core).  
Designed for Debian/Ubuntu servers. Includes multi-user management via simple CLI commands.

---

## ✨ Features

- ✅ Automatic installation of Xray-core (latest release)
- ✅ VLESS + XTLS-Vision + Reality — the most censorship-resistant stack
- ✅ BBR congestion control enabled automatically
- ✅ Auto-generated UUID, private key, short ID
- ✅ QR-code output for easy mobile import
- ✅ Simple CLI tools for multi-user management

---

## 📋 Requirements

| Requirement | Detail |
|---|---|
| OS | Debian 10+ / Ubuntu 20.04+ |
| Access | Root |
| Port | 443 (TCP) must be open |

---

## ⚡ Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bootmgfw/xray-reality-setup/main/install.sh)
```

After installation, the connection link and QR-code for the **main user** are printed automatically.

---

## 🛠 Management Commands

After installation, the following commands are available system-wide:

| Command | Description |
|---|---|
| `mainuser` | Show connection link & QR-code for the main user |
| `newuser` | Create a new user (prompts for username) |
| `rmuser` | Remove an existing user |
| `sharelink` | Display connection link & QR-code for any user |
| `userlist` | List all active clients |

---

## 📁 File Locations

| File | Path |
|---|---|
| Xray config | `/usr/local/etc/xray/config.json` |
| Keys (UUID, private key, short ID) | `/usr/local/etc/xray/xray.keys` |
| Helper command scripts | `/usr/local/bin/` |

---

## 🔄 Useful Commands

```bash
# Restart Xray
systemctl restart xray

# Check Xray status
systemctl status xray

# View live logs
journalctl -u xray -f
```

---

## 🔧 Configuration Details

| Parameter | Value |
|---|---|
| Protocol | VLESS |
| Transport | TCP |
| Security | Reality |
| Flow | xtls-rprx-vision |
| Fingerprint | Firefox |
| SNI / Destination | `ya.ru:443` |
| Port | 443 |
| Ad blocking | Enabled (geosite:category-ads-all) |

> **Note:** You can change the `dest` and `serverNames` in `/usr/local/etc/xray/config.json` to any TLS 1.3-supporting domain (e.g. `www.google.com:443`).

---

## 📱 Client Apps

| Platform | App |
|---|---|
| Android | [v2rayNG](https://github.com/2dust/v2rayNG) |
| iOS | [Streisand](https://apps.apple.com/app/streisand/id6450534064) / [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) |
| Windows | [v2rayN](https://github.com/2dust/v2rayN) |
| macOS | [V2Box](https://apps.apple.com/app/v2box-v2ray-client/id6446814690) |
| Linux | [Nekoray](https://github.com/MatsuriDayo/nekoray) |

Import the connection link or scan the QR-code in your app.

---

## ⚠️ Disclaimer

This tool is intended for **privacy and security research** purposes only.  
Use responsibly and in compliance with the laws of your country.

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.
