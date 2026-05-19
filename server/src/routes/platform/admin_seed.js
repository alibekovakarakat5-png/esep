/**
 * Одноразовый эндпоинт для создания enterprise-юзера на проде.
 *
 * POST /api/platform/admin-seed/courier-demo
 * Header: x-admin-secret: <PLATFORM_ADMIN_SECRET из env>
 *
 * Создаёт User с tier='enterprise' + linked platform_api_key.
 * Идемпотентен — повторный вызов обновит пароль и создаст новый ключ.
 *
 * Удалить из роутера после первого успешного запуска.
 */

const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const db = require('../../db');

const ALL_FEATURES = [
  'iin_validate', 'taxpayer_info', 'income_limit', 'process_payment',
  'fiscalize', 'cancel_receipt', 'receipt_status',
  'self_employed_registry', 'benefits',
];

router.post('/courier-demo', async (req, res) => {
  const secret = req.headers['x-admin-secret'];
  // Защита: либо явный PLATFORM_ADMIN_SECRET, либо JWT_SECRET (он точно задан)
  const expected = process.env.PLATFORM_ADMIN_SECRET || process.env.JWT_SECRET;
  if (!secret || secret !== expected) {
    return res.status(403).json({ error: 'forbidden' });
  }

  const email = req.body?.email || 'kurier-demo@esepkz.com';
  const password = req.body?.password || 'DemoKurier2026!';
  const name = req.body?.name || 'ТОО "Демо Курьерская Служба"';
  const bin = req.body?.bin || '200940012345';

  try {
    const passwordHash = await bcrypt.hash(password, 10);

    const { rows: userRows } = await db.query(
      `INSERT INTO users (email, name, password_hash, tier)
       VALUES ($1, $2, $3, 'enterprise')
       ON CONFLICT (email) DO UPDATE SET
         tier = 'enterprise',
         password_hash = EXCLUDED.password_hash,
         name = EXCLUDED.name
       RETURNING id, email, tier`,
      [email, name, passwordHash],
    );
    const userId = userRows[0].id;

    // Деактивируем старые ключи юзера
    await db.query(
      `UPDATE platform_api_keys SET is_active = FALSE WHERE user_id = $1`,
      [userId],
    );

    const apiKey = 'wkc_' + crypto.randomBytes(20).toString('hex');
    await db.query(
      `INSERT INTO platform_api_keys
         (user_id, api_key, client_name, client_bin, tier, features,
          monthly_quota, contact_email, notes, is_active)
       VALUES ($1, $2, $3, $4, 'enterprise', $5::jsonb, 10000, $6, $7, TRUE)`,
      [
        userId, apiKey, name, bin,
        JSON.stringify(ALL_FEATURES),
        email,
        `Enterprise demo client. Создан через admin-seed endpoint.`,
      ],
    );

    return res.json({
      ok: true,
      user_id: userId,
      email,
      password_note: 'Сохранён в БД с bcrypt',
      api_key: apiKey,
      tier: 'enterprise',
      login_url: 'https://api.esepkz.com/platform.html',
    });
  } catch (err) {
    console.error('[admin-seed] error:', err.message);
    return res.status(500).json({ error: err.message });
  }
});

module.exports = router;
