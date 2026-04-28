// ── ESF reconciliation + Personal account monitor schema ────────────────────
// Запускается при старте сервера. Идемпотентно.

const db = require('../db');

async function migrateEsfAndAccount() {
  await db.query(`
    -- ── ЭСФ: реестр входящих и исходящих счёт-фактур ─────────────────────────
    CREATE TABLE IF NOT EXISTS esf_invoice (
      id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id         UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      registration_no TEXT,                  -- регистрационный № ЭСФ (если есть)
      invoice_no      TEXT         NOT NULL, -- номер счёта поставщика
      invoice_date    DATE         NOT NULL,
      turnover_date   DATE,
      direction       TEXT         NOT NULL,   -- 'INCOMING' | 'OUTGOING'
      status          TEXT         NOT NULL DEFAULT 'ISSUED',
        -- DRAFT | ISSUED | DELIVERED | ANNULLED | REVOKED
      seller_iin      TEXT         NOT NULL,
      seller_name     TEXT,
      buyer_iin       TEXT         NOT NULL,
      buyer_name      TEXT,
      amount_net      NUMERIC(18,2) NOT NULL DEFAULT 0,
      amount_vat      NUMERIC(18,2) NOT NULL DEFAULT 0,
      amount_total    NUMERIC(18,2) NOT NULL DEFAULT 0,
      vat_rate        NUMERIC(5,2),                      -- 16 / 12 / 0 / NULL=без НДС
      currency        TEXT         NOT NULL DEFAULT 'KZT',
      source          TEXT         NOT NULL,             -- 'xlsx_import' | 'xml_import' | 'isep'
      source_file     TEXT,                              -- имя файла-источника
      raw_row         JSONB,                             -- исходная строка (для отладки)
      imported_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
      UNIQUE (user_id, registration_no)
    );

    CREATE INDEX IF NOT EXISTS idx_esf_user_period
      ON esf_invoice(user_id, invoice_date, direction);
    CREATE INDEX IF NOT EXISTS idx_esf_seller
      ON esf_invoice(user_id, seller_iin, invoice_date);
    CREATE INDEX IF NOT EXISTS idx_esf_buyer
      ON esf_invoice(user_id, buyer_iin, invoice_date);

    -- ── Сессии сверки (одна сессия = один акт сверки за период) ──────────────
    CREATE TABLE IF NOT EXISTS esf_recon_session (
      id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      title           TEXT        NOT NULL DEFAULT '',
      period_from     DATE        NOT NULL,
      period_to       DATE        NOT NULL,
      registry_filename TEXT,                            -- имя XLSX реестра ЭСФ
      notice_filename   TEXT,                            -- имя XLSX извещения 300
      status          TEXT        NOT NULL DEFAULT 'draft',
        -- draft | matched | exported
      stats           JSONB       NOT NULL DEFAULT '{}'::jsonb,
        -- {matched, only_esf, only_notice, amount_diff, status_red}
      created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS idx_esf_session_user
      ON esf_recon_session(user_id, created_at DESC);

    -- ── Строки извещения по ф.300 (что в зачёт по НДС) ───────────────────────
    CREATE TABLE IF NOT EXISTS esf_notice_row (
      id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
      session_id      UUID        NOT NULL REFERENCES esf_recon_session(id) ON DELETE CASCADE,
      row_index       INT         NOT NULL,
      seller_iin      TEXT,
      seller_name     TEXT,
      invoice_no      TEXT,
      invoice_date    DATE,
      amount_net      NUMERIC(18,2),
      amount_vat      NUMERIC(18,2),
      amount_total    NUMERIC(18,2),
      vat_rate        NUMERIC(5,2),
      raw_row         JSONB,
      UNIQUE (session_id, row_index)
    );

    CREATE INDEX IF NOT EXISTS idx_notice_row_session ON esf_notice_row(session_id);
    CREATE INDEX IF NOT EXISTS idx_notice_row_seller  ON esf_notice_row(session_id, seller_iin);

    -- ── Результаты матчинга ──────────────────────────────────────────────────
    CREATE TABLE IF NOT EXISTS esf_recon_match (
      id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
      session_id      UUID        NOT NULL REFERENCES esf_recon_session(id) ON DELETE CASCADE,
      esf_id          UUID        REFERENCES esf_invoice(id) ON DELETE SET NULL,
      notice_row_id   UUID        REFERENCES esf_notice_row(id) ON DELETE SET NULL,
      match_type      TEXT        NOT NULL,
        -- 'matched' | 'amount_diff' | 'status_red' | 'only_esf' | 'only_notice'
      confidence      NUMERIC(3,2) NOT NULL DEFAULT 1.00,
      diff            JSONB       NOT NULL DEFAULT '{}'::jsonb
    );

    CREATE INDEX IF NOT EXISTS idx_match_session ON esf_recon_match(session_id);
    CREATE INDEX IF NOT EXISTS idx_match_type    ON esf_recon_match(session_id, match_type);

    -- ── Лицевой счёт: ожидаемые и фактические платежи ────────────────────────
    -- Решает боль "КПН не разнёсся" — пользователь фиксирует факт платежа,
    -- мы напоминаем проверить разноску через 5/14/30 дней.
    CREATE TABLE IF NOT EXISTS account_payment (
      id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id         UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      kbk             TEXT         NOT NULL,           -- 101101, 101110, 101111 и т.д.
      kbk_label       TEXT,                            -- "ИПН по ф.910" и т.п.
      tax_period      TEXT,                            -- '2026-H1', '2026-Q1'
      paid_amount     NUMERIC(18,2) NOT NULL,
      paid_at         DATE         NOT NULL,
      bank            TEXT,                            -- Kaspi / Halyk / Forte
      payment_doc     TEXT,                            -- № платёжки
      expected_period_kbk TEXT,                        -- куда должно разнестись
      actual_status   TEXT         NOT NULL DEFAULT 'pending_check',
        -- 'pending_check' | 'posted' | 'misposted' | 'missing'
      checked_at      TIMESTAMPTZ,
      mispost_kbk     TEXT,                            -- если ушло не туда
      note            TEXT,
      attachment_url  TEXT,                            -- скан платёжки/выписки
      created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
      updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS idx_account_user_status
      ON account_payment(user_id, actual_status);
    CREATE INDEX IF NOT EXISTS idx_account_user_paid_at
      ON account_payment(user_id, paid_at DESC);
  `);

  console.log('✅  ESF + account migrated');
}

module.exports = { migrateEsfAndAccount };
