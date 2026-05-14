// Реплика логики lib/core/services/esf_service.dart на Node.js.
// Формат — контейнер импорта ИС ЭСФ:
//   esf:invoiceInfoContainer → invoiceBody (CDATA) → v2:invoice
// Только для генерации тестовых XML — НЕ продакшен-код.
// Запуск: node samples/esf/_generate.js
//
// На выходе:
//   esf-vat.xml         — плательщик НДС, ИИН покупателя заполнен
//   esf-novat.xml       — не плательщик НДС, ИИН заполнен
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

// Числа как в ИС ЭСФ: точка, без разделителей тысяч, хвостовые нули обрезаны.
function num(v) {
  const rounded = Math.round(Number(v) * 100) / 100;
  if (Number.isInteger(rounded)) return String(rounded);
  return String(rounded).replace(/0+$/, '').replace(/\.$/, '');
}

function dateFmt(d) {
  const dd = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const yyyy = d.getFullYear();
  return `${dd}.${mm}.${yyyy}`;
}

function validate(invoice, company) {
  const errors = [];
  const warnings = [];

  if (!company.name) errors.push('Не заполнено название/ФИО поставщика');
  if (!company.iin) errors.push('Не заполнен ИИН/БИН поставщика');
  else if (company.iin.length !== 12) errors.push('ИИН/БИН поставщика должен содержать 12 цифр');
  if (!company.operatorFullname) errors.push('Не заполнено ФИО оператора');

  if (!invoice.clientName) errors.push('Не указано имя покупателя');
  if (!invoice.buyerIin) warnings.push('ИИН/БИН покупателя не указан — ЭСФ не примет получатель-юрлицо');
  else if (invoice.buyerIin.length !== 12) errors.push('ИИН/БИН покупателя должен содержать 12 цифр');

  if (!invoice.items || invoice.items.length === 0) errors.push('В счёте нет ни одной позиции');
  for (const item of invoice.items || []) {
    if (!item.esfUnitCode) warnings.push(`Позиция «${item.description}»: не заполнен код единицы измерения ЭСФ`);
  }

  if (!company.iik) warnings.push('Не заполнен ИИК поставщика');

  return { errors, warnings, isValid: errors.length === 0 };
}

