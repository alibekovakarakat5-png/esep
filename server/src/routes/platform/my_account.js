/**
 * /api/platform/my-account — самообслуживание enterprise-юзера.
 *
 * Используется когда курьерка/маркетплейс залогинены в Esep через JWT
 * (стандартный auth) и заходят в свой Platform Dashboard. Этот endpoint
 * возвращает их API-ключ, набор фич и статистику использования.
 *
 * Авторизация: стандартный authMiddleware (JWT) — НЕ X-Platform-Key.
 *
 * GET /api/platform/my-account
 * Возвращает:
 *   {
 *     has_platform_access: true,
 *     api_key: "demo_xxx",          // боевой API-ключ для X-Platform-Key
 *     client_name: "...",
 *     client_bin: "...",
 *     tier: "enterprise",
 *     features: ["iin_validate", "process_payment", ...],
 *     monthly_quota: 10000,
 *     requests_this_month: 142,
 *     requests_total: 5840,
 *     services_status: { ... }       // на какой сервис что фактически работает
 *   }
 *
 * Если пользователь НЕ enterprise — возвращает 403.
 */

const express = require('express');
const router = express.Router();
const db = require('../../db');
const authMiddleware = require('../../middleware/auth');

router.get('/', authMiddleware, async (req, res) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Не авторизован' });
    }

    // Получаем платформенный аккаунт юзера
    const { rows } = await db.query(
      `SELECT id, api_key, client_name, client_bin, tier, features,
              monthly_quota, requests_this_month, requests_total,
              is_active, created_at, last_used_at
         FROM platform_api_keys
        WHERE user_id = $1
          AND is_active = TRUE
        LIMIT 1`,
      [userId],
    );

    if (rows.length === 0) {
      return res.status(403).json({
        error: 'NO_PLATFORM_ACCESS',
        has_platform_access: false,
        message: 'У вашего аккаунта нет доступа к Platform API. Свяжитесь с менеджером Esep.',
      });
    }

    const row = rows[0];

    // Считаем сколько чеков обработано
    const { rows: [stats] } = await db.query(
      `SELECT
         COUNT(*) FILTER (WHERE status='issued')                      AS issued,
         COUNT(*) FILTER (WHERE status='awaiting_courier_fiscalization') AS awaiting,
         COUNT(*) FILTER (WHERE status='cancelled')                  AS cancelled,
         COUNT(*) FILTER (WHERE status='pending_ofd_contract')       AS pending,
         COUNT(*) FILTER (WHERE status='upload_failed')              AS failed,
         COALESCE(SUM(amount), 0)                                    AS total_amount
        FROM platform_receipts
       WHERE api_key_id = $1`,
      [row.id],
    );

    return res.json({
      has_platform_access: true,
      api_key: row.api_key,
      client_name: row.client_name,
      client_bin: row.client_bin,
      tier: row.tier,
      features: row.features || [],
      monthly_quota: row.monthly_quota,
      requests_this_month: row.requests_this_month,
      requests_total: row.requests_total,
      created_at: row.created_at,
      last_used_at: row.last_used_at,
      receipts: {
        issued: parseInt(stats.issued, 10) || 0,
        awaiting: parseInt(stats.awaiting, 10) || 0,
        cancelled: parseInt(stats.cancelled, 10) || 0,
        pending: parseInt(stats.pending, 10) || 0,
        failed: parseInt(stats.failed, 10) || 0,
        total_amount: parseFloat(stats.total_amount) || 0,
      },
      api_base_url: 'https://api.esepkz.com/api/platform',
    });
  } catch (err) {
    console.error('[platform/my-account] error:', err.message);
    return res.status(500).json({ error: 'Ошибка получения данных аккаунта' });
  }
});

module.exports = router;
