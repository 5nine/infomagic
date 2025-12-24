#!/usr/bin/env bash
# Touch calibration helper script for InfoMagic
# This script helps calibrate the touch input for the DSI-1 display

set -e

echo "====================================="
echo "   InfoMagic Touch Calibration"
echo "====================================="
echo

# Check if running as root
if [[ $EUID -eq 0 ]]; then
  echo "⚠️  Running as root. Switching to display user..."
  DISPLAY_USER=$(ps aux | grep -E '[X]org|[x]init' | head -n 1 | awk '{print $1}' || echo "pi")
  if [ "$DISPLAY_USER" != "root" ]; then
    sudo -u "$DISPLAY_USER" DISPLAY=:0.0 "$0" "$@"
    exit $?
  fi
fi

export DISPLAY=:0.0

echo "▶ Detecting touch devices..."
xinput list
echo

# Find touch device
TOUCH_DEVICE=$(xinput list --name-only | grep -i -E "(touchscreen|FT|raspberrypi)" | head -n 1)

if [ -z "$TOUCH_DEVICE" ]; then
  echo "❌ No touch device found!"
  echo "Available input devices:"
  xinput list
  exit 1
fi

echo "▶ Found touch device: $TOUCH_DEVICE"
echo

# Check current mapping
echo "▶ Current touch device mapping:"
xinput list-props "$TOUCH_DEVICE" | grep -E "(Coordinate Transformation|libinput Calibration)" || echo "  (No calibration found)"
echo

# Map touch to DSI-1 display
echo "▶ Mapping touch device to DSI-1 display..."
xinput map-to-output "$TOUCH_DEVICE" DSI-1

if [ $? -eq 0 ]; then
  echo "✅ Touch device mapped to DSI-1"
else
  echo "⚠️  Could not map to DSI-1, trying alternative method..."
  # Alternative: use xinput set-prop with coordinate transformation
  echo "   You may need to run calibration manually"
fi

echo
echo "====================================="
echo "   Calibration Options"
echo "====================================="
echo
echo "Option 1: Run interactive calibration"
echo "  DISPLAY=:0.0 xinput_calibrator"
echo
echo "Option 2: Manually map touch to DSI-1 (if not already done)"
echo "  xinput map-to-output \"$TOUCH_DEVICE\" DSI-1"
echo
echo "Option 3: Check touch device properties"
echo "  xinput list-props \"$TOUCH_DEVICE\""
echo
echo "To test touch input, try touching the screen and watch:"
echo "  xinput test \"$TOUCH_DEVICE\""
echo

