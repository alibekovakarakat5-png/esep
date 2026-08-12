// Контракт transactions Flutter ↔ сервер.
//
// Dart-модель (lib/core/models/transaction.dart) всегда говорила snake_case:
// fromJson читает is_income/client_name, toJson шлёт их же. Рассинхрон
// (обнаружен 2026-08-12): GET отдавал camelCase — парсинг падал и дашборд
// пустел после перезагрузки; POST требовал isIncome — приложение получало
// 400 на ручном добавлении и импорте выписки; PUT тихо занулял
// is_income/client_name. Плюс date сериализовалась через toISOString():
// локальная полночь в TZ восточнее UTC уезжала на день назад.
const test = require('node:test');
const assert = require('node:assert');

const {
  serializeTransaction,
  normalizeTransaction,
} = require('../src/routes/transactions');

test('GET-сериализация: snake_case, как ждёт Dart-модель', () => {
  const row = {
    id: 't1',
    title: 'Оплата',
    amount: '370000.00', // pg NUMERIC приходит строкой
    is_income: true,
    date: new Date(2026, 7, 10), // локальная полночь 10 авг
    client_name: 'ТОО Пример',
    source: 'Kaspi',
    note: null,
    category: 'Продажи',
  };
  assert.deepStrictEqual(serializeTransaction(row), {
    id: 't1',
    title: 'Оплата',
    amount: 370000,
    is_income: true,
    date: '2026-08-10', // не '2026-08-09': без UTC-сдвига
    client_name: 'ТОО Пример',
    source: 'Kaspi',
    note: null,
    category: 'Продажи',
  });
});

test('normalize: snake_case от приложения (Transaction.toJson)', () => {
  const t = normalizeTransaction({
    id: 't1', title: 'X', amount: 100,
    is_income: false, date: '2026-08-10', client_name: 'Имя',
  });
  assert.strictEqual(t.isIncome, false);
  assert.strictEqual(t.clientName, 'Имя');
});

test('normalize: legacy camelCase тоже принимается', () => {
  const t = normalizeTransaction({
    id: 't1', title: 'X', amount: 100,
    isIncome: true, date: '2026-08-10', clientName: 'Имя',
  });
  assert.strictEqual(t.isIncome, true);
  assert.strictEqual(t.clientName, 'Имя');
});

test('normalize: is_income=false не выглядит как «поле отсутствует»', () => {
  const t = normalizeTransaction({ id: 't1', title: 'X', amount: 0, is_income: false, date: 'x' });
  assert.notStrictEqual(t.isIncome, undefined);
});

test('normalize: отсутствие обоих стилей — isIncome undefined (валидация даст 400)', () => {
  const t = normalizeTransaction({ id: 't1', title: 'X', amount: 1, date: 'x' });
  assert.strictEqual(t.isIncome, undefined);
});
