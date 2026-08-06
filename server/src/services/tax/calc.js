// Чистые функции налоговых расчётов НК РК 2026 (Закон 214-VIII).
// Механический порт lib/core/constants/kz_tax_constants.dart — формулы
// перенесены один в один, эталонные пары вход→выход в __fixtures__/calc_cases.json.
//
// Правила модуля: ставки приходят ПЕРВЫМ АРГУМЕНТОМ (см. rates.js),
// никакого доступа к БД/Express/сети — файл собирается esbuild'ом
// в статический бандл лендинга (tax-core.js).
//
// Формы возврата повторяют Dart-классы TaxCalculation910 / SocialPayments /
// FullTaxSummary / TooTaxCalculation, чтобы порт оставался механическим.

function clamp(x, lo, hi) {
  return Math.min(hi, Math.max(lo, x));
}

// ── Упрощёнка (форма 910): 4% = 100% ИПН, СН = 0% для СНР ────────────────────
// Маслихат может менять ставку в пределах ±50% (2–6%): regionalAdjustment —
// прямая дельта ставки, regionalDiscount — скидка; ненулевой adjustment
// имеет приоритет (как в Dart).
function calculate910(rates, income, { regionalAdjustment = 0, regionalDiscount = 0 } = {}) {
  const adjustment = regionalAdjustment !== 0 ? regionalAdjustment : -regionalDiscount;
  const totalRate = rates.ipn_rate_910 + rates.sn_rate_910;
  const effectiveRate = clamp(totalRate + adjustment, 0, 1);
  const ipn = income * effectiveRate;
  return {
    income,
    ipn,
    sn: 0, // СН = 0% для СНР с 2026
    totalTax: ipn,
    effectiveIpnRate: effectiveRate,
    effectiveSnRate: 0,
    effectiveRate: income > 0 ? ipn / income : 0,
  };
}

// ── Ежемесячные соцплатежи ИП «за себя» ──────────────────────────────────────
// ОПВ 10% от 1 МЗП, ОПВР 3.5% (не платят родившиеся до 1975), СО 5%,
// ВОСМС 5% от 1.4 МЗП.
function calculateMonthlySocial(rates, { bornBefore1975 = false } = {}) {
  const opv = rates.mzp * rates.opv_rate;
  const opvr = bornBefore1975 ? 0 : rates.mzp * rates.opvr_rate;
  const so = rates.mzp * rates.so_rate;
  const vosms = rates.mzp * rates.vosms_base_mult * rates.vosms_rate_self;
  return { opv, opvr, so, vosms, total: opv + opvr + so + vosms };
}

// ── Полный расчёт 910: налог за полугодие + соцплатежи за 6 месяцев ──────────
function calculateFull910(
  rates,
  halfYearIncome,
  { regionalAdjustment = 0, regionalDiscount = 0, bornBefore1975 = false } = {},
) {
  const tax = calculate910(rates, halfYearIncome, { regionalAdjustment, regionalDiscount });
  const monthlySocial = calculateMonthlySocial(rates, { bornBefore1975 });
  const socialHalfYear = monthlySocial.total * 6;
  const grandTotal = tax.totalTax + socialHalfYear;
  return {
    tax,
    monthlySocial,
    socialHalfYear,
    grandTotal,
    effectiveRate: halfYearIncome > 0 ? grandTotal / halfYearIncome : 0,
  };
}

// ── ОУР: прогрессивный ИПН (годовой доход) ───────────────────────────────────
// 10% до порога 8500 МРП, 15% свыше.
function calculateProgressiveIpn(rates, annualIncome) {
  if (annualIncome <= 0) return 0;
  const threshold = rates.mrp * rates.general_ipn_threshold_mrp;
  if (annualIncome <= threshold) return annualIncome * rates.general_ipn_rate;
  return threshold * rates.general_ipn_rate + (annualIncome - threshold) * rates.general_ipn_rate_high;
}

// ── Самозанятые: 4% от дохода ────────────────────────────────────────────────
function calculateSelfEmployed(rates, income) {
  return income * rates.self_emp_rate;
}

// ── ТОО: КПН + НДС + СН за сотрудников ───────────────────────────────────────
// dividendTax НЕ входит в totalTax: ИПН с дивидендов возникает только при
// фактическом распределении прибыли (ставка 5% на проверке у бухгалтера).
function calculateTooTax(
  rates,
  {
    income,
    expenses,
    isVatPayer = false,
    employeeCount = 0,
    monthlyPayroll = 0,
    kpnRateOverride = null, // ставка по виду деятельности (ст. 357); null → база
  } = {},
) {
  const taxableIncome = Math.max(0, income - expenses);
  const kpn = taxableIncome * (kpnRateOverride ?? rates.kpn_rate);

  const vatReceived = isVatPayer ? income * rates.vat_rate : 0;
  const vatPaid = isVatPayer ? expenses * rates.vat_rate : 0;
  const vatPayable = Math.max(0, vatReceived - vatPaid);

  // СН за сотрудников: 6% от ФОТ (новый НК РК 2026, без вычета СО)
  const socialTax = Math.max(0, monthlyPayroll * rates.social_tax_too_rate) * employeeCount;

  const netProfit = taxableIncome - kpn;
  const dividendTax = netProfit * rates.dividend_tax_rate;
  const totalTax = kpn + vatPayable;

  return {
    income,
    expenses,
    taxableIncome,
    kpn,
    vatReceived,
    vatPaid,
    vatPayable,
    socialTax,
    netProfit,
    dividendTax,
    totalTax,
    effectiveRate: income > 0 ? totalTax / income : 0,
  };
}

// ── Лимиты и пороги ──────────────────────────────────────────────────────────

// Самозанятые: 300 МРП/мес (ст. 715 НК), 3600 МРП/год.
function selfEmployedLimit(rates) {
  return {
    monthlyTenge: rates.mrp * rates.self_emp_month_limit,
    yearlyTenge: rates.mrp * rates.self_emp_year_limit,
  };
}

// Порог постановки на учёт по НДС: 10 000 МРП/год.
function vatThreshold(rates) {
  return { thresholdTenge: rates.mrp * rates.vat_threshold_mrp, rate: rates.vat_rate };
}

// Лимит упрощёнки: 600 000 МРП/год (старый полугодовой лимит отменён).
function simplified910YearLimit(rates) {
  return rates.mrp * rates['910_year_mrp'];
}

function simplified910HalfYearLimit(rates) {
  return simplified910YearLimit(rates) / 2;
}

// СН для ИП на ОУР: 2 МРП/мес за себя + 1 МРП/мес за работника.
function ipMonthlySocialTax(rates, { employees = 0 } = {}) {
  return rates.mrp * (rates.ip_sn_mrp_self + rates.ip_sn_mrp_per_employee * employees);
}

module.exports = {
  calculate910,
  calculateMonthlySocial,
  calculateFull910,
  calculateProgressiveIpn,
  calculateSelfEmployed,
  calculateTooTax,
  selfEmployedLimit,
  vatThreshold,
  simplified910YearLimit,
  simplified910HalfYearLimit,
  ipMonthlySocialTax,
};
