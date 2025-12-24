#!/usr/bin/env bash
set -e

# Set display
export DISPLAY=:0

# Function to check if X is accessible (after authorization is set)
x_is_ready() {
  xdpyinfo -display :0 >/dev/null 2>&1
}

# Function to try to get X access by finding auth file or using xhost
setup_x_access() {
  # First check if we already have access
  if x_is_ready; then
    echo "X display is already accessible"
    return 0
  fi
  
  # Try common XAUTHORITY locations
  local auth_locations=(
    "/tmp/.X0-auth"
    "$HOME/.Xauthority"
    "/root/.Xauthority"
  )
  
  # Try to find X process and get its auth file from command line
  local xorg_pid=$(pgrep -x Xorg | head -1)
  if [ -n "$xorg_pid" ]; then
    # Try to extract auth file from Xorg command line
    local xorg_cmd=$(ps -p "$xorg_pid" -o args= 2>/dev/null || true)
    if echo "$xorg_cmd" | grep -q -- "-auth"; then
      local auth_from_cmd=$(echo "$xorg_cmd" | sed -n 's/.*-auth \([^ ]*\).*/\1/p')
      if [ -n "$auth_from_cmd" ] && [ -f "$auth_from_cmd" ]; then
        export XAUTHORITY="$auth_from_cmd"
        if x_is_ready; then
          echo "Found working XAUTHORITY from Xorg process: $auth_from_cmd"
          return 0
        fi
      fi
    fi
  fi
  
  # Try each auth file location
  for auth_file in "${auth_locations[@]}"; do
    if [ -f "$auth_file" ]; then
      export XAUTHORITY="$auth_file"
      if x_is_ready; then
        echo "Found working XAUTHORITY at $auth_file"
        return 0
      fi
    fi
  done
  
  # If no auth file works, try to disable access control (acceptable for kiosk)
  echo "Attempting to disable X access control for local connections..."
  # Try with current user
  xhost +local: >/dev/null 2>&1 || true
  # Try with no restrictions (for kiosk mode) - use sudo if available
  xhost + >/dev/null 2>&1 || sudo xhost + >/dev/null 2>&1 || true
  # Also try with local
  xhost +local: >/dev/null 2>&1 || sudo xhost +local: >/dev/null 2>&1 || true
  
  return 0
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
  sleep 3
else
  echo "X server is already running"
fi

# Configure X authorization
echo "Configuring X authorization..."
setup_x_access

# Verify display is accessible
echo "Verifying display access..."
x_accessible=false
for i in {1..15}; do
  if x_is_ready; then
    echo "Display is accessible"
    x_accessible=true
    break
  fi
  if [ $i -lt 15 ]; then
    # Try setting up access again
    setup_x_access
  fi
  sleep 1
done

# If still not accessible and X is running, try restarting X
if [ "$x_accessible" = false ] && pgrep -x Xorg > /dev/null; then
  echo "WARNING: Cannot access existing X server, restarting it..."
  pkill -x Xorg || true
  sleep 2
  
  # Start X ourselves with proper auth
  echo "Starting X server with proper configuration..."
  export XAUTHORITY=/tmp/.X0-auth
  /usr/bin/Xorg :0 -nolisten tcp vt7 -auth "$XAUTHORITY" &
  
  # Wait for X to start
  for i in {1..10}; do
    if pgrep -x Xorg > /dev/null; then
      break
    fi
    sleep 1
  done
  
  sleep 3
  
  # Disable access control
  xhost +local: >/dev/null 2>&1 || true
  xhost + >/dev/null 2>&1 || true
  
  # Verify again
  if x_is_ready; then
    echo "Display is now accessible after restart"
    x_accessible=true
  fi
fi

if [ "$x_accessible" = false ]; then
  echo "ERROR: Cannot access display :0 after all attempts"
  exit 1
fi

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

