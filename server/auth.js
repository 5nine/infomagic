const fs = require('fs');
const path = require('path');
const bcrypt = require('bcrypt');

const USERS_PATH = path.join(__dirname, '../config/users.json');

// Default password hash for "password" (bcrypt with 10 rounds)
const DEFAULT_PASSWORD_HASH = bcrypt.hashSync('password', 10);

function getDefaultUsers() {
  return {
    users: [
      { username: 'admin', role: 'admin', passwordHash: DEFAULT_PASSWORD_HASH },
      { username: 'editor', role: 'editor', passwordHash: DEFAULT_PASSWORD_HASH }
    ]
  };
}

function loadUsers() {
  try {
    if (!fs.existsSync(USERS_PATH)) {
      return getDefaultUsers();
    }
    const data = fs.readFileSync(USERS_PATH, 'utf8');
    const parsed = JSON.parse(data);
    // If users array is empty or missing, use defaults
    if (!parsed.users || parsed.users.length === 0) {
      return getDefaultUsers();
    }
    return parsed;
  } catch (err) {
    // On any error, fall back to defaults
    return getDefaultUsers();
  }
}

async function verifyCredentials(username, password) {
  const { users } = loadUsers();
  const user = users.find(u => u.username === username);
  
  if (!user) {
    return null;
  }
  
  const match = await bcrypt.compare(password, user.passwordHash);
  if (!match) {
    return null;
  }
  
  return { username: user.username, role: user.role };
}

function requireRole(allowed) {
  return (req, res, next) => {
    if (!req.session.user) {
      return res.status(401).json({ error: 'Ej inloggad' });
    }
    if (!allowed.includes(req.session.user.role)) {
      return res.status(403).json({ error: 'Åtkomst nekad' });
    }
    next();
  };
}

module.exports = { requireRole, verifyCredentials };
