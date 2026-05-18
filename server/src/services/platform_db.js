/**
 * Миграции для Platform API (enterprise-клиенты типа курьерской службы).
 *
 * Таблицы:
 *   1) platform_api_keys           — API-ключи и feature flags клиентов
 *   2) platform_self_employed_income — кумулятивный доход самозанятых для лимита 300 МРП
 *   3) platform_receipts           — лог фискальных чеков (через Webkassa или мок)
 *   4) platform_audit_log          — все вызовы API для аудита и биллинга
 *
 * Запуск: вызывается из server/src/index.js → migratePlatform()
 */

const db = require('../db');

async function migratePlatform() {
  await db.query(`
    -- ════════════════════════════════════════════════════════════════════════
    -- 1) API-ключи enterprise клиентов
    -- ════════════════════════════════════════════════════════════════════════
    CREATE TABLE IF NOT EXISTS platform_api_keys (
      id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id               UUID        REFERENCES users(id) ON DELETE SET NULL,  -- владелец-пользователь Esep
      api_key               TEXT        UNIQUE NOT NULL,
      client_name           TEXT        NOT NULL,
      client_bin            TEXT,
      tier                  TEXT        NOT NULL DEFAULT 'enterprise',
      features              JSONB       NOT NULL DEFAULT '[]',
      monthly_quota         INT         NOT NULL DEFAULT 0,
      requests_this_month   INT         NOT NULL DEFAULT 0,
      requests_total        BIGINT      NOT NULL DEFAULT 0,
      monthly_reset_at      DATE        NOT NULL DEFAULT (DATE_TRUNC('month', NOW()) + INTERVAL '1 month')::DATE,
      is_active             BOOLEAN     NOT NULL DEFAULT TRUE,
      contact_email         TEXT,
      contact_phone         TEXT,
      notes                 TEXT,
      last_used_at          TIMESTAMPTZ,
      created_at            TIMESTAMPTZ DEFAULT NOW()
    );
    -- Миграция для существующих БД (если колонки нет)
    ALTER TABLE platform_api_keys ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE SET NULL;
    CREATE INDEX IF NOT EXISTS idx_platform_keys_active ON platform_api_keys(is_active);
    CREATE INDEX IF NOT EXISTS idx_platform_keys_user ON platform_api_keys(user_id);

    -- ════════════════════════════════════════════════════════════════════════
    -- 2) Учёт дохода самозанятых для проверки лимита 300 МРП в месяц
    -- ════════════════════════════════════════════════════════════════════════
    CREATE TABLE IF NOT EXISTS platform_self_employed_income (
      id              BIGSERIAL    PRIMARY KEY,
      api_key_id      UUID         NOT NULL REFERENCES platform_api_keys(id) ON DELETE CASCADE,
      iin             TEXT         NOT NULL,     -- ИИН самозанятого курьера
      month           DATE         NOT NULL,     -- первое число месяца (например 2026-05-01)
      amount          NUMERIC(15,2) NOT NULL,    -- сумма в тенге
      external_id     TEXT,                       -- ID операции у клиента
      payment_method  TEXT,                       -- 'card' | 'wallet' | 'cash' | etc.
      note            TEXT,
      created_at      TIMESTAMPTZ  DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS idx_self_emp_iin_month
      ON platform_self_employed_income(iin, month);
    CREATE INDEX IF NOT EXISTS idx_self_emp_apikey
      ON platform_self_employed_income(api_key_id);

    -- ════════════════════════════════════════════════════════════════════════
    -- 3) Лог фискальных чеков (для аннулирования и аудита)
    -- ════════════════════════════════════════════════════════════════════════
    CREATE TABLE IF NOT EXISTS platform_receipts (
      id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
      api_key_id      UUID         NOT NULL REFERENCES platform_api_keys(id) ON DELETE CASCADE,
      external_id     TEXT,                       -- ID заказа у клиента
      iin             TEXT,                       -- ИИН получателя (самозанятого)
      amount          NUMERIC(15,2) NOT NULL,
      ofd_provider    TEXT         NOT NULL DEFAULT 'webkassa',
      ofd_receipt_id  TEXT,                       -- ID чека у Webkassa
      ofd_qr_url      TEXT,                       -- ссылка на QR-код от КГД
      status          TEXT         NOT NULL DEFAULT 'pending',  -- pending | issued | cancelled | failed
      cancelled_at    TIMESTAMPTZ,
      cancel_reason   TEXT,
      raw_response    JSONB,                      -- сырой ответ от Webkassa для дебага
      created_at      TIMESTAMPTZ  DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS idx_receipts_apikey ON platform_receipts(api_key_id);
    CREATE INDEX IF NOT EXISTS idx_receipts_external ON platform_receipts(external_id);
    CREATE INDEX IF NOT EXISTS idx_receipts_status ON platform_receipts(status);

    -- ════════════════════════════════════════════════════════════════════════
    -- 4) Аудит всех запросов к Platform API
    -- ════════════════════════════════════════════════════════════════════════
    CREATE TABLE IF NOT EXISTS platform_audit_log (
      id           BIGSERIAL    PRIMARY KEY,
      api_key_id   UUID         REFERENCES platform_api_keys(id) ON DELETE SET NULL,
      feature      TEXT         NOT NULL,        -- 'iin_validate', 'fiscalize', etc.
      endpoint     TEXT,
      request_ip   TEXT,
      response_status INT,
      duration_ms  INT,
      created_at   TIMESTAMPTZ  DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS idx_audit_apikey_date
      ON platform_audit_log(api_key_id, created_at);
  `);

  console.log('✅  Platform API tables migrated');
}

/**
 * Сброс месячного счётчика requests_this_month для всех ключей,
 * у которых наступил новый месяц. Вызывается ежедневно cron'ом.
 */
async function resetMonthlyCounters() {
  const { rowCount } = await db.query(`
    UPDATE platform_api_keys
       SET requests_this_month = 0,
           monthly_reset_at = (DATE_TRUNC('month', NOW()) + INTERVAL '1 month')::DATE
     WHERE monthly_reset_at <= CURRENT_DATE
  `);
  if (rowCount > 0) {
    console.log(`[platform] reset monthly counters for ${rowCount} keys`);
  }
  return rowCount;
}

/**
 * Подсчёт дохода самозанятого за текущий месяц (для лимита 300 МРП).
 *
 * @param {string} iin
 * @param {Date} [date=now] - месяц определяется по этой дате
 * @returns {Promise<number>} - сумма в тенге
 */
async function getMonthlyIncome(iin, date = new Date()) {
  const month = new Date(date.getFullYear(), date.getMonth(), 1);
  const { rows } = await db.query(
    `SELECT COALESCE(SUM(amount), 0) AS total
       FROM platform_self_employed_income
      WHERE iin = $1
        AND month = $2`,
    [iin, month.toISOString().slice(0, 10)],
  );
  return parseFloat(rows[0].total) || 0;
}

/**
 * Запись новой выплаты самозанятому.
 */
async function recordIncome({ apiKeyId, iin, amount, externalId, paymentMethod, note, date = new Date() }) {
  const month = new Date(date.getFullYear(), date.getMonth(), 1);
  const { rows } = await db.query(
    `INSERT INTO platform_self_employed_income
       (api_key_id, iin, month, amount, external_id, payment_method, note)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING id, created_at`,
    [apiKeyId, iin, month.toISOString().slice(0, 10), amount, externalId, paymentMethod, note],
  );
  return rows[0];
}

module.exports = {
  migratePlatform,
  resetMonthlyCounters,
  getMonthlyIncome,
  recordIncome,
};
