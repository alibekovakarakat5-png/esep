// Реплика логики lib/core/services/esf_service.dart на Node.js.
// Только для генерации тестовых XML — НЕ продакшен-код.
// Запуск: node samples/esf/_generate.js
//
// На выходе:
//   esf-vat.xml    — плательщик НДС, ИИН покупателя заполнен
//   esf-novat.xml  — не плательщик НДС, ИИН заполнен
//   esf-missing-iin.xml — без ИИН покупателя (warning)
//   esf-incomplete.xml  — пустой поставщик (error)

const fs = require('fs');
const path = require('path');

const VAT_RATE = 0.16;

function esc(s) {
  if (s == null) return '';
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function fmt(num) {
  return Number(num).toFixed(2);
}

function dateFmt(d) {
  return d.toISOString().slice(0, 10);
}

function toEsfNumber(invoiceNumber) {
  return invoiceNumber.replace('СЧ-', 'ЭСФ-');
}

function validate(invoice, company) {
  const errors = [];
  const warnings = [];

  if (!company.name) errors.push('Не заполнено название/ФИО поставщика');
  if (!company.iin) errors.push('Не заполнен ИИН/БИН поставщика');
  else if (company.iin.length !== 12) errors.push('ИИН/БИН поставщика должен содержать 12 цифр');

  if (!invoice.clientName) errors.push('Не указано имя покупателя');
  if (!invoice.buyerIin) warnings.push('ИИН/БИН покупателя не указан — ЭСФ не примет получатель-юрлицо');
  else if (invoice.buyerIin.length !== 12) errors.push('ИИН/БИН покупателя должен содержать 12 цифр');

  if (!invoice.items || invoice.items.length === 0) errors.push('В счёте нет ни одной позиции');

  if (!company.iik) warnings.push('Не заполнен ИИК поставщика');

  return { errors, warnings, isValid: errors.length === 0 };
}

function generate(invoice, company) {
  const now = new Date();
  const invoiceDate = dateFmt(invoice.createdAt);
  const today = dateFmt(now);
  const esfNumber = toEsfNumber(invoice.number);
  const isVat = !!company.isVatPayer;

  let totalNet = 0, totalVat = 0, totalGross = 0;

  const items = invoice.items.map((item, idx) => {
    const i = idx + 1;
    const net = item.quantity * item.unitPrice;
    const vat = isVat ? net * VAT_RATE : 0;
    const gross = net + vat;
    totalNet += net;
    totalVat += vat;
    totalGross += gross;

    return `    <PRODUCT>
      <NUM>${i}</NUM>
      <DESCRIPTION>${esc(item.description)}</DESCRIPTION>
      <UNIT_CODE>${esc(item.unitCode)}</UNIT_CODE>
      <UNIT_NAME>${esc(item.unitName)}</UNIT_NAME>
      <COUNT>${fmt(item.quantity)}</COUNT>
      <PRICE>${fmt(item.unitPrice)}</PRICE>
      <NET_TURNOVER>${fmt(net)}</NET_TURNOVER>
      <NDS_RATE>${isVat ? 'NDS_16' : 'WITHOUT_NDS'}</NDS_RATE>
      <NDS_SUM>${fmt(vat)}</NDS_SUM>
      <TURNOVER_WITH_NDS>${fmt(gross)}</TURNOVER_WITH_NDS>
    </PRODUCT>`;
  }).join('\n');

  const buyerIin = invoice.buyerIin || '';
  const buyerIinNode = buyerIin
    ? `<IIN_BIN>${esc(buyerIin)}</IIN_BIN>`
    : `<!-- ИИН/БИН покупателя не заполнен -->`;

  const vatNotice = isVat
    ? 'Поставщик является плательщиком НДС: ставка 16% по НК РК 2026'
    : 'Поставщик не является плательщиком НДС (СНР/упрощёнка)';

  const bankBlock = company.iik
    ? `    <BANK_DETAILS>
      <NAME>${esc(company.bankName || '')}</NAME>
      <IIK>${esc(company.iik || '')}</IIK>
      <BIK>${esc(company.bik || '')}</BIK>
      <KBE>${esc(company.kbe || '19')}</KBE>
    </BANK_DETAILS>`
    : '    <!-- Банковские реквизиты не заполнены -->';

  return `<?xml version="1.0" encoding="UTF-8"?>
<!--
  ЭСФ сгенерирован приложением Esep (esep.kz)
  Для загрузки перейдите: https://esf.gov.kz
  Дата генерации: ${today}
  ${vatNotice}
-->
<ESF xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">

  <!-- 1. Заголовок -->
  <HEADER>
    <INVOICE_NUM>${esfNumber}</INVOICE_NUM>
    <INVOICE_DATE>${invoiceDate}</INVOICE_DATE>
    <DELIVERY_DATE>${invoiceDate}</DELIVERY_DATE>
    <TYPE>ORDINARY</TYPE>
    <CORRECTION>false</CORRECTION>
    <INPUT_TYPE>MANUAL</INPUT_TYPE>
  </HEADER>

  <!-- 2. Поставщик -->
  <SELLER>
    <IIN>${esc(company.iin)}</IIN>
    <NAME>${esc(company.name)}</NAME>
    <ADDRESS>${esc(company.address || '')}</ADDRESS>
    <IS_VAT_PAYER>${isVat ? 'true' : 'false'}</IS_VAT_PAYER>
${bankBlock}
  </SELLER>

  <!-- 3. Получатель -->
  <BUYER>
    ${buyerIinNode}
    <NAME>${esc(invoice.clientName)}</NAME>
  </BUYER>

  <!-- 4. Оборот -->
  <TURNOVER>
${items}
  </TURNOVER>

  <!-- 5. Итого -->
  <TOTAL>
    <TOTAL_NET_TURNOVER>${fmt(totalNet)}</TOTAL_NET_TURNOVER>
    <TOTAL_NDS>${fmt(totalVat)}</TOTAL_NDS>
    <TOTAL_TURNOVER_WITH_NDS>${fmt(totalGross)}</TOTAL_TURNOVER_WITH_NDS>
  </TOTAL>

  <!--
    ВАЖНО: Перед отправкой в ИС ЭСФ:
    1. Убедитесь что ИИН/БИН покупателя заполнен (12 цифр)
    2. Подпишите файл ЭЦП (НУЦ РК) в портале esf.gov.kz
    3. Или загрузите XML вручную через импорт
  -->

</ESF>`;
}

// ─── Test fixtures ────────────────────────────────────────────────────────

const companyComplete = {
  name: 'ИП Алибеков А.К.',
  iin: '900101300123',
  address: 'г. Астана, пр. Кабанбай батыра, 11',
  isVatPayer: false,
  bankName: 'Kaspi Bank',
  iik: 'KZ123456789012345678',
  bik: 'CASPKZKA',
  kbe: '19',
};

const companyVat = { ...companyComplete, isVatPayer: true };

const companyEmpty = {
  name: '',
  iin: '',
  isVatPayer: false,
};

const invoice = {
  number: 'СЧ-2026-001',
  clientName: 'ТОО АстанаТрейд',
  buyerIin: '060540001234',
  createdAt: new Date('2026-05-12'),
  items: [
    { description: 'Консультация по форме 910', quantity: 1, unitPrice: 50000, unitCode: '931', unitName: 'услуга' },
    { description: 'Настройка учёта', quantity: 2, unitPrice: 25000, unitCode: '356', unitName: 'час' },
  ],
};

const invoiceNoIin = { ...invoice, buyerIin: null };

const scenarios = [
  { file: 'esf-novat.xml',         desc: 'СНР/упрощёнка, ИИН покупателя есть', invoice, company: companyComplete },
  { file: 'esf-vat.xml',           desc: 'Плательщик НДС, ИИН есть',           invoice, company: companyVat },
  { file: 'esf-missing-iin.xml',   desc: 'СНР, ИИН покупателя пустой',         invoice: invoiceNoIin, company: companyComplete },
  { file: 'esf-incomplete.xml',    desc: 'Пустой поставщик (тест ошибок)',     invoice, company: companyEmpty },
];

const outDir = __dirname;
const report = [];

for (const s of scenarios) {
  const validation = validate(s.invoice, s.company);
  const xml = generate(s.invoice, s.company);
  const outPath = path.join(outDir, s.file);
  fs.writeFileSync(outPath, xml, 'utf8');

  report.push({
    file: s.file,
    desc: s.desc,
    bytes: Buffer.byteLength(xml, 'utf8'),
    errors: validation.errors,
    warnings: validation.warnings,
    isValid: validation.isValid,
  });
}

console.log(JSON.stringify(report, null, 2));
