#!/usr/bin/env bash
set -e

# Set display
export DISPLAY=:0

# Function to check if X is accessible (after authorization is set)
x_is_ready() {
  xdpyinfo -display :0 >/dev/null 2>&1
}

# Set up X authority file location
export XAUTHORITY=/tmp/.X0-auth

# Ensure X server is running
if ! pgrep -x Xorg > /dev/null; then
  echo "Starting X server..."
  # Start X with a specific auth file
  /usr/bin/Xorg :0 -nolisten tcp vt7 -auth "$XAUTHORITY" &
  X_PID=$!
  
  # Wait for X server process to be running (up to 10 seconds)
  echo "Waiting for X server process..."
  for i in {1..10}; do
    if pgrep -x Xorg > /dev/null; then
      echo "X server process is running"
      break
    fi
    if [ $i -eq 10 ]; then
      echo "ERROR: X server process failed to start"
      exit 1
    fi
    sleep 1
  done
  
  # Give X server time to initialize and create auth file
  echo "Waiting for X server to initialize..."
  for i in {1..10}; do
    if [ -f "$XAUTHORITY" ] || x_is_ready; then
      break
    fi
    sleep 1
  done
  sleep 2
else
  echo "X server is already running"
  # Try to use existing auth or allow local connections
  if [ ! -f "$XAUTHORITY" ]; then
    xhost +local: >/dev/null 2>&1 || true
  fi
fi

# Configure X authorization to allow local connections
echo "Configuring X authorization..."
xhost +local: >/dev/null 2>&1 || true

# Verify display is accessible
echo "Verifying display access..."
for i in {1..10}; do
  if x_is_ready; then
    echo "Display is accessible"
    break
  fi
  if [ $i -eq 10 ]; then
    echo "ERROR: Cannot access display :0 after authorization setup"
    exit 1
  fi
  sleep 1
done

# Enable HDMI-1-1 screen
echo "Configuring displays..."
xrandr --output HDMI-1-1 --auto --right-of DSI-1

# Start touch chromium page on DSI-1 screen (window-position=0,0)
echo "Starting touch display..."
/usr/bin/chromium --kiosk --password-store=basic --use-mock-keychain --window-position=0,0 http://localhost:3000/ui/touch.html &

# Wait a moment before starting the second instance
sleep 1

# Start tv chromium page on HDMI-1-1 screen (window-position=1280,0)
echo "Starting TV display..."
/usr/bin/chromium --kiosk --password-store=basic --use-mock-keychain --window-position=1280,0 http://localhost:3000/ui/tv.html &

echo "Startup complete. Both displays should be active."

