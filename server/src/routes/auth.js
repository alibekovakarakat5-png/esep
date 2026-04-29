const router  = require('express').Router();
const bcrypt  = require('bcryptjs');
const jwt     = require('jsonwebtoken');
const db      = require('../db');
const authMiddleware = require('../middleware/auth');
const tg      = require('../bot/telegram');
const { normalizeTier } = require('../tiers');

const sign = (userId) =>
  jwt.sign({ sub: userId }, process.env.JWT_SECRET, { expiresIn: '30d' });

// POST /api/auth/register
const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Простая нормализация казахстанского телефона
function normalizePhone(s) {
  if (!s) return null;
  const digits = String(s).replace(/\D/g, '');
  if (!digits) return null;
  if (digits.length === 11 && (digits.startsWith('7') || digits.startsWith('8'))) {
    return '+7' + digits.slice(1);
  }
  if (digits.length === 10) return '+7' + digits;
  return '+' + digits;
}

router.post('/register', async (req, res) => {
  try {
    const { email, password, name = '', phone = null } = req.body ?? {};

    if (!email || !emailRegex.test(email.trim())) {
      return res.status(400).json({ error: 'Укажите корректный email' });
    }

    if (!password || password.length < 6) {
      return res.status(400).json({ error: 'Пароль должен содержать минимум 6 символов' });
    }

    const normalizedEmail = email.toLowerCase().trim();
    const normalizedPhone = normalizePhone(phone);

    const exists = await db.query('SELECT id FROM users WHERE email = $1', [normalizedEmail]);
    if (exists.rows.length) {
      return res.status(409).json({ error: 'Email уже зарегистрирован' });
    }

    const hash = await bcrypt.hash(password, 12);
    const { rows } = await db.query(
      `INSERT INTO users (email, name, password_hash, phone, trial_started_at, trial_expires_at)
       VALUES ($1, $2, $3, $4, NOW(), NOW() + INTERVAL '7 days')
       RETURNING id, tier, trial_started_at, trial_expires_at, subscription_expires_at`,
      [normalizedEmail, name.trim(), hash, normalizedPhone],
    );

    tg.notifyNewUser({
      email: normalizedEmail,
      name,
      phone: normalizedPhone,
    });
    res.status(201).json({
      token: sign(rows[0].id),
      userId: rows[0].id,
      tier: normalizeTier(rows[0].tier),
      trialStartedAt: rows[0].trial_started_at,
      trialExpiresAt: rows[0].trial_expires_at,
      subscriptionExpiresAt: rows[0].subscription_expires_at,
    });
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
      `SELECT id, password_hash, tier, trial_started_at, trial_expires_at, subscription_expires_at
       FROM users WHERE email = $1`,
      [normalizedEmail],
    );
    if (!rows.length) {
      return res.status(401).json({ error: 'Неверный email или пароль' });
    }

    const ok = await bcrypt.compare(password, rows[0].password_hash);
    if (!ok) return res.status(401).json({ error: 'Неверный email или пароль' });

    res.json({
      token: sign(rows[0].id),
      userId: rows[0].id,
      tier: normalizeTier(rows[0].tier),
      trialStartedAt: rows[0].trial_started_at,
      trialExpiresAt: rows[0].trial_expires_at,
      subscriptionExpiresAt: rows[0].subscription_expires_at,
    });
  } catch (err) {
    console.error('POST /auth/login error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// GET /api/auth/me  — проверяет токен и возвращает актуальный тариф
router.get('/me', authMiddleware, async (req, res) => {
  try {
    const { rows } = await db.query(
      `SELECT id, email, name, tier, trial_started_at, trial_expires_at, subscription_expires_at
       FROM users WHERE id = $1`,
      [req.userId],
    );
    if (!rows.length) return res.status(404).json({ error: 'User not found' });
    const user = rows[0];
    res.json({
      id: user.id,
      email: user.email,
      name: user.name,
      tier: normalizeTier(user.tier),
      trialStartedAt: user.trial_started_at,
      trialExpiresAt: user.trial_expires_at,
      subscriptionExpiresAt: user.subscription_expires_at,
      isTrialActive: user.trial_expires_at ? new Date(user.trial_expires_at) > new Date() : false,
      isSubscriptionActive: user.subscription_expires_at ? new Date(user.subscription_expires_at) > new Date() : false,
    });
  } catch (err) {
    console.error('GET /auth/me error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

module.exports = router;
