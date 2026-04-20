const router = require('express').Router();
const db     = require('../db');
const { adminAuth } = require('./admin');
const authMiddleware = require('../middleware/auth');
const { TIERS, normalizeTier } = require('../tiers');

// ── POST /api/promos/validate — check promo code (authenticated) ────────────
router.post('/validate', authMiddleware, async (req, res) => {
  try {
    const { code } = req.body ?? {};
    if (!code) return res.status(400).json({ error: 'code is required' });

    const { rows } = await db.query(
      `SELECT * FROM promo_codes
       WHERE UPPER(code) = UPPER($1)
         AND active = TRUE
         AND (expires_at IS NULL OR expires_at > NOW())`,
      [code.trim()],
    );

    if (rows.length === 0) {
      return res.status(404).json({ error: 'Промокод не найден или истёк' });
    }

    const promo = rows[0];

    // Check usage limit
    if (promo.max_uses > 0 && promo.used_count >= promo.max_uses) {
      return res.status(410).json({ error: 'Промокод использован максимальное количество раз' });
    }

    // Check if this user already used this code
    const { rows: existing } = await db.query(
      `SELECT 1 FROM promo_usages WHERE promo_id = $1 AND user_id = $2`,
      [promo.id, req.userId],
    );
    if (existing.length > 0) {
      return res.status(409).json({ error: 'Вы уже использовали этот промокод' });
    }

    res.json({
      valid: true,
      code: promo.code,
      tier: normalizeTier(promo.grant_tier),
      duration_days: promo.duration_days,
      description: promo.description,
    });
  } catch (err) {
    console.error('POST /promos/validate error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── POST /api/promos/activate — activate promo code (authenticated) ─────────
router.post('/activate', authMiddleware, async (req, res) => {
  try {
    const { code } = req.body ?? {};
    if (!code) return res.status(400).json({ error: 'code is required' });

    const { rows } = await db.query(
      `SELECT * FROM promo_codes
       WHERE UPPER(code) = UPPER($1)
         AND active = TRUE
         AND (expires_at IS NULL OR expires_at > NOW())`,
      [code.trim()],
    );

    if (rows.length === 0) {
      return res.status(404).json({ error: 'Промокод не найден или истёк' });
    }

    const promo = rows[0];

    if (promo.max_uses > 0 && promo.used_count >= promo.max_uses) {
      return res.status(410).json({ error: 'Промокод уже использован максимальное количество раз' });
    }

    // Check duplicate usage
    const { rows: existing } = await db.query(
      `SELECT 1 FROM promo_usages WHERE promo_id = $1 AND user_id = $2`,
      [promo.id, req.userId],
    );
    if (existing.length > 0) {
      return res.status(409).json({ error: 'Вы уже использовали этот промокод' });
    }

    // Calculate expiration
    const grantTier = normalizeTier(promo.grant_tier);
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + promo.duration_days);

    // Apply: upgrade user tier + record usage (in transaction)
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      // Update user tier and extend server-side access window.
      await client.query(
        `UPDATE users
            SET tier = $1,
                subscription_expires_at = GREATEST(COALESCE(subscription_expires_at, NOW()), NOW()) + ($2 || ' days')::INTERVAL
          WHERE id = $3`,
        [grantTier, promo.duration_days, req.userId],
      );

      // Record usage
      await client.query(
        `INSERT INTO promo_usages (promo_id, user_id, expires_at)
         VALUES ($1, $2, $3)`,
        [promo.id, req.userId, expiresAt],
      );

      // Increment used_count
      await client.query(
        `UPDATE promo_codes SET used_count = used_count + 1 WHERE id = $1`,
        [promo.id],
      );

      await client.query('COMMIT');
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }

    res.json({
      ok: true,
      tier: grantTier,
      expires_at: expiresAt.toISOString(),
      duration_days: promo.duration_days,
      message: `Тариф "${grantTier}" активирован на ${promo.duration_days} дней!`,
    });
  } catch (err) {
    console.error('POST /promos/activate error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── GET /api/promos — list all promo codes (admin) ──────────────────────────
router.get('/', adminAuth, async (_req, res) => {
  try {
    const { rows } = await db.query(
      `SELECT p.*,
              (SELECT COUNT(*) FROM promo_usages WHERE promo_id = p.id) AS actual_uses
       FROM promo_codes p
       ORDER BY p.created_at DESC`,
    );
    res.json(rows);
  } catch (err) {
    console.error('GET /promos error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── POST /api/promos — create promo code (admin) ───────────────────────────
router.post('/', adminAuth, async (req, res) => {
  try {
    const { code, grant_tier, duration_days, max_uses, description, expires_at } = req.body ?? {};

    if (!code || !grant_tier || !duration_days) {
      return res.status(400).json({ error: 'code, grant_tier, duration_days are required' });
    }
    const normalizedTier = normalizeTier(grant_tier);
    if (!TIERS.includes(normalizedTier)) {
      return res.status(400).json({ error: `grant_tier must be one of: ${TIERS.join(', ')}` });
    }

    const { rows } = await db.query(
      `INSERT INTO promo_codes (code, grant_tier, duration_days, max_uses, description, expires_at)
       VALUES (UPPER($1), $2, $3, $4, $5, $6)
       RETURNING *`,
      [code.trim(), normalizedTier, duration_days, max_uses ?? 0, description ?? '', expires_at ?? null],
    );

    res.status(201).json(rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'Промокод с таким кодом уже существует' });
    }
    console.error('POST /promos error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── DELETE /api/promos/:id — deactivate promo (admin) ──────────────────────
router.delete('/:id', adminAuth, async (req, res) => {
  try {
    await db.query(`UPDATE promo_codes SET active = FALSE WHERE id = $1`, [req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    console.error('DELETE /promos error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── Seed default launch promo ──────────────────────────────────────────────
async function seedPromos() {
  await db.query(`
    INSERT INTO promo_codes (code, grant_tier, duration_days, max_uses, description)
    VALUES
      ('REVIEW6', 'solo', 180, 100, 'Отзыв = 6 месяцев бесплатно (Solo)'),
      ('LAUNCH2026', 'solo', 30, 500, 'Запуск Esep — 1 месяц бесплатно'),
      ('ACCOUNTANT', 'accountant', 90, 50, 'Бухгалтерам — 3 месяца бесплатно')
    ON CONFLICT (code) DO NOTHING
  `);
}

module.exports = { router, seedPromos };
