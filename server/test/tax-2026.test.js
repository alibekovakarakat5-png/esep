/**
 * Регрессионный guard цифр НК-2026 (Закон 214-VIII).
 * Проверяет, что (1) серверный tax-config (рантайм-источник правды) и
 * (2) fallback-константы Flutter-приложения совпадают с выверенными
 * значениями закона. Ловит расхождения «код ↔ доки» (как баг лимита 910
 * 48 076 vs 600 000, найденный 2026-06).
 *
 * Запуск: node server/test/tax-2026.test.js   (Dart-тест не гоняется из-за Device Guard,
 * поэтому стережём здесь, на node.) Источники значений: КГД / НК-2026, bcc.kz, mybuh.kz.
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const CONFIG = path.join(ROOT, 'server', 'src', 'routes', 'tax-config.js');
const DART = path.join(ROOT, 'lib', 'core', 'constants', 'kz_tax_constants.dart');

// Эталон НК-2026 (выверено по закону/КГД).
const EXPECT = {
  mrp: '4325',
  mzp: '85000',
  ipn_rate_910: '0.04',          // упрощёнка: 4% (100% ИПН)
  sn_rate_910: '0',              // СН для СНР отменён
  '910_year_mrp': '600000',      // лимит 600 000 МРП/год (~2,6 млрд ₸)
  '910_max_employees': '999999', // лимит сотрудников снят
  vat_rate: '0.16',             // НДС 16%
  vat_threshold_mrp: '10000',
  self_emp_rate: '0.04',
  self_emp_month_limit: '300',
  general_ipn_threshold_mrp: '8500',
};

let fails = 0;
const ok = (c, m) => { if (c) { console.log('  ✓', m); } else { console.error('  ✗', m); fails++; } };

// 1) Серверный tax-config
const cfgText = fs.readFileSync(CONFIG, 'utf8');
const seed = {};
for (const m of cfgText.matchAll(/key:\s*'([^']+)'\s*,\s*value:\s*'([^']*)'/g)) seed[m[1]] = m[2];
console.log('1) server/tax-config.js (рантайм-источник):');
for (const [k, v] of Object.entries(EXPECT)) ok(seed[k] === v, `${k} = ${v} (факт: ${seed[k]})`);

// 2) Fallback-константы Flutter совпадают с законом (и значит с сервером)
const dart = fs.readFileSync(DART, 'utf8');
const dcfg = (key) => { const m = dart.match(new RegExp(`_cfg\\('${key}',\\s*([\\d.]+)\\)`)); return m && m[1]; };
const dint = (key) => { const m = dart.match(new RegExp(`getInt\\('${key}',\\s*([\\d.]+)\\)`)); return m && m[1]; };
console.log('2) lib/.../kz_tax_constants.dart (fallback приложения):');
ok(dcfg('910_year_mrp') === '600000', `910_year_mrp fallback = 600000 (факт: ${dcfg('910_year_mrp')})`);
ok(dcfg('ipn_rate_910') === '0.04', `ipn_rate_910 fallback = 0.04 (факт: ${dcfg('ipn_rate_910')})`);
ok(dint('910_max_employees') === '999999', `910_max_employees fallback = 999999 (факт: ${dint('910_max_employees')})`);

// 3) Нет старого лимита нигде в Dart-исходнике
ok(!/48076|24038/.test(dart), 'в kz_tax_constants нет старого лимита 48076/24038');

// 4) Ставки КПН по видам деятельности (НК-2026, ст. 357) — форма 100.
//    Источник: docs/forms/form-100-00-2026-spec.md. Стережём, чтобы не зашили «20% всем».
console.log('4) КПН kpnActivityRates (ст. 357):');
ok(/kpnActivityRates/.test(dart), 'список kpnActivityRates присутствует');
for (const [label, re] of [
  ['обычная 20%',      /Обычная деятельность', rate: 0\.20/],
  ['сельхоз 3%',       /rate: 0\.03/],
  ['кооператив 6%',    /rate: 0\.06/],
  ['соцсфера 5%',      /rate: 0\.05/],
  ['банк/игорный 25%', /rate: 0\.25/],
]) ok(re.test(dart), `КПН: ${label}`);

console.log(fails === 0 ? '\nPASS — все цифры НК-2026 согласованы' : `\nFAIL — расхождений: ${fails}`);
process.exit(fails === 0 ? 0 : 1);
