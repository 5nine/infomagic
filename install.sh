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
  rsync \
  xinput-calibrator \
  xinput

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
$APP_USER ALL=(ALL) NOPASSWD:/usr/bin/xhost
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

# ─────────────────────────────────────
# Installera startup.sh och desktop shortcut
# ─────────────────────────────────────
echo "▶ Installerar startup.sh..."
chmod +x "$APP_DIR/startup.sh"
chown "$APP_USER:$APP_USER" "$APP_DIR/startup.sh"

# Make calibration script executable if it exists
if [ -f "$APP_DIR/calibrate-touch.sh" ]; then
  echo "▶ Installerar calibrate-touch.sh..."
  chmod +x "$APP_DIR/calibrate-touch.sh"
  chown "$APP_USER:$APP_USER" "$APP_DIR/calibrate-touch.sh"
fi

# ─────────────────────────────────────
# LXsession autostart
# ─────────────────────────────────────
echo "▶ Installerar LXsession autostart..."
LXSESSION_AUTOSTART="/etc/xdg/lxsession/LXDE-pi/autostart"

if [ -f "$LXSESSION_AUTOSTART" ]; then
  # autostart exists as a file - append startup command if not already present
  if ! grep -q "$APP_DIR/startup.sh" "$LXSESSION_AUTOSTART"; then
    echo "$APP_DIR/startup.sh &" >> "$LXSESSION_AUTOSTART"
    echo "  → LXsession autostart-kommando tillagt i $LXSESSION_AUTOSTART"
  else
    echo "  → LXsession autostart finns redan i $LXSESSION_AUTOSTART"
  fi
elif [ -d "$LXSESSION_AUTOSTART" ]; then
  # autostart exists as a directory - create desktop entry
  if [ -f "$SCRIPT_DIR/lxsession/infomagic-startup.desktop" ]; then
    sed -e "s|@APP_DIR@|$APP_DIR|g" \
        "$SCRIPT_DIR/lxsession/infomagic-startup.desktop" > "$LXSESSION_AUTOSTART/infomagic-startup.desktop"
    echo "  → LXsession autostart installerad i $LXSESSION_AUTOSTART/"
  else
    cat > "$LXSESSION_AUTOSTART/infomagic-startup.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=InfoMagic Startup
Comment=Start InfoMagic displays automatically
Exec=$APP_DIR/startup.sh
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
    echo "  → LXsession autostart installerad i $LXSESSION_AUTOSTART/"
  fi
else
  # autostart doesn't exist - create as directory and add desktop entry
  mkdir -p "$LXSESSION_AUTOSTART"
  if [ -f "$SCRIPT_DIR/lxsession/infomagic-startup.desktop" ]; then
    sed -e "s|@APP_DIR@|$APP_DIR|g" \
        "$SCRIPT_DIR/lxsession/infomagic-startup.desktop" > "$LXSESSION_AUTOSTART/infomagic-startup.desktop"
    echo "  → LXsession autostart installerad i $LXSESSION_AUTOSTART/"
  else
    cat > "$LXSESSION_AUTOSTART/infomagic-startup.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=InfoMagic Startup
Comment=Start InfoMagic displays automatically
Exec=$APP_DIR/startup.sh
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
    echo "  → LXsession autostart installerad i $LXSESSION_AUTOSTART/"
  fi
fi

# ─────────────────────────────────────
# Disable screen saver
# ─────────────────────────────────────
echo "▶ Inaktiverar screen saver..."

# Disable screen saver via xset (will be applied at runtime in startup.sh)
# Also configure LXDE to not use screen saver
if [ -f "$LXSESSION_AUTOSTART" ]; then
  # Remove any existing screen saver related lines
  sed -i '/xset s/d' "$LXSESSION_AUTOSTART" 2>/dev/null || true
  sed -i '/xset -dpms/d' "$LXSESSION_AUTOSTART" 2>/dev/null || true
  sed -i '/xset s noblank/d' "$LXSESSION_AUTOSTART" 2>/dev/null || true
  # Add screen saver disabling commands
  if ! grep -q "xset s off" "$LXSESSION_AUTOSTART"; then
    echo "@xset s off" >> "$LXSESSION_AUTOSTART"
    echo "@xset -dpms" >> "$LXSESSION_AUTOSTART"
    echo "@xset s noblank" >> "$LXSESSION_AUTOSTART"
    echo "  → Screen saver inaktiverad i $LXSESSION_AUTOSTART"
  else
    echo "  → Screen saver redan inaktiverad i $LXSESSION_AUTOSTART"
  fi
