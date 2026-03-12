const router  = require('express').Router();
const bcrypt  = require('bcryptjs');
const jwt     = require('jsonwebtoken');
const db      = require('../db');
const authMiddleware = require('../middleware/auth');

const sign = (userId) =>
  jwt.sign({ sub: userId }, process.env.JWT_SECRET, { expiresIn: '30d' });

// POST /api/auth/register
router.post('/register', async (req, res) => {
  const { email, password, name = '' } = req.body ?? {};
  if (!email || !password) {
    return res.status(400).json({ error: 'email и password обязательны' });
  }

  const exists = await db.query('SELECT id FROM users WHERE email = $1', [email]);
  if (exists.rows.length) {
    return res.status(409).json({ error: 'Email уже зарегистрирован' });
  }

  const hash = await bcrypt.hash(password, 12);
  const { rows } = await db.query(
    'INSERT INTO users (email, name, password_hash) VALUES ($1, $2, $3) RETURNING id, tier',
    [email.toLowerCase().trim(), name.trim(), hash],
  );

  res.status(201).json({ token: sign(rows[0].id), userId: rows[0].id, tier: rows[0].tier });
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  const { email, password } = req.body ?? {};
  if (!email || !password) {
    return res.status(400).json({ error: 'email и password обязательны' });
  }

  const { rows } = await db.query(
    'SELECT id, password_hash, tier FROM users WHERE email = $1',
    [email.toLowerCase().trim()],
  );
  if (!rows.length) {
    return res.status(401).json({ error: 'Неверный email или пароль' });
  }

  const ok = await bcrypt.compare(password, rows[0].password_hash);
  if (!ok) return res.status(401).json({ error: 'Неверный email или пароль' });

  res.json({ token: sign(rows[0].id), userId: rows[0].id, tier: rows[0].tier });
});

// GET /api/auth/me  — проверяет токен и возвращает актуальный тариф
router.get('/me', authMiddleware, async (req, res) => {
  const { rows } = await db.query(
    'SELECT id, email, name, tier FROM users WHERE id = $1',
    [req.userId],
  );
  if (!rows.length) return res.status(404).json({ error: 'User not found' });
  res.json(rows[0]);
});

module.exports = router;
