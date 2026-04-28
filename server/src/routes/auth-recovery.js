// ── Auth recovery routes ────────────────────────────────────────────────────
//
// Привязка Telegram (только из авторизованной сессии):
//   POST   /api/auth/telegram/bind-link        → создать одноразовую ссылку t.me
//   GET    /api/auth/telegram/status           → проверить статус привязки
//   DELETE /api/auth/telegram/unbind           → отвязать
//
// Восстановление пароля (без авторизации, доставка только в привязанный TG):
//   POST   /api/auth/forgot-password           → { email } — шлёт код в Telegram
//   POST   /api/auth/verify-reset-code         → { email, code } → reset_token
//   POST   /api/auth/reset-password            → { reset_token, new_password }

const router = require('express').Router();
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const db     = require('../db');

const tg = require('../bot/telegram');

const BIND_TOKEN_TTL_MIN  = 10;
const RESET_CODE_TTL_MIN  = 15;
const RESET_SESSION_TTL_MIN = 10;
const RESET_MAX_ATTEMPTS  = 5;
const RESET_REQUEST_RATE_LIMIT_MIN = 60;
const RESET_REQUESTS_PER_HOUR = 3;

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

// ╔════════════════════════════════════════════════════════════════════╗
// ║ Сброс пароля                                                       ║
// ╚════════════════════════════════════════════════════════════════════╝

// ── POST /api/auth/forgot-password ───────────────────────────────────────────
// Принимает email. Если есть юзер с привязанным Telegram — шлём код в TG.
// В ответе НЕ выдаём наличие или отсутствие пользователя (защита от перебора).

router.post('/forgot-password', async (req, res) => {
  const email = String(req.body?.email || '').trim().toLowerCase();
  if (!email || !email.includes('@')) {
    return res.status(400).json({ error: 'Укажите email' });
  }

  // Стандартный ответ: всегда успех, чтобы не утекали учётки
  const stdResponse = {
    ok: true,
    message: 'Если этот email зарегистрирован и к нему привязан Telegram — мы отправили туда 6-значный код.',
    delivery: 'telegram',
    expires_in_seconds: RESET_CODE_TTL_MIN * 60,
  };

  try {
    const r = await db.query(
      `SELECT id, telegram_chat_id, telegram_username, name
         FROM users WHERE LOWER(email) = $1`,
      [email]
    );
    if (r.rows.length === 0) {
      // Не палим что юзера нет
      return res.json(stdResponse);
    }
    const user = r.rows[0];
    if (!user.telegram_chat_id) {
      // Не палим что Telegram не привязан
      // (но в логах оставим заметку — поможет support'у разобраться)
      await logSecurity(user.id, 'pwd_reset_no_channel', { email }, req);
      return res.json(stdResponse);
    }

    // Rate limit: не больше 3 запросов в час с одного email
    const rl = await db.query(
      `SELECT COUNT(*) AS n FROM password_reset_code
        WHERE user_id = $1
          AND created_at > NOW() - INTERVAL '${RESET_REQUEST_RATE_LIMIT_MIN} minutes'`,
      [user.id]
    );
    if (parseInt(rl.rows[0].n, 10) >= RESET_REQUESTS_PER_HOUR) {
      await logSecurity(user.id, 'pwd_reset_rate_limited', {}, req);
      return res.json(stdResponse); // тоже стандартный ответ
    }

    const code = newSixDigitCode();
    const codeHash = hashCode(code);

    // Инвалидируем старые активные коды
    await db.query(
      `UPDATE password_reset_code
          SET used_at = NOW()
        WHERE user_id = $1 AND used_at IS NULL`,
      [user.id]
    );
    await db.query(
      `INSERT INTO password_reset_code
         (user_id, code_hash, expires_at, delivery, delivered_to)
       VALUES ($1, $2, NOW() + INTERVAL '${RESET_CODE_TTL_MIN} minutes',
               'telegram', $3)`,
      [user.id, codeHash, user.telegram_chat_id]
    );
    await logSecurity(user.id, 'pwd_reset_requested', {}, req);

    // Доставка
    await tg.send(user.telegram_chat_id,
      `🔐 <b>Восстановление пароля Esep</b>\n\n` +
      `Кто-то запросил сброс пароля для аккаунта:\n` +
      `📧 ${escapeHtml(email)}\n\n` +
      `Ваш одноразовый код:\n` +
      `<code>${code}</code>\n\n` +
      `Код действует ${RESET_CODE_TTL_MIN} минут.\n\n` +
      `<b>Если это не вы — игнорируйте это сообщение и срочно смените пароль другим способом, ` +
      `либо отвяжите Telegram через настройки.</b>`
    );

    res.json(stdResponse);
  } catch (err) {
    console.error('[auth-recovery] forgot-password failed:', err);
    // Тоже не палим
    res.json(stdResponse);
  }
});

// ── POST /api/auth/verify-reset-code ─────────────────────────────────────────

