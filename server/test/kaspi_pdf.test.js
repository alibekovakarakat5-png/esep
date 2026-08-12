// Разбор PDF-выписки Kaspi Gold (services/kaspi_pdf.js).
// Формат строки операции (текст из pdf-parse):
//   «12.08.26 - 2 230,00 ₸ Покупка Rancho магазин продуктов»
//   «11.08.26 + 149 000,00 ₸ Пополнение С карты другого банка»
// Всё остальное (шапки страниц, сводка, футеры «-- N of M --») — мимо.
// Синтетика 1:1 повторяет структуру реального файла; сам реальный PDF в
// репозиторий не кладём — это персональные данные.
const test = require('node:test');
const assert = require('node:assert');

const { parseKaspiPdfText } = require('../src/services/kaspi_pdf');

const SAMPLE = [
  'АО «Kaspi Bank», БИК CASPKZKA, www.kaspi.kz',
  'СПРАВКА',
  'об остатке на счете',
  'Выписка по Kaspi Gold за период с 12.08.25 по 12.08.26 прилагается.',
  '-- 1 of 2 --',
  'Приложение к Справке №1256448077 от 12 августа 2026',
  'ВЫПИСКА',
  'по Kaspi Gold за период с 12.08.25 по 12.08.26',
  'Доступно на 12.08.26: + 50 136,93 ₸ Валюта счета: теңге',
  'Краткое содержание операций по карте: Лимит на снятие наличности без комиссии:',
  'Пополнения + 5 391 109,00 ₸ Другие пополнения 300 000,00 ₸',
  'Переводы - 3 069 245,00 ₸',
  'Дата Сумма Операция Детали',
  '12.08.26 - 2 230,00 ₸ Покупка Rancho магазин продуктов',
  '12.08.26 - 200,00 ₸ Покупка Tarlan Astana (LRT). Оплата проезда',
  '11.08.26 + 149 000,00 ₸ Пополнение С карты другого банка',
  '11.08.26 - 1 600,00 ₸ Перевод Қуандық М.',
  '-- 2 of 2 --',
  '31.12.25 + 300 000,00 ₸ Пополнение',
  '01.01.26 - 50 000,00 ₸ Снятие Банкомат',
].join('\n');

test('строки операций разбираются: дата, знак, сумма, тип, детали', () => {
  const { rows } = parseKaspiPdfText(SAMPLE);
  assert.strictEqual(rows.length, 6);

  assert.deepStrictEqual(rows[0], {
    date: '2026-08-12',
    amount: 2230,
    isIncome: false,
    operation: 'Покупка',
    details: 'Rancho магазин продуктов',
  });

  const income = rows.find((r) => r.isIncome && r.amount === 149000);
  assert.ok(income, 'пополнение найдено');
  assert.strictEqual(income.operation, 'Пополнение');
  assert.strictEqual(income.details, 'С карты другого банка');
});

test('детали могут быть пустыми, двузначный год расширяется в 20xx', () => {
  const { rows } = parseKaspiPdfText(SAMPLE);
  const bare = rows.find((r) => r.date === '2025-12-31');
  assert.ok(bare);
  assert.strictEqual(bare.operation, 'Пополнение');
  assert.strictEqual(bare.details, '');
  assert.strictEqual(bare.isIncome, true);
});

test('служебные строки не попадают в операции', () => {
  const { rows } = parseKaspiPdfText(SAMPLE);
  for (const r of rows) {
    assert.ok(!/Kaspi Bank|Справк|Доступно|Пополнения \+/.test(r.details), JSON.stringify(r));
  }
});

test('пустой текст — ноль строк и предупреждение', () => {
  const { rows, warnings } = parseKaspiPdfText('какой-то не тот PDF');
  assert.strictEqual(rows.length, 0);
  assert.ok(warnings.length >= 1);
});
