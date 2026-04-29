// ── Auth recovery routes ────────────────────────────────────────────────────
//
// Привязка Telegram (только из авторизованной сессии):
//   POST   /api/auth/telegram/bind-link  → создать одноразовую ссылку t.me
//   GET    /api/auth/telegram/status     → проверить статус привязки
//   DELETE /api/auth/telegram/unbind     → отвязать
//
// Восстановление пароля теперь идёт через TG-бота напрямую (см. handleReset
// в src/bot/telegram.js — команда /reset email@example.com).

const router = require('express').Router();
const crypto = require('crypto');
const db     = require('../db');

const tg = require('../bot/telegram');

const BIND_TOKEN_TTL_MIN = 10;

// ── Helpers ──────────────────────────────────────────────────────────────────

function newToken(bytes = 32) {
  return crypto.randomBytes(bytes).toString('base64url');
}

function newSixDigitCode() {
  // Криптостойкий 6-значный код, без ведущих нулей не подсунем
  const n = crypto.randomInt(0, 1000000);
  return String(n).padStart(6, '0');
}

function hashCode(code) {
  return crypto.createHash('sha256').update(code).digest('hex');
}

async function logSecurity(userId, event, meta = {}, req = null) {
  try {
    await db.query(
      `INSERT INTO auth_security_log (user_id, event, meta, ip, user_agent)
       VALUES ($1, $2, $3::jsonb, $4, $5)`,
      [
        userId || null,
        event,
        JSON.stringify(meta),
        req?.ip || null,
        req?.headers?.['user-agent']?.slice(0, 200) || null,
      ]
    );
  } catch (err) {
    console.error('[auth-recovery] log failed:', err.message);
  }
}

function requireUser(req, res) {
  const id = req.user?.id;
  if (!id) { res.status(401).json({ error: 'Требуется авторизация' }); return null; }
  return id;
}

const BOT_USERNAME = process.env.TELEGRAM_BOT_USERNAME || 'esep_bot';

// ╔════════════════════════════════════════════════════════════════════╗
// ║ Telegram-привязка                                                  ║
// ╚════════════════════════════════════════════════════════════════════╝

// ── POST /api/auth/telegram/bind-link ────────────────────────────────────────
// Создаёт одноразовый токен привязки и возвращает t.me-ссылку.
// Старые неиспользованные токены этого пользователя инвалидируются.

router.post('/telegram/bind-link', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  try {
    // Инвалидируем старые активные токены пользователя
    await db.query(
      `UPDATE telegram_bind_token
          SET expires_at = NOW()
        WHERE user_id = $1 AND consumed_at IS NULL AND expires_at > NOW()`,
      [userId]
    );

    const token = newToken(24);
    await db.query(
      `INSERT INTO telegram_bind_token (token, user_id, expires_at)
       VALUES ($1, $2, NOW() + INTERVAL '${BIND_TOKEN_TTL_MIN} minutes')`,
      [token, userId]
    );

    await logSecurity(userId, 'tg_bind_requested', {}, req);

    res.json({
      bot_username: BOT_USERNAME,
      deeplink: `https://t.me/${BOT_USERNAME}?start=bind_${token}`,
      expires_in_seconds: BIND_TOKEN_TTL_MIN * 60,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── GET /api/auth/telegram/status ────────────────────────────────────────────

router.get('/telegram/status', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  try {
    const r = await db.query(
      `SELECT telegram_chat_id, telegram_username, telegram_linked_at
         FROM users WHERE id = $1`,
      [userId]
    );
    const row = r.rows[0] || {};
    res.json({
      linked: !!row.telegram_chat_id,
      username: row.telegram_username || null,
      linked_at: row.telegram_linked_at || null,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── DELETE /api/auth/telegram/unbind ─────────────────────────────────────────

router.delete('/telegram/unbind', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  try {
    const r = await db.query(
      `UPDATE users
          SET telegram_chat_id = NULL,
              telegram_username = NULL,
              telegram_linked_at = NULL
        WHERE id = $1
       RETURNING telegram_chat_id`,
      [userId]
    );
    // Уведомим пользователя в Telegram если ещё помним chat_id
    // (на момент UPDATE он стал NULL, но мы достанем из bot_users)
    const bu = await db.query(
      `SELECT chat_id FROM bot_users WHERE linked_user_id = $1`,
      [userId]
    );
    for (const r2 of bu.rows) {
      tg.send(r2.chat_id,
        '🔌 Telegram отвязан от вашего аккаунта Esep.\n' +
        'Восстановление пароля через Telegram больше недоступно. Если это были не вы — срочно смените пароль через "Забыли пароль".'
      ).catch(() => {});
    }
    await db.query(`UPDATE bot_users SET linked_user_id = NULL WHERE linked_user_id = $1`, [userId]);

    await logSecurity(userId, 'tg_unbind', {}, req);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});


module.exports = router;
