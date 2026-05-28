// ── Partner-программа ───────────────────────────────────────────────────────
//
// Партнёр (бухгалтерская фирма) создаёт промокод, шлёт клиентам.
// Клиент активирует — получает скидку/бесплатный период, партнёру
// начисляется комиссия в копилку.
//
// Endpoints (все требуют partner-аккаунт):
//   GET  /api/partner/dashboard       — статистика и заработок
//   GET  /api/partner/promos           — мои промокоды
//   POST /api/partner/promos           — создать новый промокод
//   GET  /api/partner/activations      — список активаций моих кодов

const router = require('express').Router();
const crypto = require('crypto');
const db     = require('../db');
const authMiddleware = require('../middleware/auth');

// Доля комиссии партнёра по умолчанию
const DEFAULT_COMMISSION_PCT = 30;

// Цена тарифа (₸/мес) — единый источник истины
const TIER_PRICES = {
  free: 0,
  solo: 1900,
  accountant: 4900,
  accountant_pro: 14900,
  enterprise: 200000,
};

// ── Миграция: добавляем нужные колонки ────────────────────────────────────
async function migratePartner() {
  await db.query(`
    -- Флаг партнёра у пользователя
    ALTER TABLE users ADD COLUMN IF NOT EXISTS is_partner BOOLEAN NOT NULL DEFAULT FALSE;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS partner_commission_pct INT NOT NULL DEFAULT 30;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS partner_company_name TEXT;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS partner_payout_method TEXT;

    -- Привязка промокода к партнёру (NULL = админский, не партнёрский)
    ALTER TABLE promo_codes ADD COLUMN IF NOT EXISTS partner_user_id UUID
      REFERENCES users(id) ON DELETE SET NULL;
    CREATE INDEX IF NOT EXISTS idx_promo_partner ON promo_codes(partner_user_id);
  `);
  console.log('[partner] migration done');
}

// ── Middleware: только для партнёров ──────────────────────────────────────
async function requirePartner(req, res, next) {
  if (!req.user?.id) return res.status(401).json({ error: 'Не авторизован' });
  const r = await db.query(
    'SELECT is_partner, partner_commission_pct, partner_company_name FROM users WHERE id = $1',
    [req.user.id],
  );
  if (!r.rows[0]?.is_partner) {
    return res.status(403).json({
      error: 'NOT_A_PARTNER',
      message: 'У вашего аккаунта нет партнёрского статуса. Свяжитесь с Esep для подключения.',
    });
  }
  req.partner = r.rows[0];
  next();
}

