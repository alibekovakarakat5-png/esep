// Тесты services/tax/form910.js — порт form910_service.dart.
// Эталоны: __fixtures__/form910_cases.json + form910_h1.expected.xml.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { assertClose } = require('./_helpers');

const fixtures = require('../src/services/tax/__fixtures__/form910_cases.json');
const { rates: RATES } = require('../src/services/tax/__fixtures__/rates_2026.json');
const { calculateForm910, generateForm910Xml, generateForm910Json } = require('../src/services/tax');

const FIXED_NOW = new Date('2026-08-06T12:00:00');

for (const c of fixtures.cases) {
  test(`form910: ${c.id}`, () => {
    assertClose(calculateForm910(RATES, c.input), c.expected, c.id);
  });
}

test('form910: XML совпадает с эталоном (СОНО-конверт, поля v27 r133)', () => {
  const xc = fixtures.xmlCase;
  const c = fixtures.cases.find((x) => x.id === xc.caseId);
  const data = calculateForm910(RATES, c.input);
  const expected = fs
    .readFileSync(
      path.join(__dirname, '../src/services/tax/__fixtures__', xc.expectedXmlFile),
      'utf8',
    )
    .replace(/\r\n/g, '\n')
    .replace('{{GEN_DATE}}', xc.genDate)
    .trimEnd();
  const actual = generateForm910Xml(data, { now: new Date(xc.now) });
  assert.strictEqual(actual, expected);
});

test('form910: JSON (КНП ИСНА) — конверт и значения полей', () => {
  const c = fixtures.cases.find((x) => x.id === 'h1-main');
  const data = calculateForm910(RATES, c.input);
  const payload = JSON.parse(generateForm910Json(data, { now: FIXED_NOW }));
  assert.strictEqual(payload.formCode, '910.00');
  assert.strictEqual(payload.version, 27);
  assert.strictEqual(payload.revision, 133);
  assertClose(payload.period, { year: 2026, halfYear: 1 }, 'period');
  assert.strictEqual(payload.taxpayer.iin, c.input.iin);
  assert.strictEqual(payload.taxpayer.name, c.input.fullName);
  assert.strictEqual(payload.declarationType, 'dt_main');
  assert.strictEqual(payload.currencyCode, 'KZT');
  assertClose(payload.fields, c.expectedFields, 'fields');
  assert.strictEqual(payload._meta.generatedBy, 'Esep');
  assert.ok(String(payload._meta.generatedAt).startsWith('2026-08-06'), payload._meta.generatedAt);
});

for (const dt of fixtures.declarationTypes) {
  test(`form910: тип декларации «${dt.type}» → <${dt.field}>`, () => {
    const c = fixtures.cases.find((x) => x.id === 'h1-main');
    const data = calculateForm910(RATES, { ...c.input, declarationType: dt.type });
    const xml = generateForm910Xml(data, { now: FIXED_NOW });
    assert.ok(xml.includes(`<${dt.field}>1</${dt.field}>`), `нет <${dt.field}> в XML`);
    const payload = JSON.parse(generateForm910Json(data, { now: FIXED_NOW }));
    assert.strictEqual(payload.declarationType, dt.field);
  });
}

test('form910: XML-экранирование спецсимволов в имени', () => {
  const esc = fixtures.xmlEscaping;
  const c = fixtures.cases.find((x) => x.id === 'h1-main');
  const data = calculateForm910(RATES, { ...c.input, fullName: esc.fullName });
  const xml = generateForm910Xml(data, { now: FIXED_NOW });
  assert.ok(xml.includes(esc.expectedInXml), `ожидали строку ${esc.expectedInXml}`);
});
