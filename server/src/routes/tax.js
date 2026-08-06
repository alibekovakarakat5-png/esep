// POST /api/tax/calculate — публичный налоговый калькулятор (волна 4 спеки
// docs/superpowers/specs/2026-08-06-tax-core-node-design.md).
// POST /api/tax/form910   — генерация формы 910.00 (XML СОНО / JSON ИСНА).
//
// Без авторизации: «посчитать налог» — не приватная операция, тем же расчётом
// пользуется лендинг. Ограничение частоты — как у остальных публичных
// эндпоинтов (in-memory на IP, ср. routes/lead.js).
//
// Вся математика — services/tax; здесь только валидация входа и форма ответа.
// ratesVersion в каждом ответе обязателен: первый вопрос при расхождении сумм —
// «по какой версии ставок считали».

const express = require('express');
const router = express.Router();
const db = require('../db');
const {
  loadRates,
  calculateFull910,
  calculateMonthlySocial,
  calculateProgressiveIpn,
  calculateSelfEmployed,
  calculateTooTax,
  selfEmployedLimit,
  vatThreshold,
  simplified910YearLimit,
  simplified910HalfYearLimit,
  calculateForm910,
  generateForm910Xml,
  generateForm910Json,
} = require('../services/tax');

class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// ── Валидация ────────────────────────────────────────────────────────────────

function reqNum(v, name, { min = 0 } = {}) {
  if (v == null || v === '') throw new ApiError(400, `Поле "${name}" обязательно`);
  const n = Number(v);
  if (!Number.isFinite(n)) throw new ApiError(400, `Поле "${name}" должно быть числом`);
  if (n < min) throw new ApiError(400, `Поле "${name}" должно быть ≥ ${min}`);
  return n;
}

function optNum(v, name, fallback = 0) {
  if (v == null || v === '') return fallback;
  const n = Number(v);
  if (!Number.isFinite(n)) throw new ApiError(400, `Поле "${name}" должно быть числом`);
  return n;
}

function socialBlock(s) {
  return { opv: s.opv, opvr: s.opvr, so: s.so, vosms: s.vosms, monthlyTotal: s.total };
}

// ── Билдер ответа /calculate (чистый, покрыт test/tax_api.test.js) ───────────

function buildCalculateResponse(rates, version, body = {}) {
  const options = body.options || {};
  const bornBefore1975 = Boolean(options.bornBefore1975);

  switch (body.regime) {
    case '910': {
      const income = reqNum(body.halfYearIncome, 'halfYearIncome');
      const full = calculateFull910(rates, income, {
        regionalAdjustment: optNum(options.regionalAdjustment, 'options.regionalAdjustment'),
        regionalDiscount: optNum(options.regionalDiscount, 'options.regionalDiscount'),
        bornBefore1975,
      });
      const t = full.tax;
      const halfYearTenge = simplified910HalfYearLimit(rates);
      return {
        regime: '910',
        income,
        tax: {
          ipn: t.ipn,
          sn: t.sn,
          total: t.totalTax,
          effectiveRate: t.effectiveIpnRate + t.effectiveSnRate,
        },
        social: { ...socialBlock(full.monthlySocial), halfYearTotal: full.socialHalfYear },
        grandTotal: full.grandTotal,
        effectiveRate: full.effectiveRate,
        limit: {
          yearTenge: simplified910YearLimit(rates),
          halfYearTenge,
          exceeded: income > halfYearTenge,
        },
        ratesVersion: version,
      };
    }

    case 'self_employed': {
      const income = reqNum(body.annualIncome, 'annualIncome');
      const s = calculateMonthlySocial(rates, { bornBefore1975 });
      const taxTotal = calculateSelfEmployed(rates, income);
      const lim = selfEmployedLimit(rates);
      return {
        regime: 'self_employed',
        income,
        tax: { rate: rates.self_emp_rate, total: taxTotal },
        social: { ...socialBlock(s), yearTotal: s.total * 12 },
        grandTotal: taxTotal + s.total * 12,
        limit: { ...lim, exceeded: income > lim.yearlyTenge },
        ratesVersion: version,
      };
    }

    case 'general': {
      const income = reqNum(body.annualIncome, 'annualIncome');
      const s = calculateMonthlySocial(rates, { bornBefore1975 });
      const ipn = calculateProgressiveIpn(rates, income);
      return {
        regime: 'general',
        income,
        tax: {
          ipn,
          rateBase: rates.general_ipn_rate,
          rateHigh: rates.general_ipn_rate_high,
          threshold: rates.mrp * rates.general_ipn_threshold_mrp,
        },
        social: { ...socialBlock(s), yearTotal: s.total * 12 },
        grandTotal: ipn + s.total * 12,
        vat: vatThreshold(rates),
        ratesVersion: version,
      };
    }

    case 'too': {
      const income = reqNum(body.income, 'income');
      const expenses = reqNum(body.expenses, 'expenses');
      const employeeCount = Math.trunc(optNum(body.employeeCount, 'employeeCount'));
      if (employeeCount < 0) throw new ApiError(400, 'Поле "employeeCount" должно быть ≥ 0');
      const monthlyPayroll = optNum(body.monthlyPayroll, 'monthlyPayroll');
      if (monthlyPayroll < 0) throw new ApiError(400, 'Поле "monthlyPayroll" должно быть ≥ 0');
      const kpnRateOverride =
        body.kpnRateOverride == null ? null : reqNum(body.kpnRateOverride, 'kpnRateOverride');
      const calculation = calculateTooTax(rates, {
        income,
        expenses,
        isVatPayer: Boolean(body.isVatPayer),
        employeeCount,
        monthlyPayroll,
        kpnRateOverride,
      });
      return {
        regime: 'too',
        calculation,
        grandTotal: calculation.totalTax,
        ratesVersion: version,
      };
    }

    default:
      throw new ApiError(400, 'Поле "regime" обязательно: 910 | self_employed | general | too');
  }
}

