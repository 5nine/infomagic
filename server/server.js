const express = require('express');
const session = require('express-session');
const path = require('path');

const { requireRole } = require('./auth');
const { loadConfig, saveConfig } = require('./config');
const { upload, handleUpload, listImages, deleteImage } = require('./images');
const system = require('./system');

const app = express();
const PORT = 3000;

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use(session({
  secret: 'infomagic-secret',
  resave: false,
  saveUninitialized: false
}));

app.use('/images', express.static(path.join(__dirname, '../public/images')));
app.use('/ui', express.static(path.join(__dirname, '../public/ui')));

/* --- TEMP: enkel login för test --- */
app.post('/login', (req, res) => {
  const role = req.body.role === 'admin' ? 'admin' : 'editor';
  req.session.user = { role };
  res.json({ ok: true, role });
});

/* --- Images --- */
app.post('/api/images/upload',
  requireRole(['admin', 'editor']),
  upload.array('images'),
  handleUpload
);

app.get('/api/images', listImages);

/* --- Config --- */
app.get('/api/config', (req, res) => {
  res.json(loadConfig());
});

app.post('/api/config',
  requireRole(['admin']),
  (req, res) => {
    const cfg = loadConfig();
    Object.assign(cfg, req.body);
    saveConfig(cfg);
    res.json({ ok: true });
  }
);

app.delete('/api/images/:id',
  requireRole(['admin','editor']),
  deleteImage
);

const { getWeather } = require('./weather');

app.get('/api/weather', async (req, res) => {
  try {
    res.json(await getWeather());
  } catch {
    res.status(500).json({ error: 'Väder ej tillgängligt' });
  }
});

const slideshow = require('./slideshow');

app.get('/api/slideshow', slideshow.getState);
app.post('/api/slideshow', slideshow.control);


/* --- System (admin only) --- */
app.post('/api/system/reboot', requireRole(['admin']), system.reboot);
app.post('/api/system/tv/on', requireRole(['admin']), system.tvOn);
app.post('/api/system/tv/off', requireRole(['admin']), system.tvOff);
app.post('/api/system/touch/on', requireRole(['admin']), system.touchOn);
app.post('/api/system/touch/off', requireRole(['admin']), system.touchOff);

app.listen(PORT, () => {
  console.log(`InfoMagic backend running on port ${PORT}`);
});
