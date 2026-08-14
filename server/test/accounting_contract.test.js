// Контракт клиентов бухгалтера (accounting_clients) ↔ Dart-модель.
//
// Урок из фикса transactions (коммит b73e101): контракт держим snake_case —
// как читает Dart, — и принимаем оба стиля на входе. Вложенные списки
// (сотрудники, чеклист документов) лежат в JSONB и всегда ездят вместе с
// клиентом: они маленькие и всегда нужны на экране целиком.
const test = require('node:test');
const assert = require('node:assert');

const {
  serializeClient,
  normalizeClient,
} = require('../src/routes/accounting');

test('GET-сериализация: snake_case, числа числами, списки на месте', () => {
  const row = {
    id: 'c1',
    name: 'ТОО «Астана Строй»',
    bin_or_iin: '200540013422',
    entity_type: 'too',
    regime: 'our',
    monthly_fee: '25000.00', // pg NUMERIC приходит строкой
    fee_received_this_month: true,
    notes: null,
    is_active: true,
    phone: null,
    employees: [{ id: 'e1', name: 'Иванов А.А.', salary: 150000 }],
    checklist: [{ id: 'd1', label: 'Банковская выписка', received: false }],
  };
  assert.deepStrictEqual(serializeClient(row), {
    phone: null,
    id: 'c1',
    name: 'ТОО «Астана Строй»',
    bin_or_iin: '200540013422',
    entity_type: 'too',
    regime: 'our',
    monthly_fee: 25000,
    fee_received_this_month: true,
    notes: null,
    is_active: true,
    employees: [{ id: 'e1', name: 'Иванов А.А.', salary: 150000 }],
    checklist: [{ id: 'd1', label: 'Банковская выписка', received: false }],
  });
});

test('normalize: snake_case от приложения', () => {
  const c = normalizeClient({
    id: 'c1', name: 'ИП Ахметов', bin_or_iin: '850304300421',
    entity_type: 'ip', regime: 'simplified910',
    monthly_fee: 15000, fee_received_this_month: false, is_active: true,
  });
  assert.strictEqual(c.binOrIin, '850304300421');
  assert.strictEqual(c.entityType, 'ip');
  assert.strictEqual(c.monthlyFee, 15000);
  assert.strictEqual(c.feeReceivedThisMonth, false);
  assert.strictEqual(c.isActive, true);
});

test('normalize: legacy camelCase тоже принимается', () => {
  const c = normalizeClient({
    id: 'c1', name: 'ИП Ахметов', binOrIin: '850304300421',
    entityType: 'ip', regime: 'simplified910', monthlyFee: 15000,
  });
  assert.strictEqual(c.binOrIin, '850304300421');
  assert.strictEqual(c.entityType, 'ip');
  assert.strictEqual(c.monthlyFee, 15000);
});

test('телефон клиента ездит в обе стороны — по нему бот просит документы', () => {
  const row = serializeClient({
    id: 'c1', name: 'ИП', bin_or_iin: '', entity_type: 'ip', regime: 'our',
    monthly_fee: 0, fee_received_this_month: false, notes: null, is_active: true,
    employees: [], checklist: [], phone: '+7 701 000 00 01',
  });
  assert.strictEqual(row.phone, '+7 701 000 00 01');

  assert.strictEqual(normalizeClient({ phone: '+7 701 000 00 01' }).phone, '+7 701 000 00 01');
  assert.strictEqual(normalizeClient({}).phone, null);
});

test('normalize: умолчания — активен, гонорар 0, пустые списки', () => {
  const c = normalizeClient({ id: 'c1', name: 'ИП', entity_type: 'ip', regime: 'our' });
  assert.strictEqual(c.isActive, true);
  assert.strictEqual(c.monthlyFee, 0);
  assert.strictEqual(c.feeReceivedThisMonth, false);
  assert.deepStrictEqual(c.employees, []);
  assert.deepStrictEqual(c.checklist, []);
});

test('normalize: мусорные типы в списках не роняют сервер', () => {
  const c = normalizeClient({
    id: 'c1', name: 'ИП', entity_type: 'ip', regime: 'our',
    employees: 'не массив', checklist: null,
  });
  assert.deepStrictEqual(c.employees, []);
  assert.deepStrictEqual(c.checklist, []);
});
