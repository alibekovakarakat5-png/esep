// Форма 910.00 (Упрощённая декларация) — порт lib/core/services/form910_service.dart.
//
// Имена полей (field_910_00_001 и т.д.) — из официального пакета СОНО v27 r133,
// см. docs/forms/form-910-00-v27-spec.md. Конверт XML (СОНО) и схема JSON (КНП
// ИСНА) публично не опубликованы — реализованы по обоснованной догадке, перед
// боевой подачей сверить с реальным образцом экспорта из 1С / КНП ИСНА.
// Реальная форма ждёт помесячную разбивку (поля _1.._6) — здесь 6-месячные
// агрегаты, как и в Dart-версии.
//
// Дата генерации инъектируется опцией { now } — для детерминированных тестов.

const { calculateMonthlySocial } = require('./calc');

const FORM_CODE = '910.00';
const FORM_VERSION = 27;
const FORM_REVISION = 133;

// Источники, считающиеся безналичными для строки 910.00.001 A
const NON_CASH_SOURCES = ['kaspi', 'перевод', 'карта'];

// Дата транзакции: строка 'YYYY-MM-DD[...]' разбирается без таймзонных сдвигов,
// Date — по локальным полям (как DateTime в Dart).
function txYearMonth(date) {
  if (date instanceof Date) return { year: date.getFullYear(), month: date.getMonth() + 1 };
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(date));
  if (!m) throw new Error(`Неразбираемая дата транзакции: ${date}`);
  return { year: Number(m[1]), month: Number(m[2]) };
}

// Расчёт данных формы 910.00 из транзакций (порт Form910Service.calculate).
function calculateForm910(rates, input) {
  const {
    iin,
    fullName,
    halfYear, // 1 или 2
    year,
    declarationType = 'очередная', // 'очередная' | 'дополнительная' | 'ликвидационная'
    transactions = [],
    employeeCount = 0,
    totalPayroll = 0,
    bornBefore1975 = false,
  } = input;

  const startMonth = halfYear === 1 ? 1 : 7;
  const endMonth = halfYear === 1 ? 6 : 12;

  const relevant = transactions.filter((t) => {
    const d = txYearMonth(t.date);
    return d.year === year && d.month >= startMonth && d.month <= endMonth;
  });

  const income = relevant
    .filter((t) => t.isIncome)
    .reduce((s, t) => s + t.amount, 0);

  const incomeNonCash = relevant
    .filter((t) => t.isIncome && NON_CASH_SOURCES.includes(t.source))
    .reduce((s, t) => s + t.amount, 0);

  // Налог (Новый НК РК 2026, ставка 4%)
  const calculatedTax = income * (rates.ipn_rate_910 + rates.sn_rate_910);
  // Региональные 2-6% учитываются настроенной ставкой 910
  const taxAdjustment = 0;
  const netTax = calculatedTax - taxAdjustment;
  const ipn = netTax; // 100% ИПН

  // Соцплатежи за полугодие (6 месяцев)
  const social = calculateMonthlySocial(rates, { bornBefore1975 });

  // СН = 0% для СНР с 2026
  const socialTax = 0;

  const totalTax = ipn + socialTax;
  const totalSocial = (social.so + social.opv + social.opvr + social.vosms) * 6;

  return {
    iin,
    fullName,
    halfYear,
    year,
    declarationType,
    income,
    incomeNonCash,
    incomeEcommerce: 0,
    transferPricing: 0,
    avgEmployees: employeeCount,
    avgMonthlyWage: employeeCount > 0 ? totalPayroll / employeeCount : 0,
    calculatedTax,
    taxAdjustment,
    netTax,
    ipn,
    socialTax,
    soIncome: rates.mzp * 6,
    soAmount: social.so * 6,
    opvIncome: rates.mzp * 6,
    opvAmount: social.opv * 6,
    opvrAmount: social.opvr * 6,
    vosmsAmount: social.vosms * 6,
    totalTax,
    totalSocial,
    grandTotal: totalTax + totalSocial,
    periodLabel: halfYear === 1 ? `1-е полугодие ${year}` : `2-е полугодие ${year}`,
  };
}

