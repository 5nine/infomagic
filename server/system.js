const { exec } = require('child_process');

function reboot(req, res) {
  exec('sudo /sbin/reboot', (error, stdout, stderr) => {
    if (error) {
      console.error('Reboot error:', error);
      return res.status(500).json({ error: 'Kunde inte starta om systemet: ' + error.message });
    }
    res.json({ ok: true });
  });
}

function tvOn(req, res) {
  exec(`echo "on 0" | sudo cec-client -s`, (error, stdout, stderr) => {
    if (error) {
      console.error('TV on error:', error);
      return res.status(500).json({ error: 'Kunde inte sätta på TV: ' + error.message });
    }
    if (stderr && !stderr.includes('opening a connection')) {
      console.error('TV on stderr:', stderr);
    }
    res.json({ ok: true });
  });
}

function tvOff(req, res) {
  exec(`echo "standby 0" | sudo cec-client -s`, (error, stdout, stderr) => {
    if (error) {
      console.error('TV off error:', error);
      return res.status(500).json({ error: 'Kunde inte sätta av TV: ' + error.message });
    }
    if (stderr && !stderr.includes('opening a connection')) {
      console.error('TV off stderr:', stderr);
    }
    res.json({ ok: true });
  });
}

function touchOn(req, res) {
  exec(`echo 0 | sudo tee /sys/class/backlight/*/bl_power`, (error, stdout, stderr) => {
    if (error) {
      console.error('Touch on error:', error);
      return res.status(500).json({ error: 'Kunde inte sätta på touch-skärm: ' + error.message });
    }
    res.json({ ok: true });
  });
}

function touchOff(req, res) {
  exec(`echo 1 | sudo tee /sys/class/backlight/*/bl_power`, (error, stdout, stderr) => {
    if (error) {
      console.error('Touch off error:', error);
      return res.status(500).json({ error: 'Kunde inte sätta av touch-skärm: ' + error.message });
    }
    res.json({ ok: true });
  });
}

module.exports = { reboot, tvOn, tvOff, touchOn, touchOff };
