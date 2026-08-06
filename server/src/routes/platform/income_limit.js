/**
 * Platform Service #7: Проверка лимита дохода самозанятого (300 МРП в месяц)
 *
 * По НК РК 2026 (Закон 214-VIII):
 *   - Самозанятый платит 4% от дохода
 *   - Лимит дохода — 300 МРП в КАЛЕНДАРНЫЙ МЕСЯЦ
 *   - Превышение → теряет режим, обязан перейти в ИП
 *
 * Лимит считается из ставок tax_config (БД) через services/tax —
 * при дефолтах НК-2026: 300 МРП × 4 325 ₸ = 1 297 500 ₸/мес
 *
 * Endpoints:
 *   GET  /api/platform/income-limit/check?iin=...&proposed_amount=...
 *        → "можно ли начислить эту сумму, не превысив лимит?"
 *
 *   POST /api/platform/income-limit/record
 *        Body: { iin, amount, external_id?, payment_method?, note?, date? }
 *        → записывает фактическую выплату
 *
 *   GET  /api/platform/income-limit/status/:iin
 *        → текущее состояние месячного лимита у этого ИИН
 */

const express = require('express');
const router = express.Router();
const { requirePlatformKey } = require('../../middleware/platform_api_key');
const { validateIinChecksum } = require('../../services/iin_algorithm');
const {
  getMonthlyIncome,
  recordIncome,
} = require('../../services/platform_db');
const db = require('../../db');
const { loadRates, selfEmployedLimit } = require('../../services/tax');

// Лимит самозанятого — из ставок tax_config (БД) через services/tax.
// Хардкода МРП здесь больше нет: смена МРП/лимита в админке сразу
// отражается в API. При недоступной таблице loadRates отдаёт дефолты НК-2026.
async function monthlyLimit() {
  const { rates } = await loadRates(db);
  return {
    mrp: rates.mrp,
    limitMrp: rates.self_emp_month_limit,
    limitTenge: selfEmployedLimit(rates).monthlyTenge,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/platform/income-limit/status/:iin
// ─────────────────────────────────────────────────────────────────────────────
router.get(
  '/status/:iin',
  requirePlatformKey('income_limit'),
  async (req, res) => {
    const { iin } = req.params;

    const iinCheck = validateIinChecksum(iin);
    if (!iinCheck.valid) {
      return res.status(400).json({
        error: 'Неверный ИИН',
        reason: iinCheck.reason,
      });
    }

    try {
      const { mrp, limitMrp, limitTenge } = await monthlyLimit();
      const usedTenge = await getMonthlyIncome(iin);
      const remainingTenge = Math.max(0, limitTenge - usedTenge);
      const percentUsed = Math.min(100, (usedTenge / limitTenge) * 100);

      return res.json({
        iin,
        month: new Date().toISOString().slice(0, 7), // YYYY-MM
        limit: {
          mrp: limitMrp,
          tenge: limitTenge,
          mrp_2026: mrp,
        },
        used_tenge: usedTenge,
        remaining_tenge: remainingTenge,
        percent_used: parseFloat(percentUsed.toFixed(2)),
        status: percentUsed >= 100 ? 'exceeded'
              : percentUsed >= 80  ? 'warning'
              : 'ok',
        legal_basis: 'НК РК 2026, Закон 214-VIII от 18.07.2025',
      });
    } catch (err) {
      console.error('[income-limit/status] DB error:', err.message);
      return res.status(500).json({ error: 'Ошибка БД' });
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/platform/income-limit/check?iin=...&proposed_amount=...
// «Можно ли начислить эту сумму, не превысив лимит?»
// ─────────────────────────────────────────────────────────────────────────────
router.get(
  '/check',
  requirePlatformKey('income_limit'),
  async (req, res) => {
    const iin = req.query.iin;
    const proposed = parseFloat(req.query.proposed_amount);

    if (!iin) {
      return res.status(400).json({ error: 'Параметр "iin" обязателен' });
    }
    if (!Number.isFinite(proposed) || proposed <= 0) {
      return res.status(400).json({
        error: 'Параметр "proposed_amount" обязателен и > 0',
      });
    }

    const iinCheck = validateIinChecksum(iin);
    if (!iinCheck.valid) {
      return res.status(400).json({ error: 'Неверный ИИН', reason: iinCheck.reason });
    }

    try {
      const { limitTenge } = await monthlyLimit();
      const usedTenge = await getMonthlyIncome(iin);
      const afterPayment = usedTenge + proposed;
      const canPay = afterPayment <= limitTenge;

      return res.json({
        iin,
        can_pay: canPay,
        proposed_amount: proposed,
        already_used: usedTenge,
        would_be_total: afterPayment,
        limit: limitTenge,
        ...(canPay ? {} : {
          excess: afterPayment - limitTenge,
          recommendation: 'Самозанятый превысит лимит. Рекомендуем не оформлять выплату или предложить ему перейти в ИП.',
        }),
      });
    } catch (err) {
      console.error('[income-limit/check] DB error:', err.message);
      return res.status(500).json({ error: 'Ошибка БД' });
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/platform/income-limit/record
// «Записать фактическую выплату»
// ─────────────────────────────────────────────────────────────────────────────
router.post(
  '/record',
  requirePlatformKey('income_limit'),
  async (req, res) => {
    const {
      iin,
      amount,
      external_id,
      payment_method,
      note,
      date,
    } = req.body || {};

    if (!iin || !amount) {
      return res.status(400).json({
        error: 'Поля "iin" и "amount" обязательны',
        example: {
          iin: '850101300123',
          amount: 50000,
          external_id: 'order_12345',
          payment_method: 'card',
        },
      });
    }

    const iinCheck = validateIinChecksum(iin);
    if (!iinCheck.valid) {
      return res.status(400).json({ error: 'Неверный ИИН', reason: iinCheck.reason });
    }

    const amountNum = parseFloat(amount);
    if (!Number.isFinite(amountNum) || amountNum <= 0) {
      return res.status(400).json({ error: '"amount" должен быть числом > 0' });
    }

    try {
      // Дата по умолчанию = сейчас
      const paymentDate = date ? new Date(date) : new Date();

      // Проверка лимита перед записью
      const { limitMrp, limitTenge } = await monthlyLimit();
      const used = await getMonthlyIncome(iin, paymentDate);
      const after = used + amountNum;

      if (after > limitTenge) {
        return res.status(409).json({
          error: 'LIMIT_EXCEEDED',
          message: `Превышен месячный лимит ${limitMrp} МРП для самозанятого`,
          already_used: used,
          attempted: amountNum,
          would_be_total: after,
          limit: limitTenge,
          excess: after - limitTenge,
        });
      }

      const record = await recordIncome({
        apiKeyId: req.platformClient.id,
        iin,
        amount: amountNum,
        externalId: external_id,
        paymentMethod: payment_method,
        note,
        date: paymentDate,
      });

      return res.status(201).json({
        recorded: true,
        id: record.id,
        new_monthly_total: after,
        remaining: limitTenge - after,
        created_at: record.created_at,
      });
    } catch (err) {
      console.error('[income-limit/record] DB error:', err.message);
      return res.status(500).json({ error: 'Ошибка БД' });
    }
  },
);

module.exports = router;
