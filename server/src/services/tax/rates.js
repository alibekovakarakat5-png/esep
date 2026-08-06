// Ставки НК РК 2026 (Закон 214-VIII) — дефолты Tax Core на Node.
// Значения зеркалят SEED из routes/tax-config.js и fallback'и
// lib/core/constants/kz_tax_constants.dart. Канон для тестов —
// __fixtures__/rates_2026.json.
//
// Правило модуля: никаких require Express/БД — db передаётся параметром,
// чтобы файл оставался чистым и пригодным для esbuild-бандла лендинга.

const DEFAULT_VERSION = '2026.03';

const DEFAULT_RATES = Object.freeze({
  // Базовые показатели
  mrp: 4325,
  mzp: 85000,
  // Упрощёнка (910)
  ipn_rate_910: 0.04,
  sn_rate_910: 0,
  '910_year_mrp': 600000,
  '910_max_employees': 999999,
  // Соцплатежи за себя
  opv_rate: 0.1,
  opvr_rate: 0.035,
  so_rate: 0.05,
  vosms_rate_self: 0.05,
  vosms_base_mult: 1.4,
  // Соцплатежи за сотрудников
  emp_opvr_rate: 0.035,
  emp_so_rate: 0.05,
  emp_vosms_rate: 0.03,
  emp_vosms_max_mult: 40,
  ee_opv_rate: 0.1,
  ee_vosms_rate: 0.02,
  ee_vosms_max_mult: 20,
  ee_social_tax_rate: 0.06,
  // Самозанятые
  self_emp_rate: 0.04,
  self_emp_month_limit: 300,
  self_emp_year_limit: 3600,
  // НДС
  vat_rate: 0.16,
  vat_threshold_mrp: 10000,
  // ОУР — прогрессивная шкала ИПН
  general_ipn_rate: 0.1,
  general_ipn_rate_high: 0.15,
  general_ipn_threshold_mrp: 8500,
  ipn_deduction_mrp: 30,
  // ТОО
  kpn_rate: 0.2,
  social_tax_too_rate: 0.06,
  dividend_tax_rate: 0.05,
  // СН для ИП на ОУР (фикс в МРП)
  ip_sn_mrp_self: 2,
  ip_sn_mrp_per_employee: 1,
});

function parseNumber(value) {
  if (value == null) return null;
  const s = String(value).trim();
  if (s === '') return null;
  const num = Number(s);
  return Number.isFinite(num) ? num : null;
}

// raw — плоская карта key→value (строки из tax_config или числа).
// Неизвестные ключи игнорируются, непарсящиеся значения падают в дефолт —
// та же семантика, что _cfg()/getDouble() в Dart.
function resolveRates(raw = {}) {
  const rates = { ...DEFAULT_RATES };
  for (const key of Object.keys(DEFAULT_RATES)) {
    const num = parseNumber(raw[key]);
    if (num !== null) rates[key] = num;
  }
  const rawVersion = raw.config_version != null ? String(raw.config_version).trim() : '';
  return { rates, version: rawVersion !== '' ? rawVersion : DEFAULT_VERSION };
}

// Читает tax_config через переданный db ({ query }) и накладывает на дефолты.
// При недоступной БД возвращает дефолты — считаем по последним известным
// ставкам, как это делает Flutter-клиент при недоступном сервере.
async function loadRates(db) {
  try {
    const { rows } = await db.query('SELECT key, value FROM tax_config');
    const raw = {};
    for (const r of rows) raw[r.key] = r.value;
    return resolveRates(raw);
  } catch (err) {
    console.error('[tax/rates] tax_config недоступен, считаем по дефолтам:', err.message);
    return resolveRates();
  }
}

module.exports = { DEFAULT_RATES, DEFAULT_VERSION, resolveRates, loadRates };
