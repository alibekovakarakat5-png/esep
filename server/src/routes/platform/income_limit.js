/**
 * Platform Service #7: Проверка лимита дохода самозанятого (300 МРП в месяц)
 *
 * По НК РК 2026 (Закон 214-VIII):
 *   - Самозанятый платит 4% от дохода
 *   - Лимит дохода — 300 МРП в КАЛЕНДАРНЫЙ МЕСЯЦ
 *   - Превышение → теряет режим, обязан перейти в ИП
 *
 * МРП на 2026 = 4 325 ₸ (kz_tax_constants.dart)
 * Месячный лимит = 300 × 4 325 = 1 297 500 ₸
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

// Константы НК РК 2026 — синхронизировано с lib/core/constants/kz_tax_constants.dart
const MRP_2026 = 4325;
const MONTHLY_LIMIT_MRP = 300;
const MONTHLY_LIMIT_TENGE = MRP_2026 * MONTHLY_LIMIT_MRP; // 1 297 500 ₸

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
      const usedTenge = await getMonthlyIncome(iin);
      const remainingTenge = Math.max(0, MONTHLY_LIMIT_TENGE - usedTenge);
      const percentUsed = Math.min(100, (usedTenge / MONTHLY_LIMIT_TENGE) * 100);

      return res.json({
        iin,
        month: new Date().toISOString().slice(0, 7), // YYYY-MM
        limit: {
          mrp: MONTHLY_LIMIT_MRP,
          tenge: MONTHLY_LIMIT_TENGE,
          mrp_2026: MRP_2026,
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
      const usedTenge = await getMonthlyIncome(iin);
      const afterPayment = usedTenge + proposed;
      const canPay = afterPayment <= MONTHLY_LIMIT_TENGE;

      return res.json({
        iin,
        can_pay: canPay,
        proposed_amount: proposed,
        already_used: usedTenge,
        would_be_total: afterPayment,
        limit: MONTHLY_LIMIT_TENGE,
        ...(canPay ? {} : {
          excess: afterPayment - MONTHLY_LIMIT_TENGE,
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
      const used = await getMonthlyIncome(iin, paymentDate);
      const after = used + amountNum;

      if (after > MONTHLY_LIMIT_TENGE) {
        return res.status(409).json({
          error: 'LIMIT_EXCEEDED',
          message: 'Превышен месячный лимит 300 МРП для самозанятого',
          already_used: used,
          attempted: amountNum,
          would_be_total: after,
          limit: MONTHLY_LIMIT_TENGE,
          excess: after - MONTHLY_LIMIT_TENGE,
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
        remaining: MONTHLY_LIMIT_TENGE - after,
        created_at: record.created_at,
      });
    } catch (err) {
      console.error('[income-limit/record] DB error:', err.message);
      return res.status(500).json({ error: 'Ошибка БД' });
    }
  },
);

module.exports = router;
