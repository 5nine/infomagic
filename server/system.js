const { exec } = require('child_process');

// Helper to execute commands with timeout and error handling
function execCommand(command, timeout = 5000) {
  return new Promise((resolve, reject) => {
    const child = exec(command, { timeout }, (error, stdout, stderr) => {
      if (error) {
        // Don't reject for non-zero exit codes (some commands return them normally)
        resolve({ error: error.message, stdout, stderr });
      } else {
        resolve({ stdout, stderr });
      }
    });
    
    // Handle timeout
    child.on('error', reject);
  });
}

function reboot(req, res) {
  res.json({ ok: true });
  // Don't wait for reboot command - it will kill the process anyway
  exec('sudo /sbin/reboot', { timeout: 1000 }, (err) => {
    if (err) console.error('Reboot command error:', err);
  });
}

async function tvOn(req, res) {
  try {
    await execCommand(`echo "on 0" | sudo cec-client -s`, 3000);
    res.json({ ok: true });
  } catch (err) {
    console.error('TV on error:', err);
    res.status(500).json({ ok: false, error: err.message });
  }
}

async function tvOff(req, res) {
  try {
    await execCommand(`echo "standby 0" | sudo cec-client -s`, 3000);
    res.json({ ok: true });
  } catch (err) {
    console.error('TV off error:', err);
    res.status(500).json({ ok: false, error: err.message });
  }
}

async function touchOn(req, res) {
  try {
    await execCommand(`echo 0 | sudo tee /sys/class/backlight/*/bl_power`, 2000);
    res.json({ ok: true });
  } catch (err) {
    console.error('Touch on error:', err);
    res.status(500).json({ ok: false, error: err.message });
  }
}

async function touchOff(req, res) {
  try {
    await execCommand(`echo 1 | sudo tee /sys/class/backlight/*/bl_power`, 2000);
    res.json({ ok: true });
  } catch (err) {
    console.error('Touch off error:', err);
    res.status(500).json({ ok: false, error: err.message });
  }
}

module.exports = { reboot, tvOn, tvOff, touchOn, touchOff };
