#!/usr/bin/env bash
set -e
umask 027

echo "====================================="
echo "   InfoMagic installer v1.6"
echo "====================================="

# ─────────────────────────────────────
# Kontroll: root
# ─────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "❌ Kör detta script med sudo"
  exit 1
fi

APP_USER="infomagic"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="/opt/infomagic"

echo "▶ Installerar från källa:"
echo "   $SCRIPT_DIR"
echo "▶ Mål:"
echo "   $APP_DIR"

# ─────────────────────────────────────
# Skapa användare
# ─────────────────────────────────────
if ! id "$APP_USER" &>/dev/null; then
  echo "▶ Skapar användare '$APP_USER'..."
  useradd -m -s /bin/bash "$APP_USER"
else
  echo "▶ Användare '$APP_USER' finns redan"
fi

# ─────────────────────────────────────
# Systemuppdatering + paket
# ─────────────────────────────────────
echo "▶ Uppdaterar paketlista..."
apt update

echo "▶ Installerar beroenden..."
apt install -y \
  nodejs npm \
  chromium \
  weston \
  cec-utils \
  git \
  rsync

# ─────────────────────────────────────
# Installera app
# ─────────────────────────────────────
echo "▶ Installerar InfoMagic till $APP_DIR..."
mkdir -p "$APP_DIR"
rsync -a --delete --exclude='.git' "$SCRIPT_DIR/" "$APP_DIR/"
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

if [ ! -f "$APP_DIR/server/package.json" ]; then
  echo "❌ package.json hittades inte i $APP_DIR/server"
  exit 1
fi

# ─────────────────────────────────────
# Node dependencies
# ─────────────────────────────────────
echo "▶ Installerar Node-beroenden (server/)..."
sudo -u "$APP_USER" bash <<EOF
cd "$APP_DIR/server"
npm install
EOF

# ─────────────────────────────────────
# Skapa lösenord
# ─────────────────────────────────────
echo
echo "====================================="
echo "🔐 Skapa inloggningar för InfoMagic"
echo "====================================="

read -s -p "Ange ADMIN-lösenord: " ADMIN_PASS; echo
read -s -p "Bekräfta ADMIN-lösenord: " ADMIN_PASS2; echo
[[ "$ADMIN_PASS" == "$ADMIN_PASS2" ]] || { echo "❌ ADMIN-lösenorden matchar inte"; exit 1; }

read -s -p "Ange EDITOR-lösenord: " EDITOR_PASS; echo
read -s -p "Bekräfta EDITOR-lösenord: " EDITOR_PASS2; echo
[[ "$EDITOR_PASS" == "$EDITOR_PASS2" ]] || { echo "❌ EDITOR-lösenorden matchar inte"; exit 1; }

echo "▶ Skapar config/users.json..."

sudo -u "$APP_USER" \
  ADMIN_PASS="$ADMIN_PASS" \
  EDITOR_PASS="$EDITOR_PASS" \
  bash <<EOF
cd "$APP_DIR/server"
node <<'NODEEOF'
const fs = require('fs');
const bcrypt = require('bcrypt');

const adminPass = process.env.ADMIN_PASS;
const editorPass = process.env.EDITOR_PASS;

if (!adminPass || !editorPass) {
  console.error('❌ Lösenord saknas i miljön');
  process.exit(1);
}

const out = {
  users: [
    { username: 'admin', role: 'admin', passwordHash: bcrypt.hashSync(adminPass, 10) },
    { username: 'editor', role: 'editor', passwordHash: bcrypt.hashSync(editorPass, 10) }
  ]
};

fs.mkdirSync('../config', { recursive: true });
fs.writeFileSync('../config/users.json', JSON.stringify(out, null, 2));
console.log('✔ users.json skapad');
NODEEOF
EOF

unset ADMIN_PASS
unset EDITOR_PASS

# ─────────────────────────────────────
# systemd-tjänster
# ─────────────────────────────────────
echo "▶ Installerar systemd-tjänster..."

# Backend
cat >/etc/systemd/system/infomagic-backend.service <<EOF
[Unit]
Description=InfoMagic Backend
After=network.target
Wants=network.target

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node server/server.js
Restart=always
RestartSec=3
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

# TV
cat >/etc/systemd/system/infomagic-tv.service <<EOF
[Unit]
Description=InfoMagic TV Display
After=network-online.target infomagic-backend.service
Wants=network-online.target

[Service]
User=infomagic
Environment=DISPLAY=:0
ExecStart=/usr/bin/chromium \
  --kiosk \
  --window-position=0,0 \
  --window-size=1920,1080 \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-translate \
  --disable-features=TranslateUI \
  http://localhost:3000/ui/tv.html
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Touch
cat >/etc/systemd/system/infomagic-touch.service <<EOF
[Unit]
Description=InfoMagic Touch Display
After=network-online.target infomagic-backend.service
Wants=network-online.target

[Service]
User=infomagic
Environment=DISPLAY=:1
ExecStart=/usr/bin/chromium \
  --kiosk \
  --window-position=1920,0 \
  --window-size=1280,720 \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-translate \
  --disable-features=TranslateUI \
  http://localhost:3000/ui/touch.html
Restart=always
RestartSec=5


[Install]
WantedBy=multi-user.target
EOF

# ─────────────────────────────────────
# sudoers
# ─────────────────────────────────────
echo "▶ Konfigurerar sudoers..."
cat >/etc/sudoers.d/infomagic <<EOF
$APP_USER ALL=(ALL) NOPASSWD:/usr/bin/cec-client
$APP_USER ALL=(ALL) NOPASSWD:/usr/bin/tee
EOF
chmod 440 /etc/sudoers.d/infomagic

# ─────────────────────────────────────
# Bildmappar
# ─────────────────────────────────────
echo "▶ Skapar bildmappar..."
mkdir -p "$APP_DIR/public/images/originals" "$APP_DIR/public/images/thumbs"
chown -R "$APP_USER:$APP_USER" "$APP_DIR/public/images"

# ─────────────────────────────────────
# Aktivera tjänster
# ─────────────────────────────────────
echo "▶ Aktiverar systemd-tjänster..."
systemctl daemon-reload
systemctl enable infomagic-backend
systemctl enable weston
systemctl enable infomagic-tv
systemctl enable infomagic-touch

echo
echo "====================================="
echo "✅ Installation klar"
echo "▶ Starta om systemet:"
echo "   sudo reboot"
echo "====================================="
