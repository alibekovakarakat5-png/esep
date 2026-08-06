// Тесты чистых функций расчёта services/tax/calc.js по эталонным фикстурам.
// Фикстуры сняты с Dart-исходника (kz_tax_constants.dart) — см. спеку
// docs/superpowers/specs/2026-08-06-tax-core-node-design.md, волна 1.
const test = require('node:test');
const { assertClose } = require('./_helpers');

const fixtures = require('../src/services/tax/__fixtures__/calc_cases.json');
const { rates: DEFAULT_2026 } = require('../src/services/tax/__fixtures__/rates_2026.json');
const tax = require('../src/services/tax');

// Диспетчер: имя функции из фикстуры → вызов с аргументами кейса.
const CALL = {
  calculate910:            (c, r) => tax.calculate910(r, c.income, c.options ?? {}),
  calculateMonthlySocial:  (c, r) => tax.calculateMonthlySocial(r, c.options ?? {}),
  calculateFull910:        (c, r) => tax.calculateFull910(r, c.income, c.options ?? {}),
  calculateProgressiveIpn: (c, r) => tax.calculateProgressiveIpn(r, c.income),
  calculateSelfEmployed:   (c, r) => tax.calculateSelfEmployed(r, c.income),
  calculateTooTax:         (c, r) => tax.calculateTooTax(r, c.input),
  selfEmployedLimit:       (c, r) => tax.selfEmployedLimit(r),
  vatThreshold:            (c, r) => tax.vatThreshold(r),
  simplified910YearLimit:  (c, r) => tax.simplified910YearLimit(r),
  simplified910HalfYearLimit: (c, r) => tax.simplified910HalfYearLimit(r),
  ipMonthlySocialTax:      (c, r) => tax.ipMonthlySocialTax(r, c.options ?? {}),
};

for (const c of fixtures.cases) {
  test(`calc: ${c.id}`, () => {
    const rates = { ...DEFAULT_2026, ...(c.ratesOverride ?? {}) };
    const call = CALL[c.fn];
    if (!call) throw new Error(`Нет диспетчера для fn=${c.fn} (кейс ${c.id})`);
    assertClose(call(c, rates), c.expected, c.id);
  });
}
