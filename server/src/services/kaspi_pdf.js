// Разбор PDF-выписки Kaspi Gold.
//
// Kaspi отдаёт «Справку + Выписку» одним PDF. pdf-parse извлекает текст,
// операции в нём — строки вида:
//   «12.08.26 - 2 230,00 ₸ Покупка Rancho магазин продуктов»
//   «11.08.26 + 149 000,00 ₸ Пополнение С карты другого банка»
// Шапки страниц, «Краткое содержание», футеры «-- N of M --» под этот
// паттерн не попадают: строка обязана НАЧИНАТЬСЯ с даты. Строки сводки
// («Доступно на 12.08.25 + 361,62 ₸ …») начинаются со слов — мимо.
//
// Проверено на реальных выписках (34 страницы, 1429 операций): суммы
// разобранных строк сходятся с блоком «Краткое содержание» до тиына.
const { PDFParse } = require('pdf-parse');

// Дата, знак, сумма (пробелы/NBSP как разделители тысяч, копейки через
// запятую), «₸», затем тип операции одним словом и произвольные детали.
const LINE_RE =
  /^(\d{2})\.(\d{2})\.(\d{2}|\d{4})\s*([+-])\s*([\d\s ]+(?:,\d{1,2})?)\s*₸\s*(?:(\S+)\s*(.*))?$/u;

function parseAmount(raw) {
  return parseFloat(raw.replace(/[\s ]/g, '').replace(',', '.'));
}

/**
 * Текст PDF → операции.
 * @returns {{rows: Array<{date, amount, isIncome, operation, details}>, warnings: string[]}}
 */
function parseKaspiPdfText(text) {
  const rows = [];
  for (const line of String(text ?? '').split('\n')) {
    const m = LINE_RE.exec(line.trim());
    if (!m) continue;
    const [, dd, mm, yy, sign, amountRaw, operation = '', details = ''] = m;
    const year = yy.length === 2 ? `20${yy}` : yy;
    const amount = parseAmount(amountRaw);
    if (!Number.isFinite(amount)) continue;
    rows.push({
      date: `${year}-${mm}-${dd}`,
      amount,
      isIncome: sign === '+',
      operation,
      details: details.trim(),
    });
  }

  const warnings = [];
  if (!rows.length) {
    warnings.push(
      'В PDF не нашлось операций. Поддерживается выписка Kaspi Gold ' +
        '(приложение Kaspi → Мой банк → Выписка). Для других банков ' +
        'используйте Excel или CSV.',
    );
  }
  return { rows, warnings };
}

/** PDF-файл (Buffer) → операции. */
async function parseKaspiPdfBuffer(buffer) {
  const parser = new PDFParse({ data: new Uint8Array(buffer) });
  try {
    const { text } = await parser.getText();
    return parseKaspiPdfText(text);
  } finally {
    await parser.destroy().catch(() => {});
  }
}

module.exports = { parseKaspiPdfText, parseKaspiPdfBuffer };
