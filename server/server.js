const express = require('express');
const session = require('express-session');
const path = require('path');
const http = require('http');
const WebSocket = require('ws');

const { requireRole, verifyCredentials } = require('./auth');
const { loadConfig, saveConfig } = require('./config');
const {
  upload,
  handleUpload,
  listImages,
  deleteImage,
  updateImageOrder,
} = require('./images');
const system = require('./system');

const app = express();
const server = http.createServer(app);
const PORT = 3000;

// Limit request body size to prevent memory issues
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Add request timeout middleware
app.use((req, res, next) => {
  req.setTimeout(30000); // 30 second timeout
  res.setTimeout(30000);
  next();
});

app.use(
  session({
    secret: 'infomagic-secret',
    resave: false,
    saveUninitialized: false,
  }),
);

/* --- Helper middleware for HTML page authentication (redirects to login) --- */
function requireRoleRedirect(allowedRoles) {
  return (req, res, next) => {
    if (!req.session.user) {
      return res.redirect('/');
    }
    if (!allowedRoles.includes(req.session.user.role)) {
      return res.redirect('/');
    }
    next();
  };
}

/* --- HTML page routes (must be before static file serving) --- */
// Admin page - requires admin role
app.get('/ui/admin.html', requireRoleRedirect(['admin']), (req, res) => {
  res.sendFile(path.join(__dirname, '../public/ui/admin.html'));
});

// Editor page - requires editor role (admins also have access)
app.get(
  '/ui/editor.html',
  requireRoleRedirect(['editor', 'admin']),
  (req, res) => {
    res.sendFile(path.join(__dirname, '../public/ui/editor.html'));
  },
);

// Login page - public access
app.get('/ui/login.html', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/ui/login.html'));
});

// Touch page - public access (for touch interface)
app.get('/ui/touch.html', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/ui/touch.html'));
});

// TV page - public access (for TV display)
app.get('/ui/tv.html', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/ui/tv.html'));
});

// Index/login page - public access
app.get('/index.html', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

app.use('/images', express.static(path.join(__dirname, '../public/images')));
app.use('/assets', express.static(path.join(__dirname, '../public/assets')));
app.use('/ui', express.static(path.join(__dirname, '../public/ui')));
app.use(
  '/styles.css',
  express.static(path.join(__dirname, '../public/styles.css')),
);

/* --- Root route - serve login page or redirect if logged in --- */
app.get('/', (req, res) => {
  if (req.session.user) {
    // User is already logged in, redirect based on role
    if (req.session.user.role === 'admin') {
      return res.redirect('/ui/admin.html');
    } else if (req.session.user.role === 'editor') {
      return res.redirect('/ui/editor.html');
    }
  }
  // Not logged in, serve login page
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

/* --- Login --- */
app.post('/login', async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Användarnamn och lösenord krävs' });
  }

  const user = await verifyCredentials(username, password);

  if (!user) {
    return res
      .status(401)
      .json({ error: 'Felaktigt användarnamn eller lösenord' });
  }

  req.session.user = user;
  res.json({ ok: true, role: user.role, username: user.username });
});

/* --- Logout --- */
app.post('/logout', (req, res) => {
  req.session.destroy(err => {
    if (err) {
      return res.status(500).json({ error: 'Kunde inte logga ut' });
    }
    res.json({ ok: true });
  });
});

/* --- Images --- */
app.post(
  '/api/images/upload',
  requireRole(['admin', 'editor']),
  upload.array('images'),
  handleUpload,
);

app.get('/api/images', listImages);

app.post(
  '/api/images/order',
  requireRole(['admin', 'editor']),
  updateImageOrder,
);

/* --- Config --- */
app.get('/api/config', (req, res) => {
  res.json(loadConfig());
});

app.post('/api/config', requireRole(['admin', 'editor']), (req, res) => {
  const cfg = loadConfig();
  const user = req.session.user;
  
  // Editors can only update calendar.view, not calendarId or other config
  if (user.role === 'editor') {
    if (req.body.calendar && cfg.calendar && req.body.calendar.view) {
      // Only allow updating the view, preserve calendarId
      cfg.calendar.view = req.body.calendar.view;
    } else {
      return res.status(403).json({ error: 'Redaktörer kan endast ändra kalendervy' });
    }
  } else {
    // Admins can update everything
    if (req.body.calendar && cfg.calendar) {
      // Deep merge for calendar object
      Object.assign(cfg.calendar, req.body.calendar);
      delete req.body.calendar;
    }
    Object.assign(cfg, req.body);
  }
  
  saveConfig(cfg);
  res.json({ ok: true });
});

app.post(
  '/api/config/slideshow-interval',
  requireRole(['admin', 'editor']),
  (req, res) => {
    const { interval } = req.body;
    if (typeof interval !== 'number' || interval < 1 || interval > 300) {
      return res
        .status(400)
        .json({ error: 'Interval måste vara mellan 1 och 300 sekunder' });
    }
    const cfg = loadConfig();
    cfg.slideshowInterval = interval;
    saveConfig(cfg);
    res.json({ ok: true, slideshowInterval: interval });
  },
);

app.delete('/api/images/:id', requireRole(['admin', 'editor']), deleteImage);

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

/* --- WebSocket server for real-time communication --- */
const wss = new WebSocket.Server({ server });

// Broadcast function to send state to all connected clients
function broadcastState(state) {
  const message = JSON.stringify({ type: 'slideshow-state', state });
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
}

// Broadcast function to send image list updates to all connected clients
function broadcastImageList(data) {
  const message = JSON.stringify(data);
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
}

// Set up the broadcast callbacks
slideshow.setBroadcastCallback(broadcastState);
const { setBroadcastCallback: setImageBroadcastCallback } = require('./images');
setImageBroadcastCallback(broadcastImageList);

// Handle WebSocket connections
wss.on('connection', ws => {
  // Send current state immediately when client connects
  const currentState = slideshow.getStateSync();
  ws.send(JSON.stringify({ type: 'slideshow-state', state: currentState }));

  // Send current image list immediately when client connects
  const { listImagesSync } = require('./images');
  const imageList = listImagesSync();
  ws.send(JSON.stringify({ type: 'images-updated', images: imageList }));

  // Handle incoming messages (if needed in the future)
  ws.on('message', message => {
    try {
      const data = JSON.parse(message);
      // Handle client messages if needed
    } catch (err) {
      console.error('Invalid WebSocket message:', err);
    }
  });

  ws.on('error', err => {
    console.error('WebSocket error:', err);
  });
});

/* --- System (admin only) --- */
app.post('/api/system/reboot', requireRole(['admin']), system.reboot);
app.post('/api/system/tv/on', requireRole(['admin']), system.tvOn);
app.post('/api/system/tv/off', requireRole(['admin']), system.tvOff);
app.post('/api/system/touch/on', requireRole(['admin']), system.touchOn);
app.post('/api/system/touch/off', requireRole(['admin']), system.touchOff);

server.listen(PORT, () => {
  console.log(`InfoMagic backend running on port ${PORT}`);
  console.log(`WebSocket server ready for real-time communication`);
});