function buildInvoiceBody(invoice, company) {
  const isVat = !!company.isVatPayer;
  const invoiceDate = dateFmt(invoice.createdAt);
  const turnoverDate = dateFmt(invoice.turnoverDate || invoice.createdAt);
  const operator = company.operatorFullname || company.name;

  let totalNet = 0, totalVat = 0, totalGross = 0;

  const products = (invoice.items || []).map((item) => {
    const net = item.quantity * item.unitPrice;
    const vat = isVat ? net * VAT_RATE : 0;
    const gross = net + vat;
    totalNet += net;
    totalVat += vat;
    totalGross += gross;

    const unitNomenclature = item.esfUnitCode
      ? `\n                <unitNomenclature>${esc(item.esfUnitCode)}</unitNomenclature>`
      : '';

    return `            <product>
                <catalogTruId>${esc(item.catalogTruId || '1')}</catalogTruId>
                <description>${esc(item.description)}</description>
                <ndsAmount>${num(vat)}</ndsAmount>
                <priceWithTax>${num(gross)}</priceWithTax>
                <priceWithoutTax>${num(net)}</priceWithoutTax>
                <quantity>${num(item.quantity)}</quantity>
                <truOriginCode>${esc(item.truOriginCode || '5')}</truOriginCode>
                <turnoverSize>${num(net)}</turnoverSize>${unitNomenclature}
                <unitPrice>${num(item.unitPrice)}</unitPrice>
            </product>`;
  }).join('\n');

  const consignorAddress = invoice.consignorSameAsSeller !== false
    ? (company.address || '') : (invoice.consignorAddress || '');
  const consignorName = invoice.consignorSameAsSeller !== false
    ? company.name : (invoice.consignorName || '');
  const consignorTin = invoice.consignorSameAsSeller !== false
    ? company.iin : (invoice.consignorTin || '');

  const consigneeAddress = invoice.consigneeSameAsCustomer !== false
    ? '' : (invoice.consigneeAddress || '');
  const consigneeName = invoice.consigneeSameAsCustomer !== false
    ? invoice.clientName : (invoice.consigneeName || '');
  const consigneeTin = invoice.consigneeSameAsCustomer !== false
    ? (invoice.buyerIin || '') : (invoice.consigneeTin || '');

  const hasContract = !!(invoice.contractNum && invoice.contractNum.length);
  let deliveryTerm = '    <deliveryTerm>\n';
  if (hasContract) {
    if (invoice.contractDate) {
      deliveryTerm += `        <contractDate>${dateFmt(invoice.contractDate)}</contractDate>\n`;
    }
    deliveryTerm += `        <contractNum>${esc(invoice.contractNum)}</contractNum>\n`;
    deliveryTerm += '        <hasContract>true</hasContract>\n';
  } else {
    deliveryTerm += '        <hasContract>false</hasContract>\n';
  }
  deliveryTerm += '    </deliveryTerm>';

  let deliveryDoc = '';
  if (invoice.deliveryDocDate) {
    deliveryDoc += `    <deliveryDocDate>${dateFmt(invoice.deliveryDocDate)}</deliveryDocDate>\n`;
  }
  if (invoice.deliveryDocNum) {
    deliveryDoc += `    <deliveryDocNum>${esc(invoice.deliveryDocNum)}</deliveryDocNum>\n`;
  }

  return `<v2:invoice xmlns:a="abstractInvoice.esf" xmlns:v2="v2.esf">
    <date>${invoiceDate}</date>
    <invoiceType>ORDINARY_INVOICE</invoiceType>
    <num>${esc(invoice.number)}</num>
    <operatorFullname>${esc(operator)}</operatorFullname>
    <turnoverDate>${turnoverDate}</turnoverDate>
    <consignee>
        <address>${esc(consigneeAddress)}</address>
        <countryCode>KZ</countryCode>
        <name>${esc(consigneeName)}</name>
        <tin>${esc(consigneeTin)}</tin>
    </consignee>
    <consignor>
        <address>${esc(consignorAddress)}</address>
        <name>${esc(consignorName)}</name>
        <tin>${esc(consignorTin)}</tin>
    </consignor>
    <customers>
        <customer>
            <address></address>
            <countryCode>KZ</countryCode>
            <name>${esc(invoice.clientName)}</name>
            <tin>${esc(invoice.buyerIin || '')}</tin>
        </customer>
    </customers>
${deliveryDoc}${deliveryTerm}
    <productSet>
        <currencyCode>KZT</currencyCode>
        <products>
${products}
        </products>
        <totalExciseAmount>0</totalExciseAmount>
        <totalNdsAmount>${num(totalVat)}</totalNdsAmount>
        <totalPriceWithTax>${num(totalGross)}</totalPriceWithTax>
        <totalPriceWithoutTax>${num(totalNet)}</totalPriceWithoutTax>
        <totalTurnoverSize>${num(totalNet)}</totalTurnoverSize>
    </productSet>
    <sellers>
        <seller>
            <address>${esc(company.address || '')}</address>
            <bank>${esc(company.bankName || '')}</bank>
            <bik>${esc(company.bik || '')}</bik>
            <iik>${esc(company.iik || '')}</iik>
            <kbe>${esc(company.kbe || '19')}</kbe>
            <name>${esc(company.name)}</name>
            <tin>${esc(company.iin)}</tin>
        </seller>
    </sellers>
</v2:invoice>`;
}

function generate(invoice, company) {
  const body = buildInvoiceBody(invoice, company);
  return `<?xml version="1.0" encoding="UTF-8"?><esf:invoiceInfoContainer xmlns:esf="esf">
  <invoiceSet>
    <invoiceInfo>
      <invoiceBody><![CDATA[${body}]]></invoiceBody>
    </invoiceInfo>
  </invoiceSet>
</esf:invoiceInfoContainer>`;
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
  operatorFullname: 'Алибеков Аскар Канатович',
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
    { description: 'Консультация по форме 910', quantity: 1, unitPrice: 50000, esfUnitCode: '5114', catalogTruId: '1', truOriginCode: '5' },
    { description: 'Настройка учёта', quantity: 2, unitPrice: 25000, esfUnitCode: '5114', catalogTruId: '1', truOriginCode: '5' },
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
