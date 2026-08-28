'use strict';

require('dotenv').config();
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const express = require('express');
const session = require('express-session');
const cookieParser = require('cookie-parser');

const ROOT = path.join(__dirname, '..');
const CONTENT_PATH = path.join(ROOT, 'data', 'content.json');
const PORT = Number(process.env.PORT) || 8080;
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'hydrowin-admin';
const SESSION_SECRET = process.env.SESSION_SECRET || crypto.randomBytes(32).toString('hex');

const app = express();

app.disable('x-powered-by');
app.use(express.json({ limit: '512kb' }));
app.use(cookieParser());
app.use(session({
  name: 'hydrowin.sid',
  secret: SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    maxAge: 8 * 60 * 60 * 1000
  }
}));

const loginAttempts = new Map();
const MAX_ATTEMPTS = 5;
const LOCK_MS = 15 * 60 * 1000;

function clientIp(req) {
  return req.ip || req.socket.remoteAddress || 'unknown';
}

function isLocked(ip) {
  const entry = loginAttempts.get(ip);
  if (!entry) return false;
  if (entry.count < MAX_ATTEMPTS) return false;
  if (Date.now() - entry.last > LOCK_MS) {
    loginAttempts.delete(ip);
    return false;
  }
  return true;
}

function recordFail(ip) {
  const entry = loginAttempts.get(ip) || { count: 0, last: 0 };
  entry.count += 1;
  entry.last = Date.now();
  loginAttempts.set(ip, entry);
}

function clearFails(ip) {
  loginAttempts.delete(ip);
}

function safeEqual(a, b) {
  const bufA = Buffer.from(String(a));
  const bufB = Buffer.from(String(b));
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

function requireAuth(req, res, next) {
  if (req.session && req.session.admin) return next();
  res.status(401).json({ error: 'Unauthorized' });
}

function readContent() {
  const raw = fs.readFileSync(CONTENT_PATH, 'utf8');
  return JSON.parse(raw);
}

function writeContent(data) {
  const tmp = CONTENT_PATH + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2) + '\n', 'utf8');
  fs.renameSync(tmp, CONTENT_PATH);
}

app.get('/api/content', (req, res) => {
  try {
    res.json(readContent());
  } catch (err) {
    res.status(500).json({ error: 'Cannot read content' });
  }
});

app.post('/api/admin/login', (req, res) => {
  const ip = clientIp(req);
  if (isLocked(ip)) {
    return res.status(429).json({ error: 'Слишком много попыток. Подождите 15 минут.' });
  }
  const password = req.body && req.body.password;
  if (!password || !safeEqual(password, ADMIN_PASSWORD)) {
    recordFail(ip);
    return res.status(401).json({ error: 'Неверный пароль' });
  }
  clearFails(ip);
  req.session.admin = true;
  res.json({ ok: true });
});

app.post('/api/admin/logout', (req, res) => {
  if (!req.session) {
    return res.json({ ok: true });
  }
  req.session.destroy(() => {
    res.clearCookie('hydrowin.sid');
    res.json({ ok: true });
  });
});

app.get('/api/admin/me', (req, res) => {
  res.json({ ok: !!(req.session && req.session.admin) });
});

app.put('/api/admin/content', requireAuth, (req, res) => {
  try {
    const data = req.body;
    if (!data || typeof data !== 'object') {
      return res.status(400).json({ error: 'Invalid JSON body' });
    }
    writeContent(data);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: 'Cannot save content' });
  }
});

app.use(express.static(ROOT, { index: 'index.html' }));

app.use((req, res) => {
  res.status(404).send('Not found');
});

app.listen(PORT, () => {
  console.log('ГидроВин сайт: http://localhost:' + PORT);
  console.log('Админка:       http://localhost:' + PORT + '/admin/');
  if (!process.env.ADMIN_PASSWORD) {
    console.log('Пароль по умолчанию: hydrowin-admin (задайте ADMIN_PASSWORD в .env)');
  }
});
