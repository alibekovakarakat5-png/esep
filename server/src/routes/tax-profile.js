// ── /api/tax-profile ────────────────────────────────────────────────────────
// GET    — мой профиль (или дефолт если ещё не сохранён)
// PUT    — сохранить/обновить профиль

const router = require('express').Router();
const db = require('../db');

function requireUser(req, res) {
  const id = req.user?.id;
  if (!id) { res.status(401).json({ error: 'Требуется авторизация' }); return null; }
  return id;
}

const DEFAULT_PROFILE = {
  entity_type: 'ip',
  regime: '910',
  size_category: 'small',
  has_employees: false,
  is_vat_payer: false,
  employees_count: 0,
  annual_revenue: null,
};

router.get('/', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  try {
    const r = await db.query(
      `SELECT entity_type, regime, size_category, has_employees, is_vat_payer,
              employees_count, annual_revenue, updated_at
         FROM company_tax_profile WHERE user_id = $1`,
      [userId]
    );
    if (r.rows.length === 0) return res.json({ ...DEFAULT_PROFILE, exists: false });
    res.json({ ...r.rows[0], exists: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

const ALLOWED_ENTITY  = ['ip', 'too', 'individual'];
const ALLOWED_REGIME  = ['esp', 'self_employed', '910', 'oyr', 'retail', null];
const ALLOWED_SIZE    = ['small', 'medium', 'large', null];

router.put('/', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  const {
    entity_type, regime, size_category, has_employees, is_vat_payer,
    employees_count, annual_revenue,
  } = req.body || {};

  if (entity_type && !ALLOWED_ENTITY.includes(entity_type)) {
    return res.status(400).json({ error: `entity_type должен быть из ${ALLOWED_ENTITY.join('/')}` });
  }
  if (regime !== undefined && !ALLOWED_REGIME.includes(regime)) {
    return res.status(400).json({ error: `regime должен быть из ${ALLOWED_REGIME.join('/')} или null` });
  }
  if (size_category !== undefined && !ALLOWED_SIZE.includes(size_category)) {
    return res.status(400).json({ error: `size_category должен быть из ${ALLOWED_SIZE.join('/')} или null` });
  }

  try {
    const r = await db.query(
      `INSERT INTO company_tax_profile
         (user_id, entity_type, regime, size_category, has_employees, is_vat_payer,
          employees_count, annual_revenue)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT (user_id) DO UPDATE
         SET entity_type     = COALESCE(EXCLUDED.entity_type, company_tax_profile.entity_type),
             regime          = EXCLUDED.regime,
             size_category   = EXCLUDED.size_category,
             has_employees   = COALESCE(EXCLUDED.has_employees, company_tax_profile.has_employees),
             is_vat_payer    = COALESCE(EXCLUDED.is_vat_payer, company_tax_profile.is_vat_payer),
             employees_count = COALESCE(EXCLUDED.employees_count, company_tax_profile.employees_count),
             annual_revenue  = COALESCE(EXCLUDED.annual_revenue, company_tax_profile.annual_revenue),
             updated_at      = NOW()
       RETURNING *`,
      [
        userId,
        entity_type || 'ip',
        regime ?? null,
        size_category ?? null,
        !!has_employees,
        !!is_vat_payer,
        employees_count != null ? Number(employees_count) : 0,
        annual_revenue != null ? Number(annual_revenue) : null,
      ]
    );
    res.json({ ...r.rows[0], exists: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
