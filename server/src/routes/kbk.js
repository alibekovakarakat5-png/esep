// ── /api/kbk ────────────────────────────────────────────────────────────────
// GET  /api/kbk/list                          — справочник КБК (всё)
// POST /api/kbk/recommend                     — рекомендация по профилю
//   body: { profile, payment_type }
//   resp: { recommended, alternatives, reason }
// POST /api/kbk/validate                      — валидация КБК пользователя
//   body: { profile, code, payment_type? }
//   resp: { ok, level, message, expected? }
// GET  /api/kbk/payment-types                 — справочник типов платежей
// GET  /api/kbk/for-me                        — все КБК для текущего пользователя
//   (если есть профиль компании в БД)

const router = require('express').Router();
const db = require('../db');

const {
  KBK,
  PAYMENT_TYPE_LABELS,
  listKbkForProfile,
  recommendKbk,
  validateKbk,
} = require('../services/kbk_recommender');

// ── Загрузка профиля пользователя из БД ─────────────────────────────────────

async function loadProfileFromDb(userId) {
  if (!userId) return null;
  try {
    const r = await db.query(
      `SELECT entity_type, regime, size_category, has_employees, is_vat_payer
         FROM company_tax_profile
        WHERE user_id = $1`,
      [userId]
    );
    if (r.rows.length === 0) return null;
    return r.rows[0];
  } catch {
    return null;
  }
}

// ── GET /list ───────────────────────────────────────────────────────────────

router.get('/list', (_req, res) => {
  res.json(KBK);
});

router.get('/payment-types', (_req, res) => {
  const items = Object.entries(PAYMENT_TYPE_LABELS).map(([id, label]) => ({ id, label }));
  res.json(items);
});

// ── POST /recommend ─────────────────────────────────────────────────────────

router.post('/recommend', (req, res) => {
  const { profile, payment_type } = req.body || {};
  if (!profile || !payment_type) {
    return res.status(400).json({ error: 'profile и payment_type обязательны' });
  }
  const result = recommendKbk(profile, payment_type);
  res.json(result);
});

// ── POST /validate ──────────────────────────────────────────────────────────

router.post('/validate', (req, res) => {
  const { profile, code, payment_type } = req.body || {};
  if (!profile || !code) {
    return res.status(400).json({ error: 'profile и code обязательны' });
  }
  res.json(validateKbk(profile, code, payment_type));
});

// ── GET /for-me ─────────────────────────────────────────────────────────────

router.get('/for-me', async (req, res) => {
  const userId = req.user?.id;
  const profile = await loadProfileFromDb(userId);
  if (!profile) {
    return res.json({ profile: null, items: [] });
  }
  res.json({ profile, items: listKbkForProfile(profile) });
});

module.exports = router;
