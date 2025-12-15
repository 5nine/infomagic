#!/usr/bin/env bash
set -e

echo "=== InfoMagic installer ==="

if [[ $EUID -ne 0 ]]; then
  echo "❌ Kör detta script med sudo"
  exit 1
fi

USER_PI="pi"
APP_DIR="/opt/infomagic"

echo "▶ Uppdaterar system..."
apt update

echo "▶ Installerar beroenden..."
apt install -y \
  nodejs npm \
  chromium-browser \
  weston \
  cec-utils \
  git

echo "▶ Skapar app-katalog..."
mkdir -p $APP_DIR
chown -R $USER_PI:$USER_PI $APP_DIR

echo "▶ Installerar Node-beroenden..."
sudo -u $USER_PI bash <<EOF
cd $APP_DIR
npm install
EOF

echo "▶ Installerar systemd-tjänster..."

cat >/etc/systemd/system/infomagic-backend.service <<EOF
[Unit]
Description=InfoMagic Backend
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/infomagic/server/server.js
WorkingDirectory=/opt/infomagic
Restart=always
User=pi
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/weston.service <<EOF
[Unit]
Description=Weston Wayland Compositor
After=systemd-user-sessions.service

[Service]
ExecStart=/usr/bin/weston --tty=1 --backend=drm-backend.so
Restart=always
User=pi
Environment=XDG_RUNTIME_DIR=/run/user/1000

[Install]
WantedBy=graphical.target
EOF

cat >/etc/systemd/system/infomagic-tv.service <<EOF
[Unit]
Description=InfoMagic TV UI
After=weston.service infomagic-backend.service

[Service]
ExecStart=/usr/bin/chromium-browser \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --autoplay-policy=no-user-gesture-required \
  --ozone-platform=wayland \
  http://localhost:3000/ui/tv.html
Restart=always
User=pi
Environment=WAYLAND_DISPLAY=wayland-0

[Install]
WantedBy=graphical.target
EOF

cat >/etc/systemd/system/infomagic-touch.service <<EOF
[Unit]
Description=InfoMagic Touch UI
After=weston.service infomagic-backend.service

[Service]
ExecStart=/usr/bin/chromium-browser \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --autoplay-policy=no-user-gesture-required \
  --ozone-platform=wayland \
  http://localhost:3000/ui/touch.html
Restart=always
User=pi
Environment=WAYLAND_DISPLAY=wayland-1

[Install]
WantedBy=graphical.target
EOF

echo "▶ Aktiverar tjänster..."
systemctl daemon-reexec
systemctl enable infomagic-backend
systemctl enable weston
systemctl enable infomagic-tv
systemctl enable infomagic-touch

echo "▶ Konfigurerar sudoers (CEC + backlight)..."

cat >/etc/sudoers.d/infomagic <<EOF
pi ALL=(ALL) NOPASSWD:/usr/bin/cec-client
pi ALL=(ALL) NOPASSWD:/usr/bin/tee
EOF
chmod 440 /etc/sudoers.d/infomagic

echo "▶ Skapar bildmappar..."
mkdir -p /opt/infomagic/public/images/{originals,thumbs}
chown -R pi:pi /opt/infomagic/public/images

echo "▶ Klart!"
echo "⚠️ Läs README.md för manuella steg (CEC, cron, verifiering)"
echo "▶ Starta om systemet: sudo reboot"