// ── Билдер ответа /form910 ───────────────────────────────────────────────────

function buildForm910Response(rates, version, body = {}) {
  const { format } = body;
  if (format !== 'xml' && format !== 'json') {
    throw new ApiError(400, 'Поле "format" обязательно: xml | json');
  }
  const iin = typeof body.iin === 'string' ? body.iin.trim() : '';
  if (!iin) throw new ApiError(400, 'Поле "iin" обязательно');
  const fullName = typeof body.fullName === 'string' ? body.fullName.trim() : '';
  if (!fullName) throw new ApiError(400, 'Поле "fullName" обязательно');
  if (body.halfYear !== 1 && body.halfYear !== 2) {
    throw new ApiError(400, 'Поле "halfYear" обязательно: 1 | 2');
  }
  const year = Number(body.year);
  if (!Number.isInteger(year) || year < 2000 || year > 2100) {
    throw new ApiError(400, 'Поле "year" обязательно (2000–2100)');
  }

  const rawTx = Array.isArray(body.transactions) ? body.transactions : [];
  const transactions = rawTx.map((t, i) => {
    const amount = Number(t && t.amount);
    if (!Number.isFinite(amount)) {
      throw new ApiError(400, `transactions[${i}].amount должен быть числом`);
    }
    return { date: t.date, amount, isIncome: Boolean(t.isIncome), source: t.source };
  });

  const employeeCount = Math.trunc(optNum(body.employeeCount, 'employeeCount'));
  const totalPayroll = optNum(body.totalPayroll, 'totalPayroll');

  let data;
  try {
    data = calculateForm910(rates, {
      iin,
      fullName,
      halfYear: body.halfYear,
      year,
      declarationType: body.declarationType,
      transactions,
      employeeCount,
      totalPayroll,
      bornBefore1975: Boolean(body.bornBefore1975),
    });
  } catch (err) {
    throw new ApiError(400, `Транзакции: ${err.message}`);
  }

  const document =
    format === 'xml' ? generateForm910Xml(data) : generateForm910Json(data);

  return {
    ratesVersion: version,
    format,
    filename: `form_910_${year}_H${body.halfYear}.${format}`,
    data,
    document,
  };
}

// ── Rate-limit: 30 POST/мин на IP (как у остальных публичных) ────────────────

const hits = new Map();
function rateLimited(ip) {
  const now = Date.now();
  const rec = hits.get(ip) || { count: 0, resetAt: now + 60_000 };
  if (now > rec.resetAt) {
    rec.count = 0;
    rec.resetAt = now + 60_000;
  }
  rec.count++;
  hits.set(ip, rec);
  return rec.count > 30;
}

function handle(builder) {
  return async (req, res) => {
    const ip = req.ip || req.headers['x-forwarded-for'] || 'unknown';
    if (rateLimited(ip)) {
      return res.status(429).json({ error: 'Слишком много запросов. Подождите минуту.' });
    }
    try {
      const { rates, version } = await loadRates(db);
      return res.json(builder(rates, version, req.body || {}));
    } catch (err) {
      if (err instanceof ApiError) return res.status(err.status).json({ error: err.message });
      console.error('[api/tax]', err);
      return res.status(500).json({ error: 'Внутренняя ошибка сервера' });
    }
  };
}

router.post('/calculate', handle(buildCalculateResponse));
router.post('/form910', handle(buildForm910Response));

module.exports = { router, buildCalculateResponse, buildForm910Response, ApiError };
