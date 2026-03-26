const router = require('express').Router();
const db     = require('../db');
const { adminAuth } = require('./admin');

// Default seed values — Новый НК РК 2026 (Закон 214-VIII от 18.07.2025)
// Обновлено: март 2026
const SEED = [
  // ── Базовые показатели ──
  { key: 'mrp',                 value: '4325',   label: 'МРП (₸)' },
  { key: 'mzp',                 value: '85000',  label: 'МЗП (₸)' },

  // ── Упрощёнка (910) ──
  { key: 'ipn_rate_910',        value: '0.04',   label: 'Ставка 910 (100% ИПН, СН=0)' },
  { key: 'sn_rate_910',         value: '0',      label: 'СН 910 (отменён с 2026)' },
  { key: '910_year_mrp',        value: '600000', label: '910 лимит годовой (МРП)' },
  { key: '910_max_employees',   value: '999999', label: '910 макс. сотрудников (без ограничений)' },

  // ── Соцплатежи за себя ──
  { key: 'opv_rate',            value: '0.10',   label: 'ОПВ ставка' },
  { key: 'opvr_rate',           value: '0.035',  label: 'ОПВР ставка (2026)' },
  { key: 'so_rate',             value: '0.05',   label: 'СО ставка' },
  { key: 'vosms_rate_self',     value: '0.05',   label: 'ВОСМС за себя (ставка)' },
  { key: 'vosms_base_mult',     value: '1.4',    label: 'ВОСМС за себя (база ×МЗП)' },

  // ── Соцплатежи за сотрудников ──
  { key: 'emp_opvr_rate',       value: '0.035',  label: 'ОПВР работодатель' },
  { key: 'emp_so_rate',         value: '0.05',   label: 'СО работодатель' },
  { key: 'emp_vosms_rate',      value: '0.03',   label: 'ООСМС работодатель' },
  { key: 'emp_vosms_max_mult',  value: '40',     label: 'ООСМС макс. база (×МЗП)' },
  { key: 'ee_opv_rate',         value: '0.10',   label: 'ОПВ с сотрудника' },
  { key: 'ee_vosms_rate',       value: '0.02',   label: 'ВОСМС с сотрудника' },
  { key: 'ee_vosms_max_mult',   value: '20',     label: 'ВОСМС макс. база (×МЗП)' },

  // ── ЕСП ──
  { key: 'esp_mrp_city_mult',   value: '1',      label: 'ЕСП город (×МРП/мес)' },
  { key: 'esp_mrp_rural_mult',  value: '0.5',    label: 'ЕСП село (×МРП/мес)' },
  { key: 'esp_year_mrp_limit',  value: '1175',   label: 'ЕСП лимит дохода (МРП/год)' },

  // ── Самозанятые ──
  { key: 'self_emp_rate',       value: '0.04',   label: 'Самозанятый ставка' },
  { key: 'self_emp_year_limit', value: '3600',   label: 'Самозанятый лимит (МРП/год)' },

  // ── НДС (новый НК РК 2026) ──
  { key: 'vat_rate',            value: '0.16',   label: 'НДС ставка (16% с 2026)' },
  { key: 'vat_threshold_mrp',   value: '10000',  label: 'НДС порог (МРП/год)' },

  // ── ОУР — прогрессивная шкала ИПН ──
  { key: 'general_ipn_rate',    value: '0.10',   label: 'ОУР ИПН базовая ставка' },
  { key: 'general_ipn_rate_high', value: '0.15', label: 'ОУР ИПН повышенная ставка' },
  { key: 'general_ipn_threshold_mrp', value: '8500', label: 'ОУР ИПН порог (МРП/год)' },
  { key: 'ipn_deduction_mrp',  value: '30',      label: 'Базовый вычет ИПН (МРП/мес)' },

  // ── ТОО ──
  { key: 'kpn_rate',            value: '0.20',   label: 'КПН ставка' },
  { key: 'social_tax_too_rate', value: '0.06',   label: 'СН ТОО (6% от ФОТ, новый НК)' },
  { key: 'dividend_tax_rate',   value: '0.05',   label: 'ИПН дивиденды' },

  // ── Метаданные ──
  { key: 'config_version',      value: '2026.03', label: 'Версия конфига' },
];

// ── GET /api/config/tax — public ──────────────────────────────────────────────
router.get('/', async (_req, res) => {
  try {
    const { rows } = await db.query(
      'SELECT key, value, label, updated_at FROM tax_config ORDER BY id',
    );
    // Return as key→value map for easy consumption
    const config = {};
    for (const r of rows) config[r.key] = { value: r.value, label: r.label, updatedAt: r.updated_at };
    res.json(config);
  } catch (err) {
    console.error('GET /config/tax error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── PUT /api/config/tax/:key — admin only ─────────────────────────────────────
router.put('/:key', adminAuth, async (req, res) => {
  try {
    const { value } = req.body ?? {};
    if (value === undefined) return res.status(400).json({ error: 'value required' });

    const { rowCount } = await db.query(
      `UPDATE tax_config SET value = $1, updated_at = NOW() WHERE key = $2`,
      [String(value), req.params.key],
    );
    if (rowCount === 0) return res.status(404).json({ error: 'Unknown key' });
    res.json({ ok: true });
  } catch (err) {
    console.error('PUT /config/tax/:key error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── PUT /api/config/tax — bulk update (admin) ─────────────────────────────────
router.put('/', adminAuth, async (req, res) => {
  try {
    const updates = req.body; // { key: value, ... }
    if (!updates || typeof updates !== 'object') return res.status(400).json({ error: 'object required' });

    for (const [key, value] of Object.entries(updates)) {
      await db.query(
        `UPDATE tax_config SET value = $1, updated_at = NOW() WHERE key = $2`,
        [String(value), key],
      );
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('PUT /config/tax (bulk) error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// ── Seed helper — called from migrate() ──────────────────────────────────────
// UPSERT: inserts new keys, updates existing keys to latest values
async function seedTaxConfig() {
  for (const row of SEED) {
    await db.query(
      `INSERT INTO tax_config (key, value, label)
       VALUES ($1, $2, $3)
       ON CONFLICT (key) DO UPDATE SET value = $2, label = $3, updated_at = NOW()`,
      [row.key, row.value, row.label],
    );
  }
}

module.exports = { router, seedTaxConfig };
