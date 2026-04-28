// ── Парсеры XLSX для ЭСФ-сверщика ────────────────────────────────────────────
// Поддерживаем два формата:
//   1. Реестр входящих ЭСФ из ИС ЭСФ (esf.gov.kz → "Экспорт реестра ЭСФ")
//   2. Извещение по форме 300 (cabinet.salyk.kz → ФНО 300 → "Скачать в Excel")
//
// Форматы заголовков менялись со временем. Парсер ищет колонки по
// набору ключевых слов, не привязываясь к конкретной позиции.

const ExcelJS = require('exceljs');

const TEXT_BIN = /^\d{12}$/;

// ── Helpers ──────────────────────────────────────────────────────────────────

function normalizeHeader(s) {
  return String(s || '')
    .toLowerCase()
    .replace(/[^\wа-я0-9]+/gi, '_')
    .replace(/_+/g, '_')
    .replace(/^_|_$/g, '');
}

function toNumber(v) {
  if (v == null || v === '') return 0;
  if (typeof v === 'number') return v;
  if (typeof v === 'object' && 'result' in v) return Number(v.result) || 0;
  const s = String(v).replace(/\s/g, '').replace(',', '.');
  const n = parseFloat(s);
  return isFinite(n) ? n : 0;
}

function toDate(v) {
  if (!v) return null;
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  if (typeof v === 'number') {
    // Excel serial date
    const ms = (v - 25569) * 86400 * 1000;
    return new Date(ms).toISOString().slice(0, 10);
  }
  const s = String(v).trim();
  // dd.mm.yyyy
  let m = s.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})/);
  if (m) return `${m[3]}-${String(m[2]).padStart(2, '0')}-${String(m[1]).padStart(2, '0')}`;
  // yyyy-mm-dd
  m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (m) return `${m[1]}-${String(m[2]).padStart(2, '0')}-${String(m[3]).padStart(2, '0')}`;
  return null;
}

function getCellText(cell) {
  const v = cell?.value;
  if (v == null) return '';
  if (typeof v === 'object') {
    if (v.text) return String(v.text);
    if (v.richText) return v.richText.map(r => r.text).join('');
    if ('result' in v) return String(v.result);
  }
  return String(v);
}

// ── Угадываем колонки по подсказкам в заголовке ──────────────────────────────

const FIELD_HINTS = {
  registration_no: ['регистрационный', 'регистр', 'номер_эсф', 'reg_no'],
  invoice_no:      ['номер_счета', 'номер_сф', 'номер_документа', 'no_invoice', 'счет_фактур'],
  invoice_date:    ['дата_выписки', 'дата_сф', 'дата_счета', 'date_invoice'],
  turnover_date:   ['дата_оборота', 'дата_совершения'],
  status:          ['статус', 'состояние'],
  seller_iin:      ['бин_иин_поставщика', 'бин_поставщика', 'иин_поставщика', 'поставщик_бин', 'продавец'],
  seller_name:     ['наименование_поставщика', 'поставщик'],
  buyer_iin:       ['бин_иин_получателя', 'бин_получателя', 'иин_получателя', 'покупатель_бин', 'получатель'],
  buyer_name:      ['наименование_получателя', 'получатель', 'покупатель'],
  amount_total:    ['итого', 'сумма_с_ндс', 'сумма_оборота_с', 'total'],
  amount_net:      ['сумма_без_ндс', 'без_ндс', 'оборот_без'],
  amount_vat:      ['сумма_ндс', 'ндс', 'vat', 'налог_на_добавленную'],
  vat_rate:        ['ставка_ндс', 'rate'],
  currency:        ['валюта', 'currency'],
};

function guessColumns(headerCells) {
  const headers = headerCells.map((c, i) => ({
    idx: i + 1,
    text: getCellText(c),
    norm: normalizeHeader(getCellText(c)),
  }));

  const map = {};
  for (const [field, hints] of Object.entries(FIELD_HINTS)) {
    for (const h of hints) {
      const found = headers.find(col => col.norm.includes(h));
      if (found) {
        map[field] = found.idx;
        break;
      }
    }
  }
  return { map, headers };
}

// ── Поиск строки заголовков (адаптивно) ──────────────────────────────────────

function findHeaderRow(sheet) {
  // Просматриваем первые 20 строк, ищем ту, где >= 4 ячеек содержат "ИИН|БИН|Поставщик|Получатель|Сумма"
  const SCAN = ['иин', 'бин', 'поставщ', 'получат', 'покупат', 'продав', 'сумма', 'дата', 'номер', 'ндс'];
  let bestRow = 1, bestScore = 0;
  const max = Math.min(sheet.rowCount, 25);
  for (let r = 1; r <= max; r++) {
    const row = sheet.getRow(r);
    let score = 0;
    row.eachCell({ includeEmpty: false }, (cell) => {
      const t = getCellText(cell).toLowerCase();
      if (SCAN.some(k => t.includes(k))) score++;
    });
    if (score > bestScore) { bestScore = score; bestRow = r; }
  }
  return bestScore >= 3 ? bestRow : 1;
}

// ── Reader: реестр ЭСФ ───────────────────────────────────────────────────────
//
// Возвращает: [{ registration_no, invoice_no, invoice_date, ..., raw_row }]