router.post('/verify-reset-code', async (req, res) => {
  const email = String(req.body?.email || '').trim().toLowerCase();
  const code  = String(req.body?.code  || '').trim();
  if (!email || !code) return res.status(400).json({ error: 'email и code обязательны' });
  if (!/^\d{6}$/.test(code)) {
    return res.status(400).json({ error: 'Код должен быть 6-значным' });
  }

  try {
    const ur = await db.query(
      `SELECT id FROM users WHERE LOWER(email) = $1`, [email]
    );
    if (ur.rows.length === 0) {
      return res.status(400).json({ error: 'Неверный код или email' });
    }
    const userId = ur.rows[0].id;

    const cr = await db.query(
      `SELECT id, code_hash, attempts, expires_at, used_at
         FROM password_reset_code
        WHERE user_id = $1
          AND used_at IS NULL
          AND expires_at > NOW()
        ORDER BY created_at DESC LIMIT 1`,
      [userId]
    );
    if (cr.rows.length === 0) {
      return res.status(400).json({ error: 'Код истёк или не запрашивался. Запросите новый.' });
    }
    const row = cr.rows[0];

    if (row.attempts >= RESET_MAX_ATTEMPTS) {
      await db.query(
        `UPDATE password_reset_code SET used_at = NOW() WHERE id = $1`,
        [row.id]
      );
      await logSecurity(userId, 'pwd_reset_too_many_attempts', {}, req);
      return res.status(429).json({ error: 'Превышено число попыток. Запросите новый код.' });
    }

    // Инкрементируем попытку и проверяем
    await db.query(
      `UPDATE password_reset_code SET attempts = attempts + 1 WHERE id = $1`,
      [row.id]
    );

    if (hashCode(code) !== row.code_hash) {
      const left = Math.max(0, RESET_MAX_ATTEMPTS - row.attempts - 1);
      return res.status(400).json({
        error: `Неверный код. Осталось попыток: ${left}.`,
      });
    }

    // Помечаем код использованным и выдаём reset_session
    await db.query(
      `UPDATE password_reset_code SET used_at = NOW() WHERE id = $1`,
      [row.id]
    );

    const sessionToken = newToken(32);
    await db.query(
      `INSERT INTO password_reset_session (token, user_id, expires_at)
       VALUES ($1, $2, NOW() + INTERVAL '${RESET_SESSION_TTL_MIN} minutes')`,
      [sessionToken, userId]
    );

    res.json({
      ok: true,
      reset_token: sessionToken,
      expires_in_seconds: RESET_SESSION_TTL_MIN * 60,
    });
  } catch (err) {
    console.error('[auth-recovery] verify-reset-code failed:', err);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

// ── POST /api/auth/reset-password ────────────────────────────────────────────

router.post('/reset-password', async (req, res) => {
  const token = String(req.body?.reset_token || '').trim();
  const newPassword = String(req.body?.new_password || '');
  if (!token || !newPassword) {
    return res.status(400).json({ error: 'reset_token и new_password обязательны' });
  }
  if (newPassword.length < 8) {
    return res.status(400).json({ error: 'Пароль должен быть не короче 8 символов' });
  }

  try {
    const r = await db.query(
      `SELECT user_id, expires_at, used_at
         FROM password_reset_session
        WHERE token = $1`,
      [token]
    );
    if (r.rows.length === 0) {
      return res.status(400).json({ error: 'Сессия сброса не найдена' });
    }
    const row = r.rows[0];
    if (row.used_at) return res.status(400).json({ error: 'Сессия уже использована' });
    if (new Date(row.expires_at) < new Date()) {
      return res.status(400).json({ error: 'Сессия истекла. Запросите код заново.' });
    }

    const passwordHash = await bcrypt.hash(newPassword, 10);
    await db.query(
      `UPDATE users SET password_hash = $1 WHERE id = $2`,
      [passwordHash, row.user_id]
    );
    await db.query(
      `UPDATE password_reset_session SET used_at = NOW() WHERE token = $1`,
      [token]
    );

    await logSecurity(row.user_id, 'pwd_reset_completed', {}, req);

    // Уведомим в Telegram, чтобы пользователь видел в случае компрометации
    const u = await db.query(
      `SELECT telegram_chat_id, email FROM users WHERE id = $1`,
      [row.user_id]
    );
    const chat = u.rows[0]?.telegram_chat_id;
    if (chat) {
      tg.send(chat,
        `✅ <b>Пароль успешно изменён</b>\n\n` +
        `Аккаунт: ${escapeHtml(u.rows[0].email)}\n\n` +
        `Если это не вы — срочно зайдите на сайт и снова смените пароль, ` +
        `затем отвяжите Telegram до выяснения.`
      ).catch(() => {});
    }

    res.json({ ok: true });
  } catch (err) {
    console.error('[auth-recovery] reset-password failed:', err);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

function escapeHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

module.exports = router;
