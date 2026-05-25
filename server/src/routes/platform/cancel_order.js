/**
 * Platform Service #5: Аннулирование чека / Отмена курьерского заказа.
 *
 * Логика двухслойная (т.к. фактический метод отмены в Webkassa API
 * пока не подтверждён документацией):
 *
 *   1) Если заказ загружен в Webkassa, но ещё НЕ фискализирован курьером
 *      (status = 'awaiting_courier_fiscalization'):
 *        → soft cancel: помечаем у нас как 'cancelled'
 *        → курьер в мобилке Webkassa не увидит или увидит отменённый
 *        → фискализации не будет
 *
 *   2) Если заказ УЖЕ фискализирован (status = 'issued'):
 *        → soft cancel недопустим — это полноценный чек в КГД
 *        → нужен официальный возврат через возвратный чек (Webkassa API)
 *        → пока возвращаем 409 с указанием связаться через support
 *
 *   3) Если заказ ещё не загружен в Webkassa (status = 'queued' или
 *      'pending_ofd_contract'):
 *        → просто помечаем 'cancelled', никаких внешних вызовов
 *
 * Endpoint:
 *   POST /api/platform/cancel-order
 *   Body: { order_id: "...", reason: "..." }
 */

const express = require('express');
const router = express.Router();
const { requirePlatformKey } = require('../../middleware/platform_api_key');
const db = require('../../db');

router.post('/', requirePlatformKey('cancel_receipt'), async (req, res) => {
  const { order_id, reason } = req.body || {};

  if (!order_id) {
    return res.status(400).json({
      error: 'Поле "order_id" обязательно',
      example: { order_id: 'ORD-2026-05-18-123', reason: 'Курьер не доставил' },
    });
  }

  try {
    // Находим чек в нашей БД, но только этого клиента (защита от подмены)
    const { rows } = await db.query(
      `SELECT id, status, iin, amount, ofd_receipt_id
         FROM platform_receipts
        WHERE external_id = $1
          AND api_key_id = $2
        LIMIT 1`,
      [order_id, req.platformClient.id],
    );

    if (rows.length === 0) {
      return res.status(404).json({
        error: 'Заказ не найден',
        order_id,
      });
    }

    const receipt = rows[0];

    // ── Случай 1: уже фискализирован — отмена недопустима через soft cancel ─
    if (receipt.status === 'issued') {
      return res.status(409).json({
        error: 'CANNOT_SOFT_CANCEL',
        message:
          'Заказ уже фискализирован, это полноценный чек в КГД. ' +
          'Для отмены требуется оформить возвратный чек. ' +
          'Свяжитесь с менеджером Esep для оформления возврата.',
        order_id,
        ticket_number: receipt.ofd_receipt_id,
        current_status: receipt.status,
      });
    }

    // ── Случай 2: уже отменён ранее — идемпотентность ───────────────────────
    if (receipt.status === 'cancelled') {
      return res.json({
        ok: true,
        order_id,
        status: 'cancelled',
        message: 'Заказ уже был отменён ранее.',
        idempotent: true,
      });
    }

    // ── Случай 3: можно отменить (queued / awaiting_courier_fiscalization /
    //   pending_ofd_contract / upload_failed) — soft cancel ──────────────────
    await db.query(
      `UPDATE platform_receipts
         SET status = 'cancelled',
             cancelled_at = NOW(),
             cancel_reason = $2
       WHERE id = $1`,
      [receipt.id, reason || 'Отменено клиентом через API'],
    );

    // Откат учёта в лимите 300 МРП — помечаем cancelled_at, не удаляем
    // (getMonthlyIncome исключает строки с cancelled_at IS NOT NULL).
    if (receipt.iin && receipt.amount) {
      await db.query(
        `UPDATE platform_self_employed_income
            SET cancelled_at = NOW(),
                note = COALESCE(note, '') || ' [CANCELLED ' || NOW()::TEXT || ']'
          WHERE external_id = $1
            AND api_key_id = $2
            AND cancelled_at IS NULL`,
        [order_id, req.platformClient.id],
      );
    }

    return res.json({
      ok: true,
      order_id,
      previous_status: receipt.status,
      new_status: 'cancelled',
      cancel_method: 'soft_cancel',
      message: receipt.status === 'awaiting_courier_fiscalization'
        ? 'Заказ помечен как отменённый. Если курьер ещё не успел фискализировать — фискализации не будет.'
        : 'Заказ помечен как отменённый.',
    });
  } catch (err) {
    console.error('[cancel-order] error:', err.message);
    return res.status(500).json({ error: 'Ошибка отмены: ' + err.message });
  }
});

module.exports = router;
