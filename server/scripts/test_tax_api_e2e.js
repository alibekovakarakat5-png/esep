/**
 * End-to-End тест публичного налогового API (волна 4 спеки tax-core).
 *
 * Запуск:
 *   node server/scripts/test_tax_api_e2e.js
 *
 * Опции через env:
 *   API_BASE     — базовый URL (по умолчанию http://localhost:3001/api/tax)
 *   DATABASE_URL — для проверки «ratesVersion следует за tax_config» (секция 7);
 *                  без него секция пропускается.
 *
 * Что тестирует:
 *   1) POST /calculate 910 — цифры из §5 спеки (187 600 / 317 650)
 *   2) 910: скидка маслихата, родившиеся до 1975
 *   3) self_employed / general / too
 *   4) Валидация → 400
 *   5) POST /form910 — XML СОНО и JSON ИСНА
 *   6) GET → 404 (только POST)
 *   7) ratesVersion/лимиты следуют за tax_config (правка БД на лету)
 */

try { require('dotenv').config({ path: __dirname + '/../.env' }); } catch {}
const http = require('http');
const https = require('https');
const { URL } = require('url');

const API_BASE = process.env.API_BASE || 'http://localhost:3001/api/tax';

function request(method, path, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path.startsWith('http') ? path : API_BASE + path);
    const isHttps = url.protocol === 'https:';
    const lib = isHttps ? https : http;
    const req = lib.request(
      {
        method,
        hostname: url.hostname,
        port: url.port || (isHttps ? 443 : 80),
        path: url.pathname + url.search,
        headers: { 'Content-Type': 'application/json', ...headers },
      },
      (res) => {
        let buf = '';
        res.on('data', (c) => (buf += c));
        res.on('end', () => {
          let parsed;
          try { parsed = JSON.parse(buf); } catch { parsed = buf; }
          resolve({ status: res.statusCode, body: parsed });
        });
      },
    );
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

const c = {
  green:  (s) => `\x1b[32m${s}\x1b[0m`,
  red:    (s) => `\x1b[31m${s}\x1b[0m`,
  yellow: (s) => `\x1b[33m${s}\x1b[0m`,
  cyan:   (s) => `\x1b[36m${s}\x1b[0m`,
  bold:   (s) => `\x1b[1m${s}\x1b[0m`,
};

let passed = 0;
let failed = 0;
function check(name, ok, details = '') {
  if (ok) { console.log(c.green('  ✅  ') + name); passed++; }
  else { console.log(c.red('  ❌  ') + name); if (details) console.log('      ' + c.red(details)); failed++; }
}
function section(title) { console.log('\n' + c.bold(c.cyan('━━ ' + title + ' ━━'))); }
const close = (a, b, eps = 0.01) => typeof a === 'number' && Math.abs(a - b) <= eps;

