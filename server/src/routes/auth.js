const router  = require('express').Router();
const bcrypt  = require('bcryptjs');
const jwt     = require('jsonwebtoken');
const db      = require('../db');

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
    'INSERT INTO users (email, name, password_hash) VALUES ($1, $2, $3) RETURNING id',
    [email.toLowerCase().trim(), name.trim(), hash],
  );

  res.status(201).json({ token: sign(rows[0].id), userId: rows[0].id });
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  const { email, password } = req.body ?? {};
  if (!email || !password) {
    return res.status(400).json({ error: 'email и password обязательны' });
  }

  const { rows } = await db.query(
    'SELECT id, password_hash FROM users WHERE email = $1',
    [email.toLowerCase().trim()],
  );
  if (!rows.length) {
    return res.status(401).json({ error: 'Неверный email или пароль' });
  }

  const ok = await bcrypt.compare(password, rows[0].password_hash);
  if (!ok) return res.status(401).json({ error: 'Неверный email или пароль' });

  res.json({ token: sign(rows[0].id), userId: rows[0].id });
});

module.exports = router;