async function parseEsfRegistry(buffer) {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buffer);
  const sheet = wb.worksheets[0];
  if (!sheet) throw new Error('XLSX пустой — нет листов');

  const headerRow = findHeaderRow(sheet);
  const headerCells = [];
  sheet.getRow(headerRow).eachCell({ includeEmpty: true }, (cell) => headerCells.push(cell));
  const { map } = guessColumns(headerCells);

  const required = ['seller_iin', 'invoice_no', 'invoice_date'];
  const missing = required.filter(f => !map[f]);
  if (missing.length) {
    throw new Error(`Не найдены колонки: ${missing.join(', ')}. Проверьте, что это реестр ЭСФ из esf.gov.kz`);
  }

  const rows = [];
  for (let r = headerRow + 1; r <= sheet.rowCount; r++) {
    const row = sheet.getRow(r);
    if (row.cellCount === 0) continue;

    const cell = (field) => map[field] ? getCellText(row.getCell(map[field])) : '';
    const num  = (field) => map[field] ? toNumber(row.getCell(map[field]).value) : 0;
    const date = (field) => map[field] ? toDate(row.getCell(map[field]).value) : null;

    const sellerIin = cell('seller_iin').replace(/\D/g, '');
    if (!TEXT_BIN.test(sellerIin)) continue; // пропускаем строки-итоги

    const item = {
      registration_no: cell('registration_no') || null,
      invoice_no:      cell('invoice_no') || `NO-${r}`,
      invoice_date:    date('invoice_date'),
      turnover_date:   date('turnover_date'),
      status:          cell('status') || 'ISSUED',
      seller_iin:      sellerIin,
      seller_name:     cell('seller_name'),
      buyer_iin:       cell('buyer_iin').replace(/\D/g, ''),
      buyer_name:      cell('buyer_name'),
      amount_total:    num('amount_total'),
      amount_net:      num('amount_net'),
      amount_vat:      num('amount_vat'),
      vat_rate:        num('vat_rate') || null,
      currency:        cell('currency') || 'KZT',
      raw_row:         headerCells.reduce((acc, _, i) => {
        const k = normalizeHeader(getCellText(headerCells[i]));
        if (k) acc[k] = getCellText(row.getCell(i + 1));
        return acc;
      }, {}),
    };
    if (!item.invoice_date) continue;
    rows.push(item);
  }

  return rows;
}

// ── Reader: извещение по форме 300 (приложение 300.07/300.08 — счёт-фактуры в зачёт)

async function parseForm300Notice(buffer) {
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.load(buffer);

  // У 300-й формы строки с ЭСФ обычно на листе с названием "300.07" / "300.08" /
  // или с заголовком "Реестр счетов-фактур по приобретённым товарам, работам, услугам".
  // Возьмём лист, где БОЛЬШЕ всего строк с похожим заголовком.

  let bestSheet = wb.worksheets[0];
  let bestScore = 0;
  for (const sheet of wb.worksheets) {
    let score = 0;
    const max = Math.min(sheet.rowCount, 25);
    for (let r = 1; r <= max; r++) {
      const row = sheet.getRow(r);
      row.eachCell({ includeEmpty: false }, (cell) => {
        const t = getCellText(cell).toLowerCase();
        if (t.includes('бин') || t.includes('иин')) score++;
        if (t.includes('счет-фактур') || t.includes('сф')) score++;
        if (t.includes('ндс')) score++;
      });
    }
    if (score > bestScore) { bestScore = score; bestSheet = sheet; }
  }

  if (!bestSheet) throw new Error('XLSX пустой');
  const sheet = bestSheet;

  const headerRow = findHeaderRow(sheet);
  const headerCells = [];
  sheet.getRow(headerRow).eachCell({ includeEmpty: true }, (cell) => headerCells.push(cell));
  const { map } = guessColumns(headerCells);

  if (!map.seller_iin || !map.invoice_no) {
    throw new Error('Не найдены колонки БИН/ИИН поставщика и № счёта. Проверьте, что это извещение по ф.300.');
  }

  const rows = [];
  for (let r = headerRow + 1; r <= sheet.rowCount; r++) {
    const row = sheet.getRow(r);
    if (row.cellCount === 0) continue;

    const cell = (field) => map[field] ? getCellText(row.getCell(map[field])) : '';
    const num  = (field) => map[field] ? toNumber(row.getCell(map[field]).value) : 0;
    const date = (field) => map[field] ? toDate(row.getCell(map[field]).value) : null;

    const sellerIin = cell('seller_iin').replace(/\D/g, '');
    if (!TEXT_BIN.test(sellerIin)) continue;

    rows.push({
      row_index:    r,
      seller_iin:   sellerIin,
      seller_name:  cell('seller_name'),
      invoice_no:   cell('invoice_no'),
      invoice_date: date('invoice_date'),
      amount_total: num('amount_total'),
      amount_net:   num('amount_net'),
      amount_vat:   num('amount_vat'),
      vat_rate:     num('vat_rate') || null,
      raw_row:      headerCells.reduce((acc, _, i) => {
        const k = normalizeHeader(getCellText(headerCells[i]));
        if (k) acc[k] = getCellText(row.getCell(i + 1));
        return acc;
      }, {}),
    });
  }

  return rows;
}

module.exports = {
  parseEsfRegistry,
  parseForm300Notice,
};
