// Тесты services/tax/rates.js: дефолты, парсинг значений из tax_config,
// загрузка через переданный db (DI, без реальной БД).
const test = require('node:test');
const assert = require('node:assert');
const { assertClose } = require('./_helpers');

const canon = require('../src/services/tax/__fixtures__/rates_2026.json');
const { DEFAULT_RATES, DEFAULT_VERSION, resolveRates, loadRates } = require('../src/services/tax');

test('rates: DEFAULT_RATES совпадают с каноном rates_2026.json', () => {
  assertClose(DEFAULT_RATES, canon.rates, 'DEFAULT_RATES');
});

test('rates: DEFAULT_VERSION совпадает с каноном', () => {
  assert.strictEqual(DEFAULT_VERSION, canon.version);
});

test('resolveRates: строки из БД парсятся в числа, версия отдельно', () => {
  const { rates, version } = resolveRates({
    mrp: '5000',
    vat_rate: '0.2',
    config_version: '2027.01',
  });
  assert.strictEqual(rates.mrp, 5000);
  assert.strictEqual(rates.vat_rate, 0.2);
  assert.strictEqual(version, '2027.01');
  assert.strictEqual(rates.mzp, 85000); // не переданное — из дефолтов
});

test('resolveRates: мусор в значении → дефолт (как _cfg в Dart)', () => {
  const { rates } = resolveRates({ mrp: 'abc', so_rate: '' });
  assert.strictEqual(rates.mrp, 4325);
  assert.strictEqual(rates.so_rate, 0.05);
});

test('resolveRates: неизвестные ключи не попадают в rates', () => {
  const { rates } = resolveRates({ unknown_key: '123' });
  assert.strictEqual(rates.unknown_key, undefined);
});

test('resolveRates: без аргумента — чистые дефолты', () => {
  const { rates, version } = resolveRates();
  assertClose(rates, canon.rates, 'defaults');
  assert.strictEqual(version, canon.version);
});

test('loadRates: читает tax_config через переданный db', async () => {
  const fakeDb = {
    query: async () => ({
      rows: [
        { key: 'mrp', value: '9999' },
        { key: 'config_version', value: '2099.12' },
      ],
    }),
  };
  const { rates, version } = await loadRates(fakeDb);
  assert.strictEqual(rates.mrp, 9999);
  assert.strictEqual(version, '2099.12');
  assert.strictEqual(rates.opv_rate, 0.1); // остальное — дефолты
});

test('loadRates: при ошибке БД возвращает дефолты (fallback-философия Dart)', async () => {
  const fakeDb = {
    query: async () => {
      throw new Error('нет соединения');
    },
  };
  const { rates, version } = await loadRates(fakeDb);
  assertClose(rates, canon.rates, 'fallback');
  assert.strictEqual(version, canon.version);
});
