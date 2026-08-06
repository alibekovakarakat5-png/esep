// Тесты билдеров ответов POST /api/tax/calculate и /api/tax/form910
// (routes/tax.js). Числа — из тех же фикстур, что и tax_calc.test.js.
// HTTP-слой (rate-limit, коды ответов) проверяет e2e: scripts/test_tax_api_e2e.js.
const test = require('node:test');
const assert = require('node:assert');
const { assertClose } = require('./_helpers');

const { rates: RATES } = require('../src/services/tax/__fixtures__/rates_2026.json');
const { buildCalculateResponse, buildForm910Response, ApiError } = require('../src/routes/tax');

const VERSION = '2026.03';
const call = (body) => buildCalculateResponse(RATES, VERSION, body);
const expectApiError = (fn, status) => {
  try {
    fn();
    assert.fail('ожидали ApiError');
  } catch (e) {
    assert.ok(e instanceof ApiError, `ожидали ApiError, получили ${e.constructor.name}: ${e.message}`);
    assert.strictEqual(e.status, status, e.message);
  }
};

// ── 910 ──────────────────────────────────────────────────────────────────────

test('api: 910 базовый — цифры спеки (§5)', () => {
  const r = call({ regime: '910', halfYearIncome: 4690000 });
  assert.strictEqual(r.regime, '910');
  assert.strictEqual(r.ratesVersion, VERSION);
  assertClose(r.tax, { ipn: 187600, sn: 0, total: 187600, effectiveRate: 0.04 }, 'tax');
  assertClose(
    r.social,
    { opv: 8500, opvr: 2975, so: 4250, vosms: 5950, monthlyTotal: 21675, halfYearTotal: 130050 },
    'social',
  );
  assertClose(r.grandTotal, 317650, 'grandTotal');
  assert.strictEqual(r.limit.exceeded, false);
  assertClose(r.limit.halfYearTenge, 1297500000, 'limit');
});

test('api: 910 скидка маслихата 2% → ставка 2%', () => {
  const r = call({ regime: '910', halfYearIncome: 4690000, options: { regionalDiscount: 0.02 } });
  assertClose(r.tax.total, 93800, 'tax.total');
  assertClose(r.tax.effectiveRate, 0.02, 'tax.effectiveRate');
});

test('api: 910 родился до 1975 → соцплатежи без ОПВР', () => {
  const r = call({ regime: '910', halfYearIncome: 4690000, options: { bornBefore1975: true } });
  assertClose(r.social.opvr, 0, 'social.opvr');
  assertClose(r.social.halfYearTotal, 112200, 'social.halfYearTotal');
  assertClose(r.grandTotal, 299800, 'grandTotal');
});

test('api: 910 нулевой доход — ок, налог 0, соцплатежи остаются', () => {
  const r = call({ regime: '910', halfYearIncome: 0 });
  assertClose(r.tax.total, 0, 'tax.total');
  assertClose(r.grandTotal, 130050, 'grandTotal');
});

test('api: 910 превышение лимита — exceeded=true', () => {
  const r = call({ regime: '910', halfYearIncome: 1400000000 });
  assert.strictEqual(r.limit.exceeded, true);
});

// ── Самозанятый ──────────────────────────────────────────────────────────────

test('api: self_employed 1 млн — налог 40 000, итог 300 100', () => {
  const r = call({ regime: 'self_employed', annualIncome: 1000000 });
  assertClose(r.tax.total, 40000, 'tax.total');
  assertClose(r.social.yearTotal, 260100, 'social.yearTotal');
  assertClose(r.grandTotal, 300100, 'grandTotal');
  assertClose(r.limit.yearlyTenge, 15570000, 'limit.yearlyTenge');
  assert.strictEqual(r.limit.exceeded, false);
});

test('api: self_employed выше лимита — exceeded=true', () => {
  const r = call({ regime: 'self_employed', annualIncome: 20000000 });
  assert.strictEqual(r.limit.exceeded, true);
});

// ── ОУР ──────────────────────────────────────────────────────────────────────