// ── GET /api/partner/dashboard — главная статистика ───────────────────────
router.get('/dashboard', authMiddleware, requirePartner, async (req, res) => {
  try {
    const userId = req.user.id;

    // 1. Список моих промокодов с использованием
    const promos = await db.query(
      `SELECT p.id, p.code, p.grant_tier, p.duration_days, p.used_count, p.created_at,
              (SELECT COUNT(*) FROM promo_usages WHERE promo_id = p.id) AS actual_uses
         FROM promo_codes p
        WHERE p.partner_user_id = $1
        ORDER BY p.created_at DESC`,
      [userId],
    );

    // 2. Активации с привязкой к тарифу — для расчёта комиссии
    const activations = await db.query(
      `SELECT pu.user_id, pu.activated_at, pu.expires_at,
              p.code, p.grant_tier, p.duration_days,
              u.email AS client_email
         FROM promo_usages pu
         JOIN promo_codes p ON p.id = pu.promo_id
         LEFT JOIN users u ON u.id = pu.user_id
        WHERE p.partner_user_id = $1
        ORDER BY pu.activated_at DESC`,
      [userId],
    );

    // 3. Расчёт комиссии
    const pct = req.partner.partner_commission_pct || DEFAULT_COMMISSION_PCT;
    let totalEarned = 0;
    let monthEarned = 0;
    let activeClients = 0;
    const now = Date.now();
    const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1).getTime();

    for (const a of activations.rows) {
      const tierPrice = TIER_PRICES[a.grant_tier] || 0;
      const monthly = (tierPrice * pct) / 100;
      const expiresMs = a.expires_at ? new Date(a.expires_at).getTime() : 0;
      const activatedMs = new Date(a.activated_at).getTime();

      // Считаем сколько месяцев прошло между активацией и сейчас (но не более срока)
      const endMs = Math.min(now, expiresMs);
      const startMs = activatedMs;
      const monthsActive = Math.max(0, (endMs - startMs) / (1000 * 60 * 60 * 24 * 30));
      totalEarned += monthly * monthsActive;

      if (expiresMs > now) {
        activeClients++;
        // Доход за этот месяц (с monthStart до сегодня, либо начала подписки)
        const startThis = Math.max(monthStart, startMs);
        const endThis = Math.min(now, expiresMs);
        if (endThis > startThis) {
          const monthsThis = (endThis - startThis) / (1000 * 60 * 60 * 24 * 30);
          monthEarned += monthly * monthsThis;
        }
      }
    }

    res.json({
      partner: {
        company_name: req.partner.partner_company_name,
        commission_pct: pct,
      },
      stats: {
        total_promos: promos.rows.length,
        total_activations: activations.rows.length,
        active_clients: activeClients,
        earned_total: Math.round(totalEarned),
        earned_this_month: Math.round(monthEarned),
        // Прогноз: если ещё 5 клиентов добавится
        projected_next_month: Math.round(activeClients * (TIER_PRICES.solo * pct / 100)),
      },
      promos: promos.rows.map((p) => ({
        id: p.id,
        code: p.code,
        grant_tier: p.grant_tier,
        duration_days: p.duration_days,
        activations: parseInt(p.actual_uses, 10) || 0,
        created_at: p.created_at,
      })),
      recent_activations: activations.rows.slice(0, 20).map((a) => ({
        client_email: a.client_email,
        code: a.code,
        tier: a.grant_tier,
        activated_at: a.activated_at,
        expires_at: a.expires_at,
        monthly_commission: Math.round((TIER_PRICES[a.grant_tier] || 0) * pct / 100),
      })),
    });
  } catch (err) {
    console.error('GET /partner/dashboard error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── POST /api/partner/promos — создать промокод ───────────────────────────
router.post('/promos', authMiddleware, requirePartner, async (req, res) => {
  try {
    const { code, grant_tier = 'solo', duration_days = 30, description = '' } = req.body ?? {};

    if (!code || !/^[A-Z0-9_-]{3,24}$/i.test(String(code).trim())) {
      return res.status(400).json({ error: 'Код должен быть 3-24 символа (буквы, цифры, _, -)' });
    }
    if (!['solo', 'accountant', 'accountant_pro'].includes(grant_tier)) {
      return res.status(400).json({ error: 'grant_tier должен быть solo/accountant/accountant_pro' });
    }
    if (duration_days < 7 || duration_days > 365) {
      return res.status(400).json({ error: 'duration_days в диапазоне 7-365 дней' });
    }

    const { rows } = await db.query(
      `INSERT INTO promo_codes
         (code, grant_tier, duration_days, max_uses, description, partner_user_id, active)
       VALUES (UPPER($1), $2, $3, 0, $4, $5, TRUE)
       RETURNING id, code, grant_tier, duration_days, created_at`,
      [code.trim(), grant_tier, duration_days, description, req.user.id],
    );

    res.status(201).json(rows[0]);
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'Такой промокод уже существует' });
    }
    console.error('POST /partner/promos error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── POST /api/partner/promos/generate — сгенерировать рандомный код ───────
router.post('/promos/generate', authMiddleware, requirePartner, async (req, res) => {
  try {
    const company = (req.partner.partner_company_name || 'PARTNER')
      .toUpperCase()
      .replace(/[^A-Z0-9]/g, '')
      .slice(0, 8);
    const suffix = crypto.randomBytes(2).toString('hex').toUpperCase();
    const code = `${company}-${suffix}`;
    const { rows } = await db.query(
      `INSERT INTO promo_codes
         (code, grant_tier, duration_days, max_uses, description, partner_user_id, active)
       VALUES ($1, 'solo', 30, 0, 'Сгенерирован партнёром', $2, TRUE)
       RETURNING id, code, grant_tier, duration_days, created_at`,
      [code, req.user.id],
    );
    res.json(rows[0]);
  } catch (err) {
    console.error('POST /partner/promos/generate error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

module.exports = { router, migratePartner };
