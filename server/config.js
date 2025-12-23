const fs = require('fs');
const path = require('path');

const CONFIG_PATH = path.join(__dirname, '../config/config.json');

const DEFAULT_CONFIG = {
  minImageLongSide: 1280,
  slideshowInterval: 5,
  calendar: {
    calendarId: 'xxxxxxxx@group.calendar.google.com',
    view: 'WEEK',
    showTitle: false,
    showNav: false,
    showDate: false,
    showTz: false,
  },
};

function loadConfig() {
  if (fs.existsSync(CONFIG_PATH)) {
    return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
  }
  return DEFAULT_CONFIG;
}

function saveConfig(cfg) {
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2));
}

module.exports = { loadConfig, saveConfig };