test('api: general 50 млн — прогрессивный ИПН', () => {
  const r = call({ regime: 'general', annualIncome: 50000000 });
  assertClose(r.tax.ipn, 5661875, 'tax.ipn');
  assertClose(r.tax.threshold, 36762500, 'tax.threshold');
  assertClose(r.grandTotal, 5921975, 'grandTotal');
  assertClose(r.vat.thresholdTenge, 43250000, 'vat');
});

// ── ТОО ──────────────────────────────────────────────────────────────────────

test('api: too — полный расчёт как в Dart-классе', () => {
  const r = call({
    regime: 'too',
    income: 50000000,
    expenses: 30000000,
    isVatPayer: true,
    employeeCount: 3,
    monthlyPayroll: 300000,
  });
  assertClose(r.calculation.kpn, 4000000, 'kpn');
  assertClose(r.calculation.vatPayable, 3200000, 'vatPayable');
  assertClose(r.calculation.socialTax, 54000, 'socialTax');
  assertClose(r.calculation.dividendTax, 800000, 'dividendTax');
  assertClose(r.calculation.totalTax, 7200000, 'totalTax');
  assertClose(r.grandTotal, 7200000, 'grandTotal');
  assert.strictEqual(r.ratesVersion, VERSION);
});

test('api: too — kpnRateOverride 0 (малый бизнес) уважается', () => {
  const r = call({ regime: 'too', income: 50000000, expenses: 30000000, kpnRateOverride: 0 });
  assertClose(r.calculation.kpn, 0, 'kpn');
});

// ── Валидация ────────────────────────────────────────────────────────────────

test('api: без regime → 400', () => expectApiError(() => call({}), 400));
test('api: неизвестный regime → 400', () =>
  expectApiError(() => call({ regime: 'patent' }), 400));
test('api: 910 без halfYearIncome → 400', () =>
  expectApiError(() => call({ regime: '910' }), 400));
test('api: 910 отрицательный доход → 400', () =>
  expectApiError(() => call({ regime: '910', halfYearIncome: -5 }), 400));
test('api: 910 нечисловой доход → 400', () =>
  expectApiError(() => call({ regime: '910', halfYearIncome: 'abc' }), 400));
test('api: too без expenses → 400', () =>
  expectApiError(() => call({ regime: 'too', income: 1000000 }), 400));

// ── Форма 910 ────────────────────────────────────────────────────────────────

const FORM_INPUT = {
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

test('api: form910 xml — конверт СОНО с полями', () => {
  const r = buildForm910Response(RATES, VERSION, FORM_INPUT);
  assert.strictEqual(r.format, 'xml');
  assert.strictEqual(r.filename, 'form_910_2026_H1.xml');
  assert.strictEqual(r.ratesVersion, VERSION);
  assert.ok(r.document.includes('<dt_main>1</dt_main>'), 'нет dt_main');
  assert.ok(r.document.includes('<field_910_00_001>3500000.00</field_910_00_001>'), 'нет поля 001');
  assertClose(r.data.income, 3500000, 'data.income');
  assertClose(r.data.grandTotal, 270050, 'data.grandTotal');
});

test('api: form910 json — конверт ИСНА', () => {
  const r = buildForm910Response(RATES, VERSION, { ...FORM_INPUT, format: 'json' });
  assert.strictEqual(r.filename, 'form_910_2026_H2.json'.replace('H2', 'H1'));
  const doc = JSON.parse(r.document);
  assert.strictEqual(doc.formCode, '910.00');
  assertClose(doc.fields.field_910_00_001, 3500000, 'fields.001');
});

test('api: form910 невалидный format → 400', () =>
  expectApiError(() => buildForm910Response(RATES, VERSION, { ...FORM_INPUT, format: 'pdf' }), 400));
test('api: form910 halfYear=3 → 400', () =>
  expectApiError(() => buildForm910Response(RATES, VERSION, { ...FORM_INPUT, halfYear: 3 }), 400));
test('api: form910 без iin → 400', () =>
  expectApiError(() => buildForm910Response(RATES, VERSION, { ...FORM_INPUT, iin: '' }), 400));
test('api: form910 мусорная дата транзакции → 400', () =>
  expectApiError(
    () => buildForm910Response(RATES, VERSION, {
      ...FORM_INPUT,
      transactions: [{ date: 'вчера', amount: 1, isIncome: true }],
    }),
    400,
  ));
