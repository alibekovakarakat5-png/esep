// ── Auth recovery: Telegram-привязка + сброс пароля ─────────────────────────

const db = require('../db');

async function migrateAuthRecovery() {
  await db.query(`
    -- ── Привязка Telegram ───────────────────────────────────────────────────
    -- На стороне users.telegram_chat_id уже есть в bot_users.linked_user_id,
    -- но добавляем явное поле в users для скорости + отметку времени и username.

    ALTER TABLE users ADD COLUMN IF NOT EXISTS telegram_chat_id  TEXT;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS telegram_username TEXT;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS telegram_linked_at TIMESTAMPTZ;

    CREATE UNIQUE INDEX IF NOT EXISTS idx_users_telegram_chat_id
      ON users(telegram_chat_id) WHERE telegram_chat_id IS NOT NULL;

    -- ── Одноразовые токены привязки Telegram ────────────────────────────────
    -- Создаются на сайте в авторизованной сессии. Срок жизни 10 минут.
    -- При нажатии Start в боте — токен находится по payload, бот пишет
    -- юзеру "Привязать аккаунт {email}? Это вы?" с inline-кнопкой.
    -- При нажатии "Да" — токен помечается consumed, привязка завершается.

    CREATE TABLE IF NOT EXISTS telegram_bind_token (
      token         TEXT         PRIMARY KEY,
      user_id       UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
      expires_at    TIMESTAMPTZ  NOT NULL,
      consumed_at   TIMESTAMPTZ,
      consumed_chat_id TEXT,
      consumed_username TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_tg_bind_user
      ON telegram_bind_token(user_id);
    CREATE INDEX IF NOT EXISTS idx_tg_bind_expires
      ON telegram_bind_token(expires_at) WHERE consumed_at IS NULL;

    -- ── Коды восстановления пароля ──────────────────────────────────────────
    -- 6-значный код, валиден 15 минут, до 5 попыток ввода.
    -- Доставка только в привязанный Telegram (никаких email/SMS пока).
    -- Хранится hash, не сам код.

    CREATE TABLE IF NOT EXISTS password_reset_code (
      id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id       UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      code_hash     TEXT         NOT NULL,
      created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
      expires_at    TIMESTAMPTZ  NOT NULL,
      attempts      INT          NOT NULL DEFAULT 0,
      used_at       TIMESTAMPTZ,
      delivery      TEXT         NOT NULL DEFAULT 'telegram',
      delivered_to  TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_reset_user_active
      ON password_reset_code(user_id) WHERE used_at IS NULL;
    CREATE INDEX IF NOT EXISTS idx_reset_expires
      ON password_reset_code(expires_at) WHERE used_at IS NULL;

    -- ── Reset-токены (после успешной верификации кода) ──────────────────────
    -- Однострочный: верифицировали код → выдали токен → пользователь
    -- ставит новый пароль. Токен живёт 10 минут.

    CREATE TABLE IF NOT EXISTS password_reset_session (
      token         TEXT         PRIMARY KEY,
      user_id       UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
      expires_at    TIMESTAMPTZ  NOT NULL,
      used_at       TIMESTAMPTZ
    );

    CREATE INDEX IF NOT EXISTS idx_reset_session_user
      ON password_reset_session(user_id);

    -- ── Audit log безопасности (уведомления о ключевых действиях) ───────────

    CREATE TABLE IF NOT EXISTS auth_security_log (
      id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id       UUID         REFERENCES users(id) ON DELETE SET NULL,
      event         TEXT         NOT NULL,
        -- 'tg_bind_requested' | 'tg_bind_confirmed' | 'tg_bind_rejected'
        -- | 'tg_unbind' | 'pwd_reset_requested' | 'pwd_reset_completed'
        -- | 'pwd_reset_too_many_attempts'
      meta          JSONB        NOT NULL DEFAULT '{}'::jsonb,
      ip            TEXT,
      user_agent    TEXT,
      created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS idx_sec_log_user
      ON auth_security_log(user_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_sec_log_event
      ON auth_security_log(event, created_at DESC);
  `);
  console.log('✅  Auth recovery migrated');
}

module.exports = { migrateAuthRecovery };