// Данные → официальные имена полей формы 910.00 v27 (порядок фиксирован).
function fieldValues(d) {
  return {
    field_910_00_001: d.income,
    field_910_00_001_A: d.incomeNonCash,
    field_910_00_001_B: d.incomeEcommerce,
    field_910_00_002: d.transferPricing,
    field_910_00_003: d.avgEmployees,
    field_910_00_004: d.avgMonthlyWage,
    field_910_00_005: d.calculatedTax,
    field_910_00_006: d.taxAdjustment,
    field_910_00_007: d.netTax,
    field_910_00_008: d.ipn,
    field_910_00_009: d.socialTax,
    field_910_00_010: d.soIncome,
    field_910_00_011: d.soAmount,
    field_910_00_012: d.opvIncome,
    field_910_00_013: d.opvAmount,
    field_910_00_014: d.opvrAmount,
    field_910_00_015: d.vosmsAmount,
  };
}

// Чекбокс типа декларации (dt_main / dt_additional / dt_final).
function declarationTypeField(d) {
  switch (d.declarationType) {
    case 'дополнительная':
      return 'dt_additional';
    case 'ликвидационная':
      return 'dt_final';
    default:
      return 'dt_main';
  }
}

const fmtAmount = (v) => v.toFixed(2); // NumberFormat('0.00', 'en_US')

const fmtDate = (d) => {
  const dd = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  return `${dd}.${mm}.${d.getFullYear()}`; // DateFormat('dd.MM.yyyy')
};

// regex-replace вместо replaceAll (ES2021): бандл лендинга должен работать
// в браузерах уровня ES2019, esbuild рантайм-API не полифиллит
function escapeXml(input) {
  return String(input)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

// XML для СОНО. Имена полей официальные, конверт — по догадке.
function generateForm910Xml(data, { now = new Date() } = {}) {
  const fields = fieldValues(data);
  const dtField = declarationTypeField(data);
  const fieldXml = Object.entries(fields)
    .map(([k, v]) => `  <${k}>${fmtAmount(v)}</${k}>`)
    .join('\n');

  return `<?xml version="1.0" encoding="UTF-8"?>
<!--
  Форма 910.00 (версия ${FORM_VERSION}, ревизия ${FORM_REVISION}) — сгенерирована Esep.
  Имена полей — из официального пакета СОНО. Корневой конверт реализован
  по догадке: ПЕРЕД ПОДАЧЕЙ сверить с образцом экспорта из 1С/СОНО.
  Дата генерации: ${fmtDate(now)}
-->
<form code="${FORM_CODE}" version="${FORM_VERSION}" revision="${FORM_REVISION}">
  <iin>${escapeXml(data.iin)}</iin>
  <payer_name1>${escapeXml(data.fullName)}</payer_name1>
  <period_year>${data.year}</period_year>
  <period_half_year>${data.halfYear}</period_half_year>
  <${dtField}>1</${dtField}>
  <currency_code>KZT</currency_code>
${fieldXml}
</form>`;
}

// JSON для КНП ИСНА. Схема не опубликована — конверт по обоснованной догадке.
// Отличие от Dart: generatedAt в UTC (toISOString), Dart пишет локальное время.
function generateForm910Json(data, { now = new Date() } = {}) {
  const payload = {
    _meta: {
      generatedBy: 'Esep',
      generatedAt: now.toISOString(),
      note: 'Конверт не сверён с официальной схемой ИСНА',
    },
    formCode: FORM_CODE,
    version: FORM_VERSION,
    revision: FORM_REVISION,
    period: {
      year: data.year,
      halfYear: data.halfYear,
    },
    taxpayer: {
      iin: data.iin,
      name: data.fullName,
    },
    declarationType: declarationTypeField(data),
    currencyCode: 'KZT',
    fields: Object.entries(fieldValues(data)).reduce((acc, [k, v]) => {
      acc[k] = Number(v.toFixed(2));
      return acc;
    }, {}),
  };
  return JSON.stringify(payload, null, 2);
}

module.exports = {
  FORM_CODE,
  FORM_VERSION,
  FORM_REVISION,
  calculateForm910,
  generateForm910Xml,
  generateForm910Json,
};
