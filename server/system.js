const { exec } = require('child_process');

function reboot(req, res) {
  res.json({ ok: true });
  exec('sudo /sbin/reboot');
}

function tvOn(req, res) {
  exec(`echo "on 0" | sudo cec-client -s`);
  res.json({ ok: true });
}

function tvOff(req, res) {
  exec(`echo "standby 0" | sudo cec-client -s`);
  res.json({ ok: true });
}

function touchOn(req, res) {
  exec(`echo 0 | sudo tee /sys/class/backlight/*/bl_power`);
  res.json({ ok: true });
}

function touchOff(req, res) {
  exec(`echo 1 | sudo tee /sys/class/backlight/*/bl_power`);
  res.json({ ok: true });
}

module.exports = { reboot, tvOn, tvOff, touchOn, touchOff };
