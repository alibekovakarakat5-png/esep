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

// Дефолтные фичи для любого enterprise-юзера — пока не дифференцируем
// по конкретным клиентам (введём через 6 мес когда будут договоры).
const DEFAULT_ENTERPRISE_FEATURES = [
  'process_payment', 'taxpayer_info', 'iin_validate',
  'cancel_receipt', 'receipt_status', 'income_limit',
  'self_employed_registry', 'benefits',
];

// (зарезервировано для будущего endpoint'а POST /api/admin/users/:id/enable-platform)
async function _provisionApiKey(userId) {
  const crypto = require('crypto');
  const apiKey = 'pk_' + crypto.randomBytes(16).toString('base64url');
  const userInfo = await db.query(
    'SELECT name FROM users WHERE id = $1',
    [userId],
  );
  const inserted = await db.query(
    `INSERT INTO platform_api_keys
       (user_id, api_key, client_name, client_bin, tier, features,
        monthly_quota, is_active)
     VALUES ($1, $2, $3, NULL, 'enterprise', $4::jsonb, 10000, TRUE)
     RETURNING id, api_key, client_name, client_bin, features,
               monthly_quota, requests_this_month, requests_total,
               created_at, last_used_at`,
    [
      userId,
      apiKey,
      userInfo.rows[0]?.name || 'Enterprise клиент',
      JSON.stringify(DEFAULT_ENTERPRISE_FEATURES),
    ],
  );
  console.log('[platform/my-account] auto-provisioned for', userId);
  return inserted.rows[0];
}

router.get('/', authMiddleware, async (req, res) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Не авторизован' });
    }

    const isAdminImpersonation = !!req.isImpersonated;

    // Разработчик/основатель видит кабинет напрямую по своему email —
    // без enterprise-тарифа и без impersonation ("разраб видит всё").
    const DEV_EMAILS = (process.env.PLATFORM_DEV_EMAILS ||
      'alibekovakarakat5@gmail.com,aksharayev@gmail.com')
      .split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
    const isDev = !!(req.user?.email && DEV_EMAILS.includes(req.user.email.toLowerCase()));

    // Доступ требует tier=enterprise (биллинг).
    // Исключения: super-admin через impersonation ИЛИ разработчик по email.
    if (req.user?.tier !== 'enterprise' && !isAdminImpersonation && !isDev) {
      return res.status(403).json({
        error: 'NO_PLATFORM_ACCESS',
        has_platform_access: false,
        message: 'Platform API доступен только на тарифе Enterprise. ' +
                 'Свяжитесь с менеджером Esep для подключения.',
      });
    }

    // Ищем существующий API-ключ
    const existing = await db.query(
      `SELECT id, api_key, client_name, client_bin, features,
              monthly_quota, requests_this_month, requests_total,
              created_at, last_used_at
         FROM platform_api_keys
        WHERE user_id = $1 AND is_active = TRUE
        LIMIT 1`,
      [userId],
    );

    let row = existing.rows[0];

    if (!row) {
      // Нет ключа в БД.
      if (isDev) {
        // Разработчик: авто-выдаём РЕАЛЬНЫЙ enterprise-ключ, чтобы можно
        // было сразу тестировать платформенные вызовы (fiscalize и т.д.).
        console.log('[platform/my-account] dev auto-provision for', userId);
        row = await _provisionApiKey(userId);
      } else if (isAdminImpersonation) {
        // Super-admin через impersonation: виртуальный просмотр без записи в БД.
        console.log('[platform/my-account] admin bypass for user', userId, '(no api key row)');
        row = {
          id: null,
          api_key: 'pk_admin_view_no_key',
          client_name: '[admin view] ' + (req.user.email || 'Enterprise клиент'),
          client_bin: null,
          features: DEFAULT_ENTERPRISE_FEATURES,
          monthly_quota: 0,
          requests_this_month: 0,
          requests_total: 0,
          created_at: null,
          last_used_at: null,
        };
      } else {
        // Обычный enterprise-юзер без ключа: 403, менеджер Esep оформит.
        return res.status(403).json({
          error: 'NO_PLATFORM_ACCESS',
          has_platform_access: false,
          message: 'Аккаунт ещё не настроен для Platform API. ' +
                   'Менеджер Esep оформит ваш ключ в течение рабочего дня.',
        });
      }
    }

    // Считаем сколько чеков обработано (если api_key_id есть)
    let stats = { issued: 0, awaiting: 0, cancelled: 0, pending: 0, failed: 0, total_amount: 0 };
    if (row.id) {
      try {
        const r = await db.query(
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
        stats = r.rows[0] || stats;
      } catch (e) {
        console.error('[platform/my-account] stats query failed:', e.message);
      }
    }

    return res.json({
      has_platform_access: true,
      api_key: row.api_key,
      client_name: row.client_name,
      client_bin: row.client_bin,
      tier: 'enterprise',
      features: row.features || DEFAULT_ENTERPRISE_FEATURES,
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