elif [ -d "$LXSESSION_AUTOSTART" ]; then
  # Create a separate desktop entry for screen saver disabling
  cat > "$LXSESSION_AUTOSTART/infomagic-disable-screensaver.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=InfoMagic Disable Screen Saver
Comment=Disable screen saver for kiosk mode
Exec=sh -c "xset s off && xset -dpms && xset s noblank"
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  echo "  → Screen saver inaktiverad via desktop entry"
fi

# Also disable screen saver system-wide for the user
USER_HOME=$(getent passwd "$APP_USER" | cut -d: -f6)
if [ -n "$USER_HOME" ] && [ -d "$USER_HOME" ]; then
  XINITRC="$USER_HOME/.xinitrc"
  if [ ! -f "$XINITRC" ] || ! grep -q "xset s off" "$XINITRC" 2>/dev/null; then
    cat >> "$XINITRC" <<'EOF'
# Disable screen saver for InfoMagic
xset s off
xset -dpms
xset s noblank
EOF
    chown "$APP_USER:$APP_USER" "$XINITRC"
    echo "  → Screen saver inaktiverad i $XINITRC"
  fi
fi

# ─────────────────────────────────────
# Cron jobs för schemaläggning
# ─────────────────────────────────────
echo "▶ Konfigurerar cron jobs för schemaläggning..."

# Default times (06:00 and 18:00)
ON_HOUR="${INFOMAGIC_ON_HOUR:-6}"
ON_MINUTE="${INFOMAGIC_ON_MINUTE:-0}"
OFF_HOUR="${INFOMAGIC_OFF_HOUR:-18}"
OFF_MINUTE="${INFOMAGIC_OFF_MINUTE:-0}"

# Marker to identify InfoMagic cron jobs
CRON_MARKER="# InfoMagic scheduled on/off"

# Create temporary file for new crontab
TMP_CRON=$(mktemp)
trap "rm -f $TMP_CRON" EXIT

# Get current crontab
crontab -l > "$TMP_CRON" 2>/dev/null || true

# Check if InfoMagic cron jobs already exist
if grep -q "$CRON_MARKER" "$TMP_CRON" 2>/dev/null; then
  echo "  → InfoMagic cron jobs finns redan - uppdaterar..."
  # Remove existing InfoMagic entries (marker and the two cron lines that follow)
  # Use awk to skip lines from marker until we hit a non-cron line or blank line
  awk -v marker="$CRON_MARKER" '
    BEGIN { skip=0; skip_count=0 }
    $0 ~ marker { skip=1; skip_count=2; next }
    skip && skip_count > 0 && /^[0-9*]+\s+[0-9*]+\s+/ { skip_count--; next }
    skip { skip=0; skip_count=0 }
    { print }
  ' "$TMP_CRON" > "${TMP_CRON}.new" && mv "${TMP_CRON}.new" "$TMP_CRON"
else
  echo "  → Lägger till InfoMagic cron jobs..."
  # Add blank line if crontab is not empty and doesn't end with newline
  if [ -s "$TMP_CRON" ] && [ "$(tail -c 1 "$TMP_CRON")" != "" ]; then
    echo "" >> "$TMP_CRON"
  fi
fi

# Add InfoMagic cron jobs
# Note: bl_power 0 = backlight ON, bl_power 1 = backlight OFF
# At startup (ON time), reboot the system - autostart will handle turning on displays
cat >> "$TMP_CRON" <<EOF
$CRON_MARKER
$ON_MINUTE $ON_HOUR * * * /sbin/reboot
$OFF_MINUTE $OFF_HOUR * * * echo "standby 0" | cec-client -s -d 1 && echo 1 | tee /sys/class/backlight/*/bl_power >/dev/null 2>&1
EOF

# Install new crontab
crontab "$TMP_CRON"
echo "  → Cron jobs installerade (på: ${ON_HOUR}:$(printf %02d ${ON_MINUTE}), av: ${OFF_HOUR}:$(printf %02d ${OFF_MINUTE}))"

echo
echo "====================================="
echo "✅ Installation klar"
echo "▶ Starta om systemet:"
echo "   sudo reboot"
echo "====================================="
