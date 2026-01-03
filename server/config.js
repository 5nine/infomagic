const fs = require('fs').promises;
const path = require('path');

const CONFIG_PATH = path.join(__dirname, '../config/config.json');

const DEFAULT_CONFIG = {
  minImageLongSide: 1280,
  slideshowInterval: 15,
  calendar: {
    calendarId: 'xxxxxxxx@group.calendar.google.com',
    view: 'WEEK',
    showTitle: false,
    showNav: false,
    showDate: false,
    showTz: false,
  },
};

// In-memory cache to avoid repeated file reads
let configCache = null;
let configCacheTime = 0;
const CONFIG_CACHE_TTL = 1000; // 1 second cache

// Async version (preferred)
async function loadConfigAsync() {
  const now = Date.now();
  if (configCache && (now - configCacheTime) < CONFIG_CACHE_TTL) {
    return configCache;
  }

  try {
    const data = await fs.readFile(CONFIG_PATH, 'utf8');
    configCache = JSON.parse(data);
    configCacheTime = now;
    return configCache;
  } catch (err) {
    if (err.code === 'ENOENT') {
      configCache = DEFAULT_CONFIG;
      configCacheTime = now;
      return configCache;
    }
    // On other errors, return default
    return DEFAULT_CONFIG;
  }
}

// Sync version (for backwards compatibility, but cached)
function loadConfig() {
  const now = Date.now();
  if (configCache && (now - configCacheTime) < CONFIG_CACHE_TTL) {
    return configCache;
  }

  try {
    const data = require('fs').readFileSync(CONFIG_PATH, 'utf8');
    configCache = JSON.parse(data);
    configCacheTime = now;
    return configCache;
  } catch (err) {
    if (err.code === 'ENOENT') {
      configCache = DEFAULT_CONFIG;
      configCacheTime = now;
      return configCache;
    }
    return DEFAULT_CONFIG;
  }
}

async function saveConfigAsync(cfg) {
  configCache = cfg;
  configCacheTime = Date.now();
  await fs.writeFile(CONFIG_PATH, JSON.stringify(cfg, null, 2));
}

function saveConfig(cfg) {
  configCache = cfg;
  configCacheTime = Date.now();
  require('fs').writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2));
}

module.exports = { loadConfig, loadConfigAsync, saveConfig, saveConfigAsync };
