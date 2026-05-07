/**
 * Feedback router — отзывы / баги / идеи от бета-тестировщиков.
 *
 * Зачем: даём избранным пользователям (бухгалтер-консультант, фокус-группа)
 * быструю кнопку "Сообщить о баге" в каждом экране Flutter-приложения.
 * Любой их отзыв падает (а) в БД для истории и (б) сразу в Telegram админу,
 * чтобы Каракат могла отреагировать в течение часа.
 *
 * Доступ:
 *   - Только авторизованный пользователь.
 *   - Только если у пользователя `is_beta_tester = true`.
 *   - Иначе 403 — обычные клиенты не должны видеть кнопку и тем более
 *     посылать сюда что-то.
 *
 * Endpoints:
 *   POST /api/feedback     — создать запись
 *   GET  /api/feedback/mine — прошлые отзывы текущего пользователя (мини-список)
 */
const router = require('express').Router();
const db = require('../db');
const auth = require('../middleware/auth');
const tg = require('../bot/telegram');

const SEVERITY = ['low', 'normal', 'high', 'critical'];

// Сколько разрешаем максимум — чтобы не положить сервер
const MAX_MESSAGE_LEN = 4000;
const MAX_SCREEN_LEN = 80;
const MAX_VERSION_LEN = 32;

router.post('/', auth, async (req, res) => {
  try {
    // Проверяем что пользователь — бета-тестер.
    const { rows: userRows } = await db.query(
      'SELECT email, name, is_beta_tester FROM users WHERE id = $1',
      [req.userId],
    );
    if (!userRows.length) {
      return res.status(404).json({ error: 'User not found' });
    }
    const user = userRows[0];
    if (!user.is_beta_tester) {
      return res.status(403).json({
        error: 'Эта функция доступна только бета-тестировщикам',
      });
    }

    const message = String(req.body?.message || '').trim();
    if (!message) {
      return res.status(400).json({ error: 'Опишите проблему или идею' });
    }
    if (message.length > MAX_MESSAGE_LEN) {
      return res.status(400).json({
        error: `Сообщение слишком длинное (макс ${MAX_MESSAGE_LEN} символов)`,
      });
    }

    const screen = String(req.body?.screen || 'unknown').slice(0, MAX_SCREEN_LEN);
    const appVersion = String(req.body?.appVersion || '').slice(0, MAX_VERSION_LEN) || null;
    let severity = String(req.body?.severity || 'normal');
    if (!SEVERITY.includes(severity)) severity = 'normal';

    // device_info: что-нибудь полезное от Flutter (платформа, версия ОС и т.д.)
    let deviceInfo = req.body?.deviceInfo;
    if (deviceInfo && typeof deviceInfo !== 'object') deviceInfo = null;

    const { rows } = await db.query(
      `INSERT INTO feedback (user_id, screen, severity, message, device_info, app_version)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, created_at`,
      [req.userId, screen, severity, message, deviceInfo || null, appVersion],
    );

    // ── Уведомление в Telegram админу ────────────────────────────────────────
    // Формат специально читабельный: эмодзи серьёзности + экран + ссылка на
    // запись в админке.
    const sevIcon = {
      low: '🔵',
      normal: '🟢',
      high: '🟠',
      critical: '🔴',
    }[severity] || '🟢';

    const adminUrl = process.env.ADMIN_URL || 'https://api.esepkz.com/api/admin';
    const txt = [
      `${sevIcon} <b>Бета-фидбек</b>`,
      ``,
      `<b>От:</b> ${escape(user.name || '—')} (${escape(user.email)})`,
      `<b>Экран:</b> <code>${escape(screen)}</code>`,
      appVersion ? `<b>Версия:</b> <code>${escape(appVersion)}</code>` : null,
      ``,
      escape(message),
      ``,
      `📋 <a href="${adminUrl}#feedback">Открыть в админке</a> · #${rows[0].id}`,
    ].filter(Boolean).join('\n');

    // Не блокируем ответ клиенту, если Telegram упал
    tg.sendAdmin(txt).catch((e) => console.error('feedback → telegram failed:', e?.message));

    res.status(201).json({ id: rows[0].id, createdAt: rows[0].created_at });
  } catch (err) {
    console.error('POST /feedback error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

router.get('/mine', auth, async (req, res) => {
  try {
    const { rows } = await db.query(
      `SELECT id, screen, severity, message, status, created_at
       FROM feedback
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT 50`,
      [req.userId],
    );
    res.json(rows);
  } catch (err) {
    console.error('GET /feedback/mine error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// Простейший HTML-escape для подстановки в Telegram parse_mode=HTML
function escape(s) {
  if (s == null) return '';
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

module.exports = router;
