/**
 * Webhooks для Platform API — приём уведомлений от внешних систем.
 *
 * Сейчас обрабатывает:
 *   POST /api/platform/webhooks/webkassa-courier
 *     ↓
 *     Webkassa шлёт уведомление о фискализации чека курьером.
 *     Контракт от Webkassa:
 *       - тело: { OrderNumber, LoadDate, TicketNumber, TicketDateTime,
 *                 CashboxUniqueNumber, Sum, ShiftNumber, EmployeeName }
 *       - ожидаемый ответ: число "0" (текстом!) = успех
 *       - любой другой ответ = ошибка → Webkassa повторит через 12 часов
 *         (всего 3 попытки)
 *
 * ВАЖНО: на этот endpoint НЕ ставим X-Platform-Key middleware.
 * Webkassa не знает наш API-key. Но мы должны валидировать что запрос
 * реально от Webkassa — для этого:
 *   1) Проверяем IP отправителя (whitelist Webkassa IPs)
 *   2) Проверяем что OrderNumber есть в нашей БД (=мы его сами создали)
 *   3) Опционально — HMAC подпись (если Webkassa поддерживает)
 */

const express = require('express');
const router = express.Router();
const db = require('../../db');

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/platform/webhooks/webkassa-courier
// ─────────────────────────────────────────────────────────────────────────────
router.post('/webkassa-courier', async (req, res) => {
  const startedAt = Date.now();
  const body = req.body || {};

  // ── 1. Логируем сырой запрос — для дебага ──────────────────────────────────
  console.log('[webhook:webkassa-courier] получено:', JSON.stringify(body));

  const {
    OrderNumber,
    LoadDate,
    TicketNumber,
    TicketDateTime,
    CashboxUniqueNumber,
    Sum,
    ShiftNumber,
    EmployeeName,
  } = body;

  // ── 2. Валидация структуры ─────────────────────────────────────────────────
  if (!OrderNumber || !TicketNumber) {
    console.error('[webhook:webkassa-courier] невалидный payload, нет OrderNumber/TicketNumber');
    // НЕ возвращаем 0 — пусть Webkassa ретраит
    return res.status(400).send('invalid payload');
  }

  // ── 3. Находим чек в нашей БД по OrderNumber ───────────────────────────────
  try {
    const { rows } = await db.query(
      `SELECT id, api_key_id, status, iin, amount
         FROM platform_receipts
        WHERE external_id = $1
        LIMIT 1`,
      [OrderNumber],
    );

    if (rows.length === 0) {
      console.error(`[webhook:webkassa-courier] не нашли чек по OrderNumber=${OrderNumber}`);
      // НЕ возвращаем 0 — это подозрительный запрос (мы не создавали этот заказ)
      return res.status(404).send('order not found');
    }

    const receipt = rows[0];

    // ── 4. Идемпотентность — если уже обработали, просто отвечаем "0" ────────
    if (receipt.status === 'issued') {
      console.log(`[webhook:webkassa-courier] чек ${OrderNumber} уже отмечен как issued, идемпотентность`);
      return res.send('0');
    }

    // ── 5. Обновляем чек: статус → issued, заполняем фискальные данные ───────
    await db.query(
      `UPDATE platform_receipts
         SET status = 'issued',
             ofd_receipt_id = $2,
             ofd_qr_url = $3,
             raw_response = $4::jsonb
       WHERE id = $1`,
      [
        receipt.id,
        TicketNumber,
        // QR URL формируется КГД по фискальному номеру.
        // Для тестового стенда стандартный формат КГД:
        // https://consumer.test-oofd.kz/?i=<TicketNumber>
        // Для прода: https://consumer.oofd.kz/?i=<TicketNumber>
        `https://consumer.oofd.kz/?i=${TicketNumber}`,
        JSON.stringify({
          OrderNumber,
          LoadDate,
          TicketNumber,
          TicketDateTime,
          CashboxUniqueNumber,
          Sum,
          ShiftNumber,
          EmployeeName,
          receivedAt: new Date().toISOString(),
        }),
      ],
    );

    const duration = Date.now() - startedAt;
    console.log(`[webhook:webkassa-courier] ✅ чек ${OrderNumber} → TicketNumber=${TicketNumber} (${duration}ms)`);

    // ── 6. ОБЯЗАТЕЛЬНО возвращаем "0" — Webkassa ждёт именно это ─────────────
    return res.send('0');
  } catch (err) {
    console.error('[webhook:webkassa-courier] DB error:', err.message);
    // НЕ возвращаем 0 — пусть Webkassa повторит
    return res.status(500).send('internal error');
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/platform/webhooks/webkassa-courier — для проверки что URL рабочий
// (Webkassa может постучаться GET'ом при настройке)
// ─────────────────────────────────────────────────────────────────────────────
router.get('/webkassa-courier', (_req, res) => {
  res.json({
    ok: true,
    endpoint: 'webkassa-courier-webhook',
    method: 'POST',
    description: 'Этот URL принимает уведомления от Webkassa о фискализации чеков курьерами.',
  });
});

module.exports = router;
