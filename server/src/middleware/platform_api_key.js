/**
 * Middleware для Platform API.
 *
 * Аутентификация enterprise-клиентов (курьерская служба, маркетплейсы)
 * через API-ключ в заголовке `X-Platform-Key`.
 *
 * Ключи хранятся в таблице platform_api_keys (см. миграцию в index.js).
 * Поле `features` — JSON со списком разрешённых сервисов:
 *   ["iin_validate", "taxpayer_info", "income_limit",
 *    "fiscalize", "cancel_receipt", "receipt_status",
 *    "self_employed_registry", "benefits"]
 *
 * Каждый запрос:
 *   1) Проверяет валидность ключа
 *   2) Проверяет, что запрашиваемая фича разрешена для этого ключа
 *   3) Логирует обращение (для биллинга и debugging)
 *   4) Прикрепляет req.platformClient = { id, name, tier, features, ... }
 */

const db = require('../db');

/**
 * @param {string} requiredFeature - имя фичи, которую запрашивает endpoint
 * @returns Express middleware
 */
function requirePlatformKey(requiredFeature) {
  return async (req, res, next) => {
    const apiKey = req.headers['x-platform-key'] || req.query.apiKey;

    if (!apiKey) {
      return res.status(401).json({
        error: 'API-ключ обязателен',
        hint: 'Передайте заголовок X-Platform-Key: <ваш ключ>',
      });
    }

    try {
      const { rows } = await db.query(
        `SELECT id, client_name, tier, features, monthly_quota,
                requests_this_month, is_active
           FROM platform_api_keys
          WHERE api_key = $1
          LIMIT 1`,
        [apiKey],
      );

      if (rows.length === 0) {
        return res.status(403).json({ error: 'Неверный API-ключ' });
      }

      const client = rows[0];

      if (!client.is_active) {
        return res.status(403).json({ error: 'API-ключ деактивирован' });
      }

      // ── Проверка фичи ──────────────────────────────────────────────────────
      const features = Array.isArray(client.features) ? client.features : [];
      if (requiredFeature && !features.includes(requiredFeature)) {
        return res.status(403).json({
          error: `Фича "${requiredFeature}" не входит в ваш тариф`,
          your_features: features,
          contact: 'Для подключения свяжитесь с менеджером',
        });
      }

      // ── Проверка месячного лимита ──────────────────────────────────────────
      if (client.monthly_quota > 0 && client.requests_this_month >= client.monthly_quota) {
        return res.status(429).json({
          error: 'Превышен месячный лимит запросов',
          quota: client.monthly_quota,
          used: client.requests_this_month,
        });
      }

      // ── Инкремент счётчика (асинхронно, не блокируем ответ) ────────────────
      db.query(
        `UPDATE platform_api_keys
            SET requests_this_month = requests_this_month + 1,
                last_used_at = NOW()
          WHERE id = $1`,
        [client.id],
      ).catch((err) => {
        console.error('[platform_api_key] counter update failed:', err.message);
      });

      // ── Прикрепляем клиента к запросу ──────────────────────────────────────
      req.platformClient = {
        id: client.id,
        name: client.client_name,
        tier: client.tier,
        features,
      };

      return next();
    } catch (err) {
      console.error('[platform_api_key] DB error:', err.message);
      return res.status(500).json({ error: 'Ошибка аутентификации' });
    }
  };
}

module.exports = { requirePlatformKey };
