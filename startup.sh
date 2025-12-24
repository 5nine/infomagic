#!/usr/bin/env bash
set -e

# Enable HDMI-1-1 screen
echo "Configuring displays..."
xrandr --output HDMI-1-1 --auto --right-of DSI-1

# Start touch chromium page on DSI-1 screen (window-position=0,0)
echo "Starting touch display..."
/usr/bin/chromium --kiosk --password-store=basic --use-mock-keychain --user-data-dir=/tmp/chromium-touch --window-position=0,0 http://localhost:3000/ui/touch.html &

# Wait a moment before starting the second instance
sleep 1

# Start tv chromium page on HDMI-1-1 screen (window-position=1280,0)
echo "Starting TV display..."
/usr/bin/chromium --kiosk --password-store=basic --use-mock-keychain --user-data-dir=/tmp/chromium-tv --window-position=1280,0 http://localhost:3000/ui/tv.html &

echo "Startup complete. Both displays should be active."

