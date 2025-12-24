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

# Add user to groups needed for DRM access
echo "▶ Lägger till användare i render och video grupper..."
usermod -a -G render,video "$APP_USER"

# ─────────────────────────────────────
# Systemuppdatering + paket
# ─────────────────────────────────────
echo "▶ Uppdaterar paketlista..."
apt update

echo "▶ Installerar beroenden..."
apt install -y \
  nodejs npm \
  chromium \
  xorg \
  cec-utils \
  git \
  rsync

# ─────────────────────────────────────
# Installera app
# ─────────────────────────────────────
echo "▶ Installerar InfoMagic till $APP_DIR..."
mkdir -p "$APP_DIR"

# Sync files but preserve user-modified content:
# - Exclude .git
# - Exclude config/ (will be handled separately)
# - Exclude public/images/ (user uploaded images)
# - Don't use --delete to preserve any extra files
rsync -a \
  --exclude='.git' \
  --exclude='config/' \
  --exclude='public/images/' \
  "$SCRIPT_DIR/" "$APP_DIR/"

# Ensure directories exist
mkdir -p "$APP_DIR/config"
mkdir -p "$APP_DIR/public/images/originals" "$APP_DIR/public/images/thumbs"

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
# Only prompt for passwords if users.json doesn't exist
if [ ! -f "$APP_DIR/config/users.json" ]; then
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
else
  echo "▶ Använder befintliga lösenord från config/users.json"
  # Set dummy values to avoid errors in the script
  ADMIN_PASS=""
  EDITOR_PASS=""
fi

# Only create users.json if it doesn't exist
if [ ! -f "$APP_DIR/config/users.json" ]; then
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
else
  echo "▶ config/users.json finns redan - behåller befintlig fil"
fi

unset ADMIN_PASS
unset EDITOR_PASS

# Only create config.json if it doesn't exist
if [ ! -f "$APP_DIR/config/config.json" ]; then
  echo "▶ Skapar config/config.json..."
  
  sudo -u "$APP_USER" bash <<EOF
cd "$APP_DIR/server"
node <<'NODEEOF'
const fs = require('fs');

const config = {
  minImageLongSide: 1280,
  slideshowInterval: 5,
  calendar: {
    calendarId: "xxxxxxxx@group.calendar.google.com",
    view: "WEEK",
    showTitle: false,
    showNav: false,
    showDate: false,
    showTz: false
  }
};

fs.mkdirSync('../config', { recursive: true });
fs.writeFileSync('../config/config.json', JSON.stringify(config, null, 2));
console.log('✔ config.json skapad');
NODEEOF
EOF
else
  echo "▶ config/config.json finns redan - behåller befintlig fil"
fi

# ─────────────────────────────────────
# systemd-tjänster
# ─────────────────────────────────────
echo "▶ Installerar systemd-tjänster..."

# Kopiera service-filer från repo och ersätt variabler
for service_file in "$SCRIPT_DIR/systemd"/*.service; do
  if [ -f "$service_file" ]; then
    service_name=$(basename "$service_file")
    echo "  → Installerar $service_name..."
    sed -e "s|@APP_USER@|$APP_USER|g" \
        -e "s|@APP_DIR@|$APP_DIR|g" \
        "$service_file" > "/etc/systemd/system/$service_name"
  fi
done


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
echo "▶ Kontrollerar bildmappar..."
mkdir -p "$APP_DIR/public/images/originals" "$APP_DIR/public/images/thumbs"
chown -R "$APP_USER:$APP_USER" "$APP_DIR/public/images"

# ─────────────────────────────────────
# Aktivera tjänster
# ─────────────────────────────────────
echo "▶ Aktiverar systemd-tjänster..."
systemctl daemon-reload
systemctl enable infomagic-backend
systemctl enable infomagic-startup

# ─────────────────────────────────────
# Installera startup.sh
# ─────────────────────────────────────
echo "▶ Installerar startup.sh..."
chmod +x "$APP_DIR/startup.sh"
chown "$APP_USER:$APP_USER" "$APP_DIR/startup.sh"

echo
echo "====================================="
echo "✅ Installation klar"
echo "▶ Starta om systemet:"
echo "   sudo reboot"
echo "====================================="
