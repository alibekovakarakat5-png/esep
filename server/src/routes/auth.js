const router  = require('express').Router();
const bcrypt  = require('bcryptjs');
const jwt     = require('jsonwebtoken');
const db      = require('../db');
const authMiddleware = require('../middleware/auth');
const tg      = require('../bot/telegram');

const sign = (userId) =>
  jwt.sign({ sub: userId }, process.env.JWT_SECRET, { expiresIn: '30d' });

// POST /api/auth/register
const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

router.post('/register', async (req, res) => {
  try {
    const { email, password, name = '' } = req.body ?? {};

    if (!email || !emailRegex.test(email.trim())) {
      return res.status(400).json({ error: 'Укажите корректный email' });
    }

    if (!password || password.length < 6) {
      return res.status(400).json({ error: 'Пароль должен содержать минимум 6 символов' });
    }

    // BUG 3: normalize email at the start and use everywhere
    const normalizedEmail = email.toLowerCase().trim();

    const exists = await db.query('SELECT id FROM users WHERE email = $1', [normalizedEmail]);
    if (exists.rows.length) {
      return res.status(409).json({ error: 'Email уже зарегистрирован' });
    }

    const hash = await bcrypt.hash(password, 12);
    const { rows } = await db.query(
      'INSERT INTO users (email, name, password_hash) VALUES ($1, $2, $3) RETURNING id, tier',
      [normalizedEmail, name.trim(), hash],
    );

    tg.notifyNewUser({ email: normalizedEmail, name });
    res.status(201).json({ token: sign(rows[0].id), userId: rows[0].id, tier: rows[0].tier });
  } catch (err) {
    console.error('POST /auth/register error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body ?? {};

    if (!email || !emailRegex.test(email.trim())) {
      return res.status(400).json({ error: 'Укажите корректный email' });
    }

    if (!password) {
      return res.status(400).json({ error: 'email и password обязательны' });
    }

    // BUG 3: normalize email
    const normalizedEmail = email.toLowerCase().trim();

    const { rows } = await db.query(
      'SELECT id, password_hash, tier FROM users WHERE email = $1',
      [normalizedEmail],
    );
    if (!rows.length) {
      return res.status(401).json({ error: 'Неверный email или пароль' });
    }

    const ok = await bcrypt.compare(password, rows[0].password_hash);
    if (!ok) return res.status(401).json({ error: 'Неверный email или пароль' });

    res.json({ token: sign(rows[0].id), userId: rows[0].id, tier: rows[0].tier });
  } catch (err) {
    console.error('POST /auth/login error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// GET /api/auth/me  — проверяет токен и возвращает актуальный тариф
router.get('/me', authMiddleware, async (req, res) => {
  try {
    const { rows } = await db.query(
      'SELECT id, email, name, tier FROM users WHERE id = $1',
      [req.userId],
    );
    if (!rows.length) return res.status(404).json({ error: 'User not found' });
    res.json(rows[0]);
  } catch (err) {
    console.error('GET /auth/me error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

module.exports = router;
