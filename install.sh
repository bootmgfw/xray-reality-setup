#!/bin/bash

# ============================================================
#  Xray-core VLESS + Reality Auto-Installer
#  GitHub: https://github.com/YOUR_USERNAME/xray-reality-setup
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Root check ────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Run this script as root."

# ── Dependencies ──────────────────────────────────────────
info "Updating packages and installing dependencies..."
apt update -qq
apt install -y qrencode curl jq

# ── BBR congestion control ────────────────────────────────
bbr=$(sysctl -a 2>/dev/null | grep net.ipv4.tcp_congestion_control)
if [[ "$bbr" == *"= bbr"* ]]; then
    info "BBR is already enabled."
else
    echo "net.core.default_qdisc=fq"          >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    info "BBR enabled."
fi

# ── Install Xray-core ─────────────────────────────────────
info "Installing Xray-core..."
bash -c "$(curl -4 -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# ── Generate keys ─────────────────────────────────────────
info "Generating keys..."
KEYS_FILE="/usr/local/etc/xray/xray.keys"
CONFIG_FILE="/usr/local/etc/xray/config.json"

[[ -f "$KEYS_FILE" ]] && rm "$KEYS_FILE"
touch "$KEYS_FILE"

echo "shortsid=$(openssl rand -hex 8)" >> "$KEYS_FILE"
echo "uuid=$(xray uuid)"               >> "$KEYS_FILE"
xray x25519                            >> "$KEYS_FILE"

export uuid=$(awk -F'=' '/^uuid/{print $2}'     "$KEYS_FILE")
export privatkey=$(awk -F': ' '/PrivateKey/{print $2}' "$KEYS_FILE")
export shortsid=$(awk -F'=' '/^shortsid/{print $2}' "$KEYS_FILE")

# ── Write config.json ─────────────────────────────────────
info "Writing Xray configuration..."
cat > "$CONFIG_FILE" <<EOF
{
    "log": {
        "loglevel": "warning"
    },
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "domain": ["geosite:category-ads-all"],
                "outboundTag": "block"
            }
        ]
    },
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "email": "main",
                        "id": "$uuid",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "ya.ru:443",
                    "xver": 0,
                    "serverNames": ["ya.ru"],
                    "privateKey": "$privatkey",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": ["$shortsid"]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ],
    "policy": {
        "levels": {
            "0": {
                "handshake": 3,
                "connIdle": 180
            }
        }
    }
}
EOF

# ── Helper scripts ────────────────────────────────────────
info "Installing helper commands..."

