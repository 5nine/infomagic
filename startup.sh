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

# Function to create Chromium preferences that disable translate
setup_chromium_prefs() {
  local user_data_dir=$1
  local prefs_dir="$user_data_dir/Default"
  mkdir -p "$prefs_dir"
  
  # Create or update Preferences file to disable translate
  local prefs_file="$prefs_dir/Preferences"
  if [ -f "$prefs_file" ]; then
    # Update existing preferences using Python or jq if available
    if command -v python3 &> /dev/null; then
      python3 << EOF
import json
import sys

try:
    with open("$prefs_file", "r") as f:
        prefs = json.load(f)
except:
    prefs = {}

# Disable translate
if "translate" not in prefs:
    prefs["translate"] = {}
prefs["translate"]["enabled"] = False

# Set language preferences
if "intl" not in prefs:
    prefs["intl"] = {}
prefs["intl"]["accept_languages"] = "en-US,en"

# Disable translate UI
if "translate_ui" not in prefs:
    prefs["translate_ui"] = {}
prefs["translate_ui"]["show_translate_option"] = False

with open("$prefs_file", "w") as f:
    json.dump(prefs, f, indent=2)
EOF
    else
      # Fallback: create minimal preferences file
      cat > "$prefs_file" << 'PREFSEOF'
{
  "translate": {
    "enabled": false
  },
  "intl": {
    "accept_languages": "en-US,en"
  },
  "translate_ui": {
    "show_translate_option": false
  }
}
PREFSEOF
    fi
  else
    # Create new preferences file
    cat > "$prefs_file" << 'PREFSEOF'
{
  "translate": {
    "enabled": false
  },
  "intl": {
    "accept_languages": "en-US,en"
  },
  "translate_ui": {
    "show_translate_option": false
  }
}
PREFSEOF
  fi
  echo "Configured Chromium preferences to disable translate in $user_data_dir"
}

# Kill any existing Chromium instances to ensure clean start
echo "Stopping any existing Chromium instances..."
pkill -f "chromium.*chromium-touch" || true
pkill -f "chromium.*chromium-tv" || true
sleep 1

# Setup Chromium preferences for both instances
echo "Configuring Chromium preferences..."
setup_chromium_prefs "/tmp/chromium-touch"
setup_chromium_prefs "/tmp/chromium-tv"

# Start touch chromium page on DSI-1 screen (window-position=0,0)
echo "Starting touch display..."
/usr/bin/chromium --kiosk --password-store=basic --use-mock-keychain --disable-features=TranslateUI,Translate --lang=en-US --user-data-dir=/tmp/chromium-touch --window-position=0,0 http://localhost:3000/ui/touch.html &

# Wait a moment before starting the second instance
sleep 1

# Start tv chromium page on HDMI-1-1 screen (window-position=1280,0)
echo "Starting TV display..."
/usr/bin/chromium --kiosk --password-store=basic --use-mock-keychain --disable-features=TranslateUI,Translate --lang=en-US --user-data-dir=/tmp/chromium-tv --window-position=1280,0 http://localhost:3000/ui/tv.html &

echo "Startup complete. Both displays should be active."

