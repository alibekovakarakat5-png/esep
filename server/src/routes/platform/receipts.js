/**
 * Platform Service #6: Статус фискальных чеков.
 *
 * Курьерская служба после доставки хочет знать: пробил ли курьер чек,
 * какой фискальный номер, ссылка на QR от КГД. А также — общий список
 * всех своих чеков для сверки.
 *
 * Endpoints:
 *   GET /api/platform/receipts/:order_id   — статус одного чека
 *   GET /api/platform/receipts             — список чеков (с фильтрами)
 *
 * Авторизация: X-Platform-Key (фича receipt_status).
 * Клиент видит ТОЛЬКО свои чеки (фильтр по api_key_id).
 */

const express = require('express');
const router = express.Router();
const { requirePlatformKey } = require('../../middleware/platform_api_key');
const db = require('../../db');

// Человекочитаемые описания статусов
const STATUS_LABELS = {
  issued: 'Фискализирован — чек пробит курьером, зарегистрирован в КГД',
  awaiting_courier_fiscalization:
    'Ожидает фискализации — заказ загружен в Webkassa, курьер ещё не пробил чек',
  pending_ofd_contract:
    'В очереди — фискализация будет после подключения ОФД',
  upload_failed:
    'Ошибка загрузки в Webkassa — требуется повторная отправка',
  cancelled: 'Отменён',
};

function shapeReceipt(row) {
  const raw = row.raw_response || {};
  return {
    order_id: row.external_id,
    status: row.status,
    status_label: STATUS_LABELS[row.status] || row.status,
    is_fiscalized: row.status === 'issued',
    courier_iin: row.iin,
    amount: parseFloat(row.amount),
    fiscal: row.status === 'issued'
      ? {
          fiscal_number: row.ofd_receipt_id,
          qr_url: row.ofd_qr_url,
          ofd_provider: row.ofd_provider,
          fiscalized_at: raw.TicketDateTime || raw.receivedAt || null,
          employee_name: raw.EmployeeName || null,
          shift_number: raw.ShiftNumber || null,
        }
      : null,
    cancelled_at: row.cancelled_at,
    cancel_reason: row.cancel_reason,
    created_at: row.created_at,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/platform/receipts/:order_id — один чек
// ─────────────────────────────────────────────────────────────────────────────
router.get(
  '/:order_id',
  requirePlatformKey('receipt_status'),
  async (req, res) => {
    const { order_id } = req.params;

    try {
      const { rows } = await db.query(
        `SELECT external_id, status, iin, amount, ofd_provider,
                ofd_receipt_id, ofd_qr_url, cancelled_at, cancel_reason,
                raw_response, created_at
           FROM platform_receipts
          WHERE external_id = $1
            AND api_key_id = $2
          LIMIT 1`,
        [order_id, req.platformClient.id],
      );

      if (rows.length === 0) {
        return res.status(404).json({
          error: 'NOT_FOUND',
          message: `Чек с order_id "${order_id}" не найден`,
          hint: 'Проверьте order_id или убедитесь что заказ был создан через /process-payment',
        });
      }

      return res.json(shapeReceipt(rows[0]));
    } catch (err) {
      console.error('[receipts/:order_id] error:', err.message);
      return res.status(500).json({ error: 'Ошибка получения чека' });
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/platform/receipts — список чеков
// Query: ?status=issued&iin=...&limit=50&offset=0
// ─────────────────────────────────────────────────────────────────────────────
router.get(
  '/',
  requirePlatformKey('receipt_status'),
  async (req, res) => {
    const status = req.query.status;
    const iin = req.query.iin;
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, 200);
    const offset = parseInt(req.query.offset, 10) || 0;

    try {
      // Собираем WHERE по фильтрам
      const conditions = ['api_key_id = $1'];
      const params = [req.platformClient.id];
      let p = 2;

      if (status) {
        conditions.push(`status = $${p++}`);
        params.push(status);
      }
      if (iin) {
        conditions.push(`iin = $${p++}`);
        params.push(iin);
      }

      const where = conditions.join(' AND ');

      // Всего записей (для пагинации)
      const { rows: [count] } = await db.query(
        `SELECT COUNT(*)::int AS total FROM platform_receipts WHERE ${where}`,
        params,
      );

      // Сводка по статусам
      const { rows: summary } = await db.query(
        `SELECT status, COUNT(*)::int AS n, COALESCE(SUM(amount),0) AS sum
           FROM platform_receipts
          WHERE api_key_id = $1
          GROUP BY status`,
        [req.platformClient.id],
      );

      // Сами записи
      const { rows } = await db.query(
        `SELECT external_id, status, iin, amount, ofd_provider,
                ofd_receipt_id, ofd_qr_url, cancelled_at, cancel_reason,
                raw_response, created_at
           FROM platform_receipts
          WHERE ${where}
          ORDER BY created_at DESC
          LIMIT $${p++} OFFSET $${p++}`,
        [...params, limit, offset],
      );

      return res.json({
        total: count.total,
        limit,
        offset,
        summary: summary.reduce((acc, s) => {
          acc[s.status] = { count: s.n, amount: parseFloat(s.sum) };
          return acc;
        }, {}),
        receipts: rows.map(shapeReceipt),
      });
    } catch (err) {
      console.error('[receipts list] error:', err.message);
      return res.status(500).json({ error: 'Ошибка получения списка чеков' });
    }
  },
);

module.exports = router;
