// Бот сбора документов: текст запроса клиенту бухгалтера.
//
// Бухгалтер каждый месяц вручную пишет каждому клиенту «пришлите выписку» —
// на 30 клиентах это половина рабочей недели. Бот шлёт запрос сам, по
// чеклисту документов из карточки клиента.
//
// Представляется КОМПАНИЕЙ Esep, а не продуктом: под Esep несколько
// направлений (бухфирмы, платформы, автоматизация, Connect), и клиент
// бухгалтера не должен гадать, что ему написали.
const test = require('node:test');
const assert = require('node:assert');

const { buildDocRequest } = require('../src/services/doc_request');

const CLIENT = {
  name: 'ТОО «Астана Строй»',
  phone: '+7 701 000 00 01',
  checklist: [
    { id: 'd1', label: 'Банковская выписка за август', received: true },
    { id: 'd2', label: 'Реестр доходов за август', received: false },
    { id: 'd3', label: 'Акты выполненных работ', received: false },
  ],
};

test('в тексте есть имя клиента и только недостающие документы', () => {
  const { text } = buildDocRequest(CLIENT, { firmName: 'Бухфирма Астана' });

  assert.ok(text.includes('ТОО «Астана Строй»'), 'имя клиента');
  assert.ok(text.includes('Реестр доходов за август'), 'недостающий документ');
  assert.ok(text.includes('Акты выполненных работ'), 'недостающий документ');
  assert.ok(!text.includes('Банковская выписка'), 'полученное не просим повторно');
});

test('бот представляется компанией Esep и называет бухгалтера', () => {
  const { text } = buildDocRequest(CLIENT, { firmName: 'Бухфирма Астана' });

  assert.ok(/компани[ияй]\s+Esep/i.test(text), 'называет компанию Esep');
  assert.ok(text.includes('Бухфирма Астана'), 'от чьего имени просим');
});

test('без названия фирмы текст остаётся корректным', () => {
  const { text } = buildDocRequest(CLIENT, {});
  assert.ok(text.includes('ваш бухгалтер'), 'нейтральная формулировка');
  assert.ok(!text.includes('undefined'));
});

test('все документы получены — сообщение не формируется', () => {
  const done = {
    ...CLIENT,
    checklist: CLIENT.checklist.map((d) => ({ ...d, received: true })),
  };
  const res = buildDocRequest(done, {});
  assert.strictEqual(res.text, null);
  assert.strictEqual(res.reason, 'all_received');
});

test('нет телефона — отправлять некуда', () => {
  const res = buildDocRequest({ ...CLIENT, phone: '' }, {});
  assert.strictEqual(res.text, null);
  assert.strictEqual(res.reason, 'no_phone');
});

test('телефон нормализуется в формат WhatsApp', () => {
  for (const [raw, expected] of [
    ['+7 701 000 00 01', '77010000001'],
    ['8 701 000 00 01', '77010000001'],
    ['7010000001', '77010000001'],
    ['+77010000001', '77010000001'],
  ]) {
    const { number } = buildDocRequest({ ...CLIENT, phone: raw }, {});
    assert.strictEqual(number, expected, raw);
  }
});
