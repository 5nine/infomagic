#!/usr/bin/env bash
set -e

# Enable HDMI-1-1 screen
echo "Configuring displays..."
xrandr --output HDMI-1-1 --auto --right-of DSI-1

# Wait for displays to be ready
sleep 1

# Map touch input to DSI-1 display only
echo "Configuring touch input..."
# Find the touch device (usually contains "touchscreen" or "FT" for FT6236)
TOUCH_DEVICE=$(xinput list --name-only | grep -i -E "(touchscreen|FT|raspberrypi)" | head -n 1)

if [ -n "$TOUCH_DEVICE" ]; then
  echo "Found touch device: $TOUCH_DEVICE"
  # Map touch device to DSI-1 display only
  # This ensures touch input only affects the touch screen, not the TV
  xinput map-to-output "pointer:$TOUCH_DEVICE" DSI-1
  echo "Mapped touch device to DSI-1 display"
else
  echo "Warning: Touch device not found, skipping touch configuration"
  echo "Run 'xinput list' to see available input devices"
fi

# Start touch chromium page on DSI-1 screen (window-position=0,0)
echo "Starting touch display..."
/usr/bin/chromium --kiosk --password-store=basic --use-mock-keychain --user-data-dir=/tmp/chromium-touch --window-position=0,0 http://localhost:3000/ui/touch.html &

# Wait a moment before starting the second instance
sleep 1

# Start tv chromium page on HDMI-1-1 screen (window-position=1280,0)
echo "Starting TV display..."
/usr/bin/chromium --kiosk --password-store=basic --use-mock-keychain --user-data-dir=/tmp/chromium-tv --window-position=1280,0 http://localhost:3000/ui/tv.html &

echo "Startup complete. Both displays should be active."

