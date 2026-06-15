// Регрессионный чек: POST /api/invoices с item без `id` должен вернуть 201, а не 500.
// invoice_items.id — NOT NULL PRIMARY KEY; раньше item.id=undefined → NULL → 23502 → 500.
// Мокаем db/tiers/middleware и гоняем реальный обработчик роута. Запуск: node scripts/test-invoice-item-id.js
const path   = require('path');
const Module = require('module');
const express = require('express');

// --- подменяем зависимости в require.cache ДО require самого роутера ---
function mock(absNoExt, exports) {
  const resolved = require.resolve(absNoExt);
  const m = new Module(resolved, module);
  m.filename = resolved;
  m.loaded   = true;
  m.exports  = exports;
  require.cache[resolved] = m;
}

const insertedItemIds = [];
const fakeClient = {
  async query(sql, params = []) {
    if (/INSERT INTO invoice_items/i.test(sql)) {
      const itemId = params[0];
      // эмулируем NOT NULL PRIMARY KEY на invoice_items.id
      if (itemId === null || itemId === undefined) {
        const e = new Error('null value in column "id" of relation "invoice_items" violates not-null constraint');
        e.code = '23502';
        throw e;
      }
      insertedItemIds.push(itemId);
    }
    if (/SELECT tier FROM users/i.test(sql)) return { rows: [{ tier: 'pro' }] };
    if (/COUNT\(\*\)/i.test(sql))            return { rows: [{ count: '0' }] };
    return { rows: [], rowCount: 1 };
  },
  release() {},
};

mock(path.join(__dirname, '..', 'src', 'db'), {
  async query() { return { rows: [], rowCount: 1 }; },
  async connect() { return fakeClient; },
});
mock(path.join(__dirname, '..', 'src', 'tiers'), {
  limitsFor: () => ({ invoicesPerMonth: Infinity }),
});
mock(path.join(__dirname, '..', 'src', 'middleware', 'requireSubscription'),
  (req, res, next) => next());

const invoicesRouter = require(path.join(__dirname, '..', 'src', 'routes', 'invoices'));

const app = express();
app.use(express.json());
app.use((req, res, next) => { req.userId = 'test-user'; next(); });
app.use('/api/invoices', invoicesRouter);

let failures = 0;
const check = (name, ok, extra = '') => {
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? '  ' + extra : ''}`);
  if (!ok) failures++;
};

const server = app.listen(0, async () => {
  const base = `http://127.0.0.1:${server.address().port}/api/invoices`;
  const post = (body) => fetch(base, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });

  try {
    // 1) item БЕЗ id — раньше 500, теперь 201 (id сгенерён)
    const before = insertedItemIds.length;
    const r1 = await post({
      id: 'inv-no-itemid', number: 'INV-001', clientName: 'ТОО Тест',
      items: [{ description: 'Услуга', quantity: 1, unitPrice: 1000 }],
    });
    check('item без id → 201 (не 500)', r1.status === 201, `got ${r1.status}`);
    const generated = insertedItemIds[before];
    check('сгенерён непустой id для item', typeof generated === 'string' && generated.length > 0,
      `id=${generated}`);

    // 2) happy path — item С id, поведение не меняется
    const r2 = await post({
      id: 'inv-with-itemid', number: 'INV-002', clientName: 'ТОО Тест',
      items: [{ id: 'item-keep-me', description: 'Услуга', quantity: 2, unitPrice: 500 }],
    });
    check('item с id → 201', r2.status === 201, `got ${r2.status}`);
    check('переданный id сохранён как есть', insertedItemIds.includes('item-keep-me'));

    // 3) отсутствие обязательных полей — по-прежнему 400
    const r3 = await post({ items: [] });
    check('нет id/number/clientName → 400', r3.status === 400, `got ${r3.status}`);
  } catch (e) {
    console.log('  FAIL  непойманное исключение:', e.message);
    failures++;
  } finally {
    server.close();
    console.log(failures ? `\n${failures} проверок упало` : '\nВсе проверки прошли');
    process.exit(failures ? 1 : 0);
  }
});