# userlist
cat > /usr/local/bin/userlist <<'SCRIPT'
#!/bin/bash
CONFIG="/usr/local/etc/xray/config.json"
emails=($(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG"))

if [[ ${#emails[@]} -eq 0 ]]; then
    echo "Client list is empty."
    exit 1
fi

echo "=== Clients list ==="
for i in "${!emails[@]}"; do
    echo "  $((i+1)). ${emails[$i]}"
done
SCRIPT
chmod +x /usr/local/bin/userlist

# mainuser
cat > /usr/local/bin/mainuser <<'SCRIPT'
#!/bin/bash
CONFIG="/usr/local/etc/xray/config.json"
KEYS="/usr/local/etc/xray/xray.keys"

protocol=$(jq -r '.inbounds[0].protocol' "$CONFIG")
port=$(jq -r '.inbounds[0].port' "$CONFIG")
uuid=$(awk -F'=' '/^uuid/{print $2}' "$KEYS")
pbk=$(awk -F': ' '/PublicKey/{print $2}' "$KEYS")
sid=$(awk -F'=' '/^shortsid/{print $2}' "$KEYS")
sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG")
ip=$(timeout 3 curl -4 -s icanhazip.com)

link="${protocol}://${uuid}@${ip}:${port}?security=reality&sni=${sni}&fp=firefox&pbk=${pbk}&sid=${sid}&spx=&type=tcp&flow=xtls-rprx-vision&encryption=none#vless-${ip}"

echo ""
echo "=== Connection link ==="
echo "$link"
echo ""
echo "=== QR-code ==="
echo "${link}" | qrencode -t ansiutf8
SCRIPT
chmod +x /usr/local/bin/mainuser

# newuser
cat > /usr/local/bin/newuser <<'SCRIPT'
#!/bin/bash
CONFIG="/usr/local/etc/xray/config.json"
KEYS="/usr/local/etc/xray/xray.keys"

read -rp "Enter username (email): " email

if [[ -z "$email" || "$email" == *" "* ]]; then
    echo "Username cannot be empty or contain spaces."
    exit 1
fi

existing=$(jq --arg e "$email" '.inbounds[0].settings.clients[] | select(.email == $e)' "$CONFIG")
if [[ -n "$existing" ]]; then
    echo "User '$email' already exists."
    exit 1
fi

uuid=$(xray uuid)
jq --arg email "$email" --arg uuid "$uuid" \
  '.inbounds[0].settings.clients += [{"email": $email, "id": $uuid, "flow": "xtls-rprx-vision"}]' \
  "$CONFIG" > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json "$CONFIG"

systemctl restart xray

index=$(jq --arg e "$email" '.inbounds[0].settings.clients | to_entries[] | select(.value.email == $e) | .key' "$CONFIG")
protocol=$(jq -r '.inbounds[0].protocol' "$CONFIG")
port=$(jq -r '.inbounds[0].port' "$CONFIG")
pbk=$(awk -F': ' '/PublicKey/{print $2}' "$KEYS")
sid=$(awk -F'=' '/^shortsid/{print $2}' "$KEYS")
sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG")
ip=$(curl -4 -s icanhazip.com)
link="${protocol}://${uuid}@${ip}:${port}?security=reality&sni=${sni}&fp=firefox&pbk=${pbk}&sid=${sid}&spx=&type=tcp&flow=xtls-rprx-vision&encryption=none#${email}"

echo ""
echo "=== Connection link for $email ==="
echo "$link"
echo ""
echo "=== QR-code ==="
echo "${link}" | qrencode -t ansiutf8
SCRIPT
chmod +x /usr/local/bin/newuser

# rmuser
cat > /usr/local/bin/rmuser <<'SCRIPT'
#!/bin/bash
CONFIG="/usr/local/etc/xray/config.json"
emails=($(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG"))

if [[ ${#emails[@]} -eq 0 ]]; then
    echo "No clients to remove."
    exit 1
fi

echo "=== Clients list ==="
for i in "${!emails[@]}"; do
    echo "  $((i+1)). ${emails[$i]}"
done

read -rp "Enter client number to remove: " choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#emails[@]} )); then
    echo "Invalid number. Must be between 1 and ${#emails[@]}."
    exit 1
fi

selected="${emails[$((choice - 1))]}"

jq --arg email "$selected" \
  '(.inbounds[0].settings.clients) = [.inbounds[0].settings.clients[] | select(.email != $email)]' \
  "$CONFIG" > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json "$CONFIG"

systemctl restart xray
echo "Client '$selected' removed."
SCRIPT
chmod +x /usr/local/bin/rmuser

# sharelink
cat > /usr/local/bin/sharelink <<'SCRIPT'
#!/bin/bash
CONFIG="/usr/local/etc/xray/config.json"
KEYS="/usr/local/etc/xray/xray.keys"
emails=($(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG"))

if [[ ${#emails[@]} -eq 0 ]]; then
    echo "No clients found."
    exit 1
fi

echo "=== Clients list ==="
for i in "${!emails[@]}"; do
    echo "  $((i+1)). ${emails[$i]}"
done

read -rp "Choose client: " client

if ! [[ "$client" =~ ^[0-9]+$ ]] || (( client < 1 || client > ${#emails[@]} )); then
    echo "Invalid number."
    exit 1
fi

selected="${emails[$((client - 1))]}"
index=$(jq --arg e "$selected" '.inbounds[0].settings.clients | to_entries[] | select(.value.email == $e) | .key' "$CONFIG")
protocol=$(jq -r '.inbounds[0].protocol' "$CONFIG")
port=$(jq -r '.inbounds[0].port' "$CONFIG")
uuid=$(jq --argjson i "$index" -r '.inbounds[0].settings.clients[$i].id' "$CONFIG")
pbk=$(awk -F': ' '/PublicKey/{print $2}' "$KEYS")
sid=$(awk -F'=' '/^shortsid/{print $2}' "$KEYS")
sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG")
ip=$(curl -4 -s icanhazip.com)
link="${protocol}://${uuid}@${ip}:${port}?security=reality&sni=${sni}&fp=firefox&pbk=${pbk}&sid=${sid}&spx=&type=tcp&flow=xtls-rprx-vision&encryption=none#${selected}"

echo ""
echo "=== Connection link for $selected ==="
echo "$link"
echo ""
echo "=== QR-code ==="
echo "${link}" | qrencode -t ansiutf8
SCRIPT
chmod +x /usr/local/bin/sharelink

# ── Start Xray ────────────────────────────────────────────
info "Starting Xray service..."
systemctl restart xray

# ── Help file ─────────────────────────────────────────────
cat > "$HOME/help" <<'EOF'

  ╔══════════════════════════════════════════════╗
  ║        Xray User Management Commands         ║
  ╚══════════════════════════════════════════════╝

  mainuser   — show connection link for main user
  newuser    — create a new user
  rmuser     — remove a user
  sharelink  — generate connection link for any user
  userlist   — list all clients

  Config:    /usr/local/etc/xray/config.json
  Keys:      /usr/local/etc/xray/xray.keys

  Restart:   systemctl restart xray

EOF

echo ""
info "✅ Xray-core successfully installed!"
echo ""
cat "$HOME/help"
mainuser