async function main() {
  console.log(c.bold('\n╔══════════════════════════════════════════════════════════════════╗'));
  console.log(c.bold('║  E2E ТЕСТ /api/tax — публичный калькулятор + форма 910          ║'));
  console.log(c.bold('╚══════════════════════════════════════════════════════════════════╝'));
  console.log(`\nAPI_BASE: ${API_BASE}`);

  // ── 1. 910 базовый ────────────────────────────────────────────────────────
  section('1. POST /calculate — 910, цифры §5 спеки');
  const r1 = await request('POST', '/calculate', { regime: '910', halfYearIncome: 4690000 })
    .catch((e) => ({ error: e.message }));
  check('Сервер отвечает (200)', r1.status === 200, r1.error || `status ${r1.status}`);
  check('ИПН = 187 600', close(r1.body?.tax?.ipn, 187600), `ipn=${r1.body?.tax?.ipn}`);
  check('tax.total = 187 600', close(r1.body?.tax?.total, 187600));
  check('Соцплатежи/мес = 21 675', close(r1.body?.social?.monthlyTotal, 21675));
  check('Соцплатежи за полугодие = 130 050', close(r1.body?.social?.halfYearTotal, 130050));
  check('grandTotal = 317 650', close(r1.body?.grandTotal, 317650), `grandTotal=${r1.body?.grandTotal}`);
  check('ratesVersion присутствует', typeof r1.body?.ratesVersion === 'string' && r1.body.ratesVersion.length > 0);
  check('Лимит полугодия = 1 297 500 000', close(r1.body?.limit?.halfYearTenge, 1297500000));

  // ── 2. 910 варианты ───────────────────────────────────────────────────────
  section('2. 910 — скидка маслихата и «до 1975»');
  const r2a = await request('POST', '/calculate', {
    regime: '910', halfYearIncome: 4690000, options: { regionalDiscount: 0.02 },
  });
  check('Скидка 2% → налог 93 800 (ставка 2%)', close(r2a.body?.tax?.total, 93800),
    `total=${r2a.body?.tax?.total}`);
  const r2b = await request('POST', '/calculate', {
    regime: '910', halfYearIncome: 4690000, options: { bornBefore1975: true },
  });
  check('Без ОПВР: соц/полугодие = 112 200', close(r2b.body?.social?.halfYearTotal, 112200));
  check('grandTotal = 299 800', close(r2b.body?.grandTotal, 299800));

  // ── 3. Остальные режимы ───────────────────────────────────────────────────
  section('3. self_employed / general / too');
  const r3a = await request('POST', '/calculate', { regime: 'self_employed', annualIncome: 1000000 });
  check('Самозанятый: налог 40 000', close(r3a.body?.tax?.total, 40000));
  check('Самозанятый: итог 300 100', close(r3a.body?.grandTotal, 300100));
  check('Самозанятый: лимит-год 15 570 000', close(r3a.body?.limit?.yearlyTenge, 15570000));

  const r3b = await request('POST', '/calculate', { regime: 'general', annualIncome: 50000000 });
  check('ОУР: прогрессивный ИПН 5 661 875', close(r3b.body?.tax?.ipn, 5661875),
    `ipn=${r3b.body?.tax?.ipn}`);
  check('ОУР: итог 5 921 975', close(r3b.body?.grandTotal, 5921975));
  check('ОУР: порог НДС 43 250 000', close(r3b.body?.vat?.thresholdTenge, 43250000));

  const r3c = await request('POST', '/calculate', {
    regime: 'too', income: 50000000, expenses: 30000000,
    isVatPayer: true, employeeCount: 3, monthlyPayroll: 300000,
  });
  check('ТОО: КПН 4 000 000', close(r3c.body?.calculation?.kpn, 4000000));
  check('ТОО: НДС к уплате 3 200 000', close(r3c.body?.calculation?.vatPayable, 3200000));
  check('ТОО: totalTax 7 200 000', close(r3c.body?.calculation?.totalTax, 7200000));
  check('ТОО: dividendTax справочно 800 000 (не в totalTax)',
    close(r3c.body?.calculation?.dividendTax, 800000));

  // ── 4. Валидация ──────────────────────────────────────────────────────────
  section('4. Валидация входа');
  const r4a = await request('POST', '/calculate', {});
  check('Пустое тело → 400', r4a.status === 400, `status ${r4a.status}`);
  const r4b = await request('POST', '/calculate', { regime: 'patent', annualIncome: 1 });
  check('Отменённый режим (patent) → 400', r4b.status === 400);
  const r4c = await request('POST', '/calculate', { regime: '910', halfYearIncome: 'abc' });
  check('Нечисловой доход → 400', r4c.status === 400);
  const r4d = await request('POST', '/calculate', { regime: '910', halfYearIncome: -1 });
  check('Отрицательный доход → 400', r4d.status === 400);

  // ── 5. Форма 910 ──────────────────────────────────────────────────────────
  section('5. POST /form910 — XML СОНО и JSON ИСНА');
  const formBody = {
    format: 'xml',
    iin: '850101300123',
    fullName: 'ИП Тестова А.Б.',
    halfYear: 1,
    year: 2026,
    transactions: [
      { date: '2026-03-15', amount: 2000000, isIncome: true, source: 'kaspi' },
      { date: '2026-05-10', amount: 1500000, isIncome: true, source: 'нал' },
    ],
  };
  const r5a = await request('POST', '/form910', formBody);
  check('XML: 200', r5a.status === 200, `status ${r5a.status}`);
  check('XML: filename form_910_2026_H1.xml', r5a.body?.filename === 'form_910_2026_H1.xml');
  check('XML: содержит <dt_main>1</dt_main>', String(r5a.body?.document).includes('<dt_main>1</dt_main>'));
  check('XML: доход 3 500 000.00 в поле 001',
    String(r5a.body?.document).includes('<field_910_00_001>3500000.00</field_910_00_001>'));
  check('XML: data.grandTotal = 270 050', close(r5a.body?.data?.grandTotal, 270050));

  const r5b = await request('POST', '/form910', { ...formBody, format: 'json' });
  let isnaDoc = null;
  try { isnaDoc = JSON.parse(r5b.body?.document); } catch {}
  check('JSON: 200 и документ парсится', r5b.status === 200 && !!isnaDoc);
  check('JSON: formCode 910.00', isnaDoc?.formCode === '910.00');
  check('JSON: поле 001 = 3 500 000', close(isnaDoc?.fields?.field_910_00_001, 3500000));

  const r5c = await request('POST', '/form910', { ...formBody, format: 'pdf' });
  check('format=pdf → 400', r5c.status === 400);

  // ── 6. Только POST ────────────────────────────────────────────────────────
  section('6. GET /calculate → 404');
  const r6 = await request('GET', '/calculate');
  check('GET не поддерживается (404)', r6.status === 404, `status ${r6.status}`);

  // ── 7. Ставки живут в БД ──────────────────────────────────────────────────
  section('7. ratesVersion/лимиты следуют за tax_config');
  if (!process.env.DATABASE_URL) {
    console.log(c.yellow('  ⚠  DATABASE_URL не задан — секция пропущена'));
  } else {
    const db = require('../src/db');
    const before = await request('POST', '/calculate', { regime: 'self_employed', annualIncome: 1 });
    try {
      await db.query(`UPDATE tax_config SET value = '2099.99' WHERE key = 'config_version'`);
      await db.query(`UPDATE tax_config SET value = '5000' WHERE key = 'mrp'`);
      const after = await request('POST', '/calculate', { regime: 'self_employed', annualIncome: 1 });
      check('ratesVersion отражает config_version из БД',
        after.body?.ratesVersion === '2099.99', `ratesVersion=${after.body?.ratesVersion}`);
      check('Лимит пересчитался от нового МРП (5000×3600 = 18 000 000)',
        close(after.body?.limit?.yearlyTenge, 18000000), `yearlyTenge=${after.body?.limit?.yearlyTenge}`);
    } finally {
      await db.query(`UPDATE tax_config SET value = '2026.03' WHERE key = 'config_version'`);
      await db.query(`UPDATE tax_config SET value = '4325' WHERE key = 'mrp'`);
    }
    const restored = await request('POST', '/calculate', { regime: 'self_employed', annualIncome: 1 });
    check('После отката всё как было',
      restored.body?.ratesVersion === before.body?.ratesVersion &&
      close(restored.body?.limit?.yearlyTenge, before.body?.limit?.yearlyTenge));
  }

  // ── Итог ──────────────────────────────────────────────────────────────────
  console.log('\n' + c.bold('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'));
  console.log(c.bold(`  ИТОГ:  ${c.green(passed + ' прошли')}, ${failed > 0 ? c.red(failed + ' упали') : c.green('0 упали')}`));
  console.log(c.bold('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'));
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(c.red('\n❌ Тест упал с ошибкой:'), err);
  process.exit(1);
});
