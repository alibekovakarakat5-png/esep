const router = require('express').Router();
const db     = require('../db');
const { adminAuth } = require('./admin');

// Default seed values — used on first run
const SEED = [
  { key: 'mrp',                 value: '4325',   label: 'МРП (₸)' },
  { key: 'mzp',                 value: '85000',  label: 'МЗП (₸)' },
  { key: 'ipn_rate_910',        value: '0.015',  label: 'ИПН 910 (доля)' },
  { key: 'sn_rate_910',         value: '0.015',  label: 'СН 910 (доля)' },
  { key: 'opv_rate',            value: '0.10',   label: 'ОПВ ставка' },
  { key: 'opvr_rate',           value: '0.035',  label: 'ОПВР ставка (2026)' },
  { key: 'so_rate',             value: '0.05',   label: 'СО ставка' },
  { key: 'vosms_rate_self',     value: '0.05',   label: 'ВОСМС за себя (ставка)' },
  { key: 'vosms_base_mult',     value: '1.4',    label: 'ВОСМС за себя (база ×МЗП)' },
  { key: 'emp_opvr_rate',       value: '0.035',  label: 'ОПВР работодатель' },
  { key: 'emp_so_rate',         value: '0.05',   label: 'СО работодатель' },
  { key: 'emp_vosms_rate',      value: '0.03',   label: 'ООСМС работодатель' },
  { key: 'emp_vosms_max_mult',  value: '40',     label: 'ООСМС макс. база (×МЗП)' },
  { key: 'ee_opv_rate',         value: '0.10',   label: 'ОПВ с сотрудника' },
  { key: 'ee_vosms_rate',       value: '0.02',   label: 'ВОСМС с сотрудника' },
  { key: 'ee_vosms_max_mult',   value: '20',     label: 'ВОСМС макс. база (×МЗП)' },
  { key: 'esp_mrp_city_mult',   value: '1',      label: 'ЕСП город (×МРП/мес)' },
  { key: 'esp_mrp_rural_mult',  value: '0.5',    label: 'ЕСП село (×МРП/мес)' },
  { key: 'esp_year_mrp_limit',  value: '1175',   label: 'ЕСП лимит дохода (МРП/год)' },
  { key: 'self_emp_rate',       value: '0.04',   label: 'Самозанятый ставка' },
  { key: 'self_emp_year_limit', value: '3528',   label: 'Самозанятый лимит (МРП/год)' },
  { key: 'vat_rate',            value: '0.12',   label: 'НДС ставка' },
  { key: 'vat_threshold_mrp',   value: '20000',  label: 'НДС порог (МРП/год)' },
  { key: 'general_ipn_rate',    value: '0.10',   label: 'ОУР ИПН ставка' },
  { key: '910_half_year_mrp',   value: '24038',  label: '910 лимит полугодие (МРП)' },
  { key: '910_max_employees',   value: '30',     label: '910 макс. сотрудников' },
];

// ── GET /api/config/tax — public ──────────────────────────────────────────────
router.get('/', async (_req, res) => {
  const { rows } = await db.query(
    'SELECT key, value, label, updated_at FROM tax_config ORDER BY id',
  );
  // Return as key→value map for easy consumption
  const config = {};
  for (const r of rows) config[r.key] = { value: r.value, label: r.label, updatedAt: r.updated_at };
  res.json(config);
});

// ── PUT /api/config/tax/:key — admin only ─────────────────────────────────────
router.put('/:key', adminAuth, async (req, res) => {
  const { value } = req.body ?? {};
  if (value === undefined) return res.status(400).json({ error: 'value required' });

  const { rowCount } = await db.query(
    `UPDATE tax_config SET value = $1, updated_at = NOW() WHERE key = $2`,
    [String(value), req.params.key],
  );
  if (rowCount === 0) return res.status(404).json({ error: 'Unknown key' });
  res.json({ ok: true });
});

// ── PUT /api/config/tax — bulk update (admin) ─────────────────────────────────
router.put('/', adminAuth, async (req, res) => {
  const updates = req.body; // { key: value, ... }
  if (!updates || typeof updates !== 'object') return res.status(400).json({ error: 'object required' });

  for (const [key, value] of Object.entries(updates)) {
    await db.query(
      `UPDATE tax_config SET value = $1, updated_at = NOW() WHERE key = $2`,
      [String(value), key],
    );
  }
  res.json({ ok: true });
});

// ── Seed helper — called from migrate() ──────────────────────────────────────
async function seedTaxConfig() {
  for (const row of SEED) {
    await db.query(
      `INSERT INTO tax_config (key, value, label)
       VALUES ($1, $2, $3)
       ON CONFLICT (key) DO NOTHING`,
      [row.key, row.value, row.label],
    );
  }
}

module.exports = { router, seedTaxConfig };
