/**
 * Telegram Bot — Esep
 *
 * Пользователям: умный помощник по налогам ИП Казахстана
 * Администратору: уведомления о регистрациях, налогах, статьях
 *
 * Переменные среды:
 *   TELEGRAM_BOT_TOKEN      — токен от @BotFather
 *   TELEGRAM_ADMIN_CHAT_ID  — chat_id разработчика
 */

const https     = require('https');
const db        = require('../db');
const marketing = require('./marketing');

const TOKEN      = process.env.TELEGRAM_BOT_TOKEN;
const ADMIN_ID   = process.env.TELEGRAM_ADMIN_CHAT_ID;
const CHANNEL_ID = process.env.TELEGRAM_CHANNEL_ID || '@esepfinancialsupport';
const PRIVATE_CHANNEL_ID = process.env.TELEGRAM_PRIVATE_CHANNEL_ID || null;

// ═══════════════════════════════════════════════════════════════════════════════
// CORE — Bot API
// ═══════════════════════════════════════════════════════════════════════════════

function botRequest(method, body) {
  if (!TOKEN) return Promise.resolve(null);
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req  = https.request({
      hostname: 'api.telegram.org',
      path: `/bot${TOKEN}/${method}`,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) },
    }, (res) => {
      let buf = '';
      res.on('data', (c) => buf += c);
      res.on('end', () => {
        try { resolve(JSON.parse(buf)); }
        catch { resolve(null); }
      });
    });
    req.on('error', (e) => { console.error('[bot] request error:', e.message); resolve(null); });
    req.write(data);
    req.end();
  });
}

function send(chatId, text, extra = {}) {
  return botRequest('sendMessage', { chat_id: chatId, text, parse_mode: 'HTML', ...extra });
}

function sendAdmin(text, extra = {}) {
  if (!ADMIN_ID) return;
  return send(ADMIN_ID, text, extra);
}

async function postToChannel(text, extra = {}) {
  console.log(`[bot] postToChannel → ${CHANNEL_ID}`);
  const result = await send(CHANNEL_ID, text, extra);
  if (result && !result.ok) {
    console.error('[bot] postToChannel FAILED:', result.description);
  } else {
    console.log('[bot] postToChannel OK');
  }
  return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAX DATA — загружаем из БД (tax_config)
// ═══════════════════════════════════════════════════════════════════════════════

async function getTaxConfig() {
  const defaults = {
    mrp: 4325, mzp: 85000,
    ipn_rate_910: 0.04, sn_rate_910: 0,
    opv_rate: 0.10, opvr_rate: 0.035, so_rate: 0.05,
    vosms_rate_self: 0.05, vosms_base_mult: 1.4,
    esp_mrp_city_mult: 1, esp_mrp_rural_mult: 0.5,
    esp_year_mrp_limit: 1175,
    self_emp_rate: 0.04, self_emp_year_limit: 3600,
    vat_rate: 0.16, vat_threshold_mrp: 10000,
    '910_year_mrp': 600000,
  };
  try {
    const { rows } = await db.query('SELECT key, value FROM tax_config');
    const cfg = {};
    for (const r of rows) cfg[r.key] = parseFloat(r.value) || r.value;
    return { ...defaults, ...cfg };
  } catch {
    // Fallback if DB not ready
    return defaults;
  }
}

function formatRate(rate) {
  const pct = Number(rate) * 100;
  return Number.isInteger(pct) ? `${pct}%` : `${pct.toFixed(1)}%`;
}

// ═══════════════════════════════════════════════════════════════════════════════
// USER TRACKING — лимиты бесплатных запросов
// ═══════════════════════════════════════════════════════════════════════════════

const FREE_DAILY_LIMIT = 5;

async function getUserState(chatId) {
  const { rows } = await db.query(
    'SELECT * FROM bot_users WHERE chat_id = $1', [String(chatId)]
  );
  if (rows.length) return rows[0];
  // Create new
  const { rows: [u] } = await db.query(
    `INSERT INTO bot_users (chat_id) VALUES ($1)
     ON CONFLICT (chat_id) DO UPDATE SET chat_id = $1
     RETURNING *`,
    [String(chatId)],
  );
  return u;
}

async function checkAndBump(chatId) {
  const user = await getUserState(chatId);

  // Linked to paid Esep account → unlimited
  if (user.linked_user_id) {
    const { rows } = await db.query('SELECT tier FROM users WHERE id = $1', [user.linked_user_id]);
    if (rows.length && rows[0].tier !== 'free') return { ok: true, remaining: Infinity };
  }

  // Free: 5/day
  const today = new Date().toISOString().slice(0, 10);
  if (user.last_query_date !== today) {
    await db.query(
      `UPDATE bot_users SET queries_today = 1, last_query_date = $1 WHERE chat_id = $2`,
      [today, String(chatId)],
    );
    return { ok: true, remaining: FREE_DAILY_LIMIT - 1 };
  }

  if (user.queries_today >= FREE_DAILY_LIMIT) {
    return { ok: false, remaining: 0 };
  }

  await db.query(
    `UPDATE bot_users SET queries_today = queries_today + 1 WHERE chat_id = $1`,
    [String(chatId)],
  );
  return { ok: true, remaining: FREE_DAILY_LIMIT - user.queries_today - 1 };
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMMANDS — обработчики команд пользователей
// ═══════════════════════════════════════════════════════════════════════════════

async function handleStart(chatId, from, payload) {
  // Deep links: /start calc_5000000 → instant calculation
  if (payload) {
    const p = payload.toLowerCase();

    // ── Привязка аккаунта (bind_TOKEN) ────────────────────────────────────
    // Раздельная проверка: "bind_" с case-sensitive токеном.
    if (payload.startsWith('bind_')) {
      const token = payload.slice(5).trim();
      return handleBindRequest(chatId, from, token);
    }

    if (p.startsWith('calc_')) {
      const amount = p.replace('calc_', '');
      return handleCalc(chatId, amount);
    }
    if (p === 'social') return handleSocial(chatId);
    if (p === 'rates') return handleRates(chatId);
    if (p === 'deadlines') return handleDeadlines(chatId);
    if (p === 'esp') return handleEsp(chatId);
    if (p.startsWith('self_')) {
      const amount = p.replace('self_', '');
      return handleSelf(chatId, amount);
    }
  }

  // Welcome series: regime selection
  send(chatId,
    `Привет, ${from.first_name || 'друг'}! Я — <b>Esep Bot</b>\n\n` +
    `Помогаю ИП и самозанятым Казахстана считать налоги.\n\n` +
    `<b>На каком вы налоговом режиме?</b>`,
    {
      reply_markup: {
        inline_keyboard: [
          [
            { text: '📋 Упрощёнка (910)', callback_data: 'regime_910' },
            { text: '🏷 ЕСП', callback_data: 'regime_esp' },
          ],
          [
            { text: '👤 Самозанятый', callback_data: 'regime_self' },
            { text: '🏢 ОУР', callback_data: 'regime_our' },
          ],
          [
            { text: '❓ Не знаю / хочу разобраться', callback_data: 'regime_unknown' },
          ],
        ],
      },
    },
  );

  // Notify admin about new bot user
  sendAdmin(
    `🤖 <b>Новый пользователь бота</b>\n` +
    `Имя: ${from.first_name || ''} ${from.last_name || ''}\n` +
    `Username: @${from.username || '—'}\n` +
    `Chat ID: <code>${chatId}</code>`,
  );
}

async function handleCalc(chatId, args) {
  const income = parseFloat(args.replace(/\s/g, ''));
  if (!income || income <= 0) {
    return send(chatId, 'Укажите доход: <code>/calc 5000000</code>');
  }

  const c = await getTaxConfig();
  const halfYearLimitMrp = (c['910_year_mrp'] ?? 600000) / 2;
  const limit = c.mrp * halfYearLimitMrp;
  const ipn  = income * c.ipn_rate_910;
  const sn   = income * c.sn_rate_910;
  const total = ipn + sn;
  const rate  = formatRate(c.ipn_rate_910 + c.sn_rate_910);

  const opv   = c.mzp * c.opv_rate;
  const opvr  = c.mzp * c.opvr_rate;
  const so    = c.mzp * c.so_rate;
  const vosms = c.mzp * c.vosms_base_mult * c.vosms_rate_self;
  const socialMonth = opv + opvr + so + vosms;
  const social6 = socialMonth * 6;
  const grand = total + social6;

  const fmt = (n) => Math.round(n).toLocaleString('ru-RU');
  const warn = income > limit
    ? `\n\n⚠️ <b>Доход превышает лимит 910</b> (${fmt(limit)} ₸). Нужен другой режим.`
    : '';

  send(chatId,
    `🧮 <b>Расчёт по упрощёнке (910)</b>\n` +
    `Доход за полугодие: <b>${fmt(income)} ₸</b>\n\n` +
    `<b>Налоги (${rate}):</b>\n` +
    `  ИПН (${formatRate(c.ipn_rate_910)}): ${fmt(ipn)} ₸\n` +
    `  СН (${formatRate(c.sn_rate_910)}): ${fmt(sn)} ₸\n` +
    `  <b>Итого налоги: ${fmt(total)} ₸</b>\n\n` +
    `<b>Соцплатежи за 6 мес:</b>\n` +
    `  ОПВ 10%: ${fmt(opv)} ₸/мес\n` +
    `  ОПВР 3.5%: ${fmt(opvr)} ₸/мес\n` +
    `  СО 5%: ${fmt(so)} ₸/мес\n` +
    `  ВОСМС 5%×1.4МЗП: ${fmt(vosms)} ₸/мес\n` +
    `  6 мес: <b>${fmt(social6)} ₸</b>\n\n` +
    `💰 <b>Общий итог: ${fmt(grand)} ₸</b>\n` +
    `📊 Эффективная ставка: ${(grand / income * 100).toFixed(1)}%` +
    warn,
    {
      reply_markup: {
        inline_keyboard: [
          [
            { text: '📊 Помесячная разбивка', callback_data: `monthly_${Math.round(income)}` },
            { text: '💼 Соцплатежи', callback_data: 'go_social' },
          ],
          [
            { text: '🔢 Другая сумма', callback_data: 'prompt_calc' },
            { text: '📅 Сроки сдачи', callback_data: 'go_deadlines' },
          ],
        ],
      },
    },
  );
}

async function handleSocial(chatId) {
  const c = await getTaxConfig();
  const opv   = c.mzp * c.opv_rate;
  const opvr  = c.mzp * c.opvr_rate;
  const so    = c.mzp * c.so_rate;
  const vosms = c.mzp * c.vosms_base_mult * c.vosms_rate_self;
  const total = opv + opvr + so + vosms;
  const totalNoOpvr = opv + so + vosms;

  const fmt = (n) => Math.round(n).toLocaleString('ru-RU');

  send(chatId,
    `📋 <b>Ежемесячные соцплатежи ИП "за себя"</b>\n` +
    `(база: 1 МЗП = ${fmt(c.mzp)} ₸)\n\n` +
    `  ОПВ 10%: <b>${fmt(opv)} ₸</b>\n` +
    `  ОПВР 3.5%: <b>${fmt(opvr)} ₸</b>\n` +
    `  СО 5%: <b>${fmt(so)} ₸</b>\n` +
    `  ВОСМС 5%×1.4МЗП: <b>${fmt(vosms)} ₸</b>\n\n` +
    `💰 <b>Итого: ${fmt(total)} ₸/мес</b>\n` +
    `  (без ОПВР, до 1975 г.р.: ${fmt(totalNoOpvr)} ₸)\n\n` +
    `📅 Срок оплаты: до 25 числа следующего месяца`,
    {
      reply_markup: {
        inline_keyboard: [
          [
            { text: '🧮 Калькулятор 910', callback_data: 'prompt_calc' },
            { text: '📅 Сроки сдачи', callback_data: 'go_deadlines' },
          ],
        ],
      },
    },
  );
}

async function handleRates(chatId) {
  const c = await getTaxConfig();
  const fmt = (n) => typeof n === 'number' ? n.toLocaleString('ru-RU') : n;
  const halfYearLimitMrp = (c['910_year_mrp'] ?? 600000) / 2;

  send(chatId,
    `📊 <b>Актуальные ставки 2026</b>\n\n` +
    `🔹 МРП: <b>${fmt(c.mrp)} ₸</b>\n` +
    `🔹 МЗП: <b>${fmt(c.mzp)} ₸</b>\n\n` +
    `<b>Упрощёнка (910):</b>\n` +
    `  ИПН: ${formatRate(c.ipn_rate_910)} | СН: ${formatRate(c.sn_rate_910)}\n` +
    `  Итого: ${formatRate(c.ipn_rate_910 + c.sn_rate_910)}\n` +
    `  Лимит: ${fmt(halfYearLimitMrp)} МРП = ${fmt(Math.round(c.mrp * halfYearLimitMrp))} ₸/полугодие\n\n` +
    `<b>Соцплатежи "за себя":</b>\n` +
    `  ОПВ: ${c.opv_rate * 100}% | ОПВР: ${c.opvr_rate * 100}%\n` +
    `  СО: ${c.so_rate * 100}% | ВОСМС: ${c.vosms_rate_self * 100}%×${c.vosms_base_mult}МЗП\n\n` +
    `<b>Другие режимы:</b>\n` +
    `  ЕСП: ${fmt(c.esp_mrp_city_mult)} МРП/мес город, лимит ${fmt(c.esp_year_mrp_limit)} МРП/год\n` +
    `  Самозанятый: ${formatRate(c.self_emp_rate)}, лимит ${fmt(c.self_emp_year_limit)} МРП/год\n` +
    `  НДС: ${formatRate(c.vat_rate)}, порог ${fmt(c.vat_threshold_mrp)} МРП`,
  );
}

async function handleEsp(chatId) {
  const c = await getTaxConfig();
  const city  = c.mrp * c.esp_mrp_city_mult;
  const rural = c.mrp * c.esp_mrp_rural_mult;
  const limit = c.mrp * c.esp_year_mrp_limit;
  const fmt = (n) => Math.round(n).toLocaleString('ru-RU');

  send(chatId,
    `🏷 <b>ЕСП (Единый совокупный платёж)</b>\n\n` +
    `Город: <b>${fmt(city)} ₸/мес</b> (${c.esp_mrp_city_mult} МРП)\n` +
    `Село: <b>${fmt(rural)} ₸/мес</b> (${c.esp_mrp_rural_mult} МРП)\n\n` +
    `Лимит дохода: <b>${fmt(limit)} ₸/год</b> (${c.esp_year_mrp_limit} МРП)\n\n` +
    `Включает: ИПН, СО, ВОСМС, ОПВ — всё в одном платеже.\n` +
    `Подходит для мелкой торговли, услуг физлицам, репетиторов.`,
  );
}

async function handleSelf(chatId, args) {
  const income = parseFloat(args.replace(/\s/g, ''));
  if (!income || income <= 0) {
    return send(chatId, 'Укажите доход: <code>/self 1000000</code>');
  }
  const c = await getTaxConfig();
  const tax   = income * c.self_emp_rate;
  const limit = c.mrp * c.self_emp_year_limit;
  const fmt = (n) => Math.round(n).toLocaleString('ru-RU');
  const warn = income > limit
    ? `\n\n⚠️ Доход превышает лимит (${fmt(limit)} ₸/год)`
    : '';

  send(chatId,
    `👤 <b>Режим самозанятого</b>\n\n` +
    `Доход: <b>${fmt(income)} ₸</b>\n` +
    `Ставка: ${c.self_emp_rate * 100}%\n` +
    `Налог: <b>${fmt(tax)} ₸</b>\n\n` +
    `Лимит: ${fmt(limit)} ₸/год (${c.self_emp_year_limit} МРП)` + warn,
    {
      reply_markup: {
        inline_keyboard: [
          [
            { text: '🔢 Другая сумма', callback_data: 'prompt_self' },
            { text: '💼 Соцплатежи', callback_data: 'go_social' },
          ],
        ],
      },
    },
  );
}

function handleDeadlines(chatId) {
  send(chatId,
    `📅 <b>Сроки сдачи и оплаты (910)</b>\n\n` +
    `<b>1-е полугодие (янв—июнь):</b>\n` +
    `  Подача 910.00: до 15 августа\n` +
    `  Оплата налога: до 25 августа\n\n` +
    `<b>2-е полугодие (июль—декабрь):</b>\n` +
    `  Подача 910.00: до 15 февраля\n` +
    `  Оплата налога: до 25 февраля\n\n` +
    `<b>Соцплатежи:</b>\n` +
    `  Ежемесячно до 25 числа следующего месяца\n` +
    `  Январь → до 25 февраля и т.д.`,
  );
}

async function handleStatus(chatId) {
  const user = await getUserState(chatId);
  const today = new Date().toISOString().slice(0, 10);

  // Queries remaining
  let queriesUsed = 0;
  if (user.last_query_date === today) {
    queriesUsed = user.queries_today || 0;
  }
  const remaining = FREE_DAILY_LIMIT - queriesUsed;

  // Linked account info
  let accountLine = 'Аккаунт Esep: <b>не привязан</b>';
  let tierLine = 'Тариф: Бесплатный';
  let unlimited = false;

  if (user.linked_user_id) {
    try {
      const { rows } = await db.query('SELECT email, name, tier FROM users WHERE id = $1', [user.linked_user_id]);
      if (rows.length) {
        const u = rows[0];
        const tierLabel = { free: 'Бесплатный', ip: 'ИП', accountant: 'Бухгалтер', corporate: 'Корпоративный' };
        accountLine = `Аккаунт: <b>${u.email}</b>`;
        tierLine = `Тариф: <b>${tierLabel[u.tier] || u.tier}</b>`;
        if (u.tier !== 'free') unlimited = true;
      }
    } catch {}
  }

  const limitLine = unlimited
    ? 'Запросы: <b>безлимит</b>'
    : `Запросов сегодня: <b>${remaining} из ${FREE_DAILY_LIMIT}</b>`;

  send(chatId,
    `📊 <b>Ваш статус</b>\n\n` +
    `${limitLine}\n` +
    `${accountLine}\n` +
    `${tierLine}\n\n` +
    (unlimited ? '' : `Для безлимита привяжите платный аккаунт:\n<code>/link your@email.com</code>`),
  );
}

function handleHelp(chatId) {
  send(chatId,
    `📖 <b>Команды Esep Bot</b>\n\n` +
    `/calc 5000000 — налог 910 за полугодие\n` +
    `/social — соцплатежи за себя\n` +
    `/rates — актуальные ставки 2026\n` +
    `/esp — расчёт ЕСП\n` +
    `/self 1000000 — налог самозанятого\n` +
    `/deadlines — сроки сдачи\n` +
    `/status — ваш статус и лимиты\n` +
    `/link email — привязать аккаунт Esep\n\n` +
    `Или просто спросите: <i>"сколько налогов с 3 млн?"</i>`,
    {
      reply_markup: {
        inline_keyboard: [
          [
            { text: '🧮 Рассчитать налог', callback_data: 'prompt_calc' },
            { text: '📊 Ставки 2026', callback_data: 'go_rates' },
          ],
        ],
      },
    },
  );
}

// ── Безопасная привязка через одноразовый токен ────────────────────────────
//
// Флоу:
//   1. Пользователь на сайте жмёт "Привязать Telegram", получает t.me-ссылку
//      с одноразовым токеном.
//   2. Открывает её в Telegram, бот видит /start bind_TOKEN.
//   3. Бот находит токен в БД, показывает email пользователя и кнопки
//      "Это я / Это не я".
//   4. Только при нажатии "Это я" фактическая привязка выполняется,
//      и пользователь получает уведомление.
//
// Защита:
//   - Токен одноразовый и валиден 10 минут.
//   - Бот показывает email — пользователь видит чьё именно имя он привязывает.
//     Если кто-то скинул ему ссылку — он отклонит.
//   - При повторной привязке к существующему аккаунту — заменяем chat_id.
//   - Audit log в auth_security_log.

async function handleBindRequest(chatId, from, token) {
  if (!token) {
    return send(chatId, '❌ Токен привязки не передан.');
  }
  try {
    const r = await db.query(
      `SELECT t.user_id, t.expires_at, t.consumed_at,
              u.email, u.name
         FROM telegram_bind_token t
         JOIN users u ON u.id = t.user_id
        WHERE t.token = $1`,
      [token]
    );
    if (r.rows.length === 0) {
      return send(chatId,
        '❌ Ссылка привязки недействительна или уже использована.\n' +
        'Откройте Esep и запросите новую ссылку привязки.'
      );
    }
    const row = r.rows[0];
    if (row.consumed_at) {
      return send(chatId, '❌ Эта ссылка уже была использована.');
    }
    if (new Date(row.expires_at) < new Date()) {
      return send(chatId, '❌ Срок действия ссылки истёк (10 минут). Запросите новую в Esep.');
    }

    const safeEmail = String(row.email || '').replace(/</g, '&lt;');
    const safeName  = String(row.name || '').replace(/</g, '&lt;');

    return send(chatId,
      `🔐 <b>Привязка Telegram к Esep</b>\n\n` +
      `Кто-то запросил привязать <b>этот Telegram</b> к аккаунту:\n\n` +
      `📧 ${safeEmail}\n` +
      (safeName ? `👤 ${safeName}\n` : '') +
      `\n<b>Это вы?</b>\n\n` +
      `Если этот аккаунт ваш — нажмите "Это я". Если нет — нажмите "Это не я", ` +
      `и мы ничего не привяжем.\n\n` +
      `<i>После подтверждения вы сможете восстанавливать пароль через этот Telegram.</i>`,
      {
        reply_markup: {
          inline_keyboard: [
            [{ text: '✅ Это я, привязать', callback_data: `bind_yes:${token}` }],
            [{ text: '❌ Это не я', callback_data: `bind_no:${token}` }],
          ],
        },
      }
    );
  } catch (err) {
    console.error('[bot/bind] failed:', err);
    return send(chatId, '❌ Ошибка привязки. Попробуйте снова.');
  }
}

async function handleBindConfirm(cb, token) {
  const chatId = cb.from.id;
  try {
    const r = await db.query(
      `SELECT t.user_id, t.expires_at, t.consumed_at,
              u.email
         FROM telegram_bind_token t
         JOIN users u ON u.id = t.user_id
        WHERE t.token = $1`,
      [token]
    );
    if (r.rows.length === 0) {
      botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: '❌ Токен не найден' });
      return;
    }
    const row = r.rows[0];
    if (row.consumed_at) {
      botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: 'Уже использовано' });
      return send(chatId, '❌ Эта ссылка уже была использована.');
    }
    if (new Date(row.expires_at) < new Date()) {
      botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: 'Просрочено' });
      return send(chatId, '❌ Срок ссылки истёк.');
    }

    const username = cb.from.username || null;

    // Если у этого chat_id уже привязан другой user — отвяжем (chat_id уникален)
    await db.query(
      `UPDATE users SET telegram_chat_id = NULL,
                        telegram_username = NULL,
                        telegram_linked_at = NULL
        WHERE telegram_chat_id = $1`,
      [String(chatId)]
    );

    // Привязываем
    await db.query(
      `UPDATE users
          SET telegram_chat_id = $1,
              telegram_username = $2,
              telegram_linked_at = NOW()
        WHERE id = $3`,
      [String(chatId), username, row.user_id]
    );

    // bot_users — сохраняем для совместимости с существующим ботом
    await db.query(
      `INSERT INTO bot_users (chat_id, linked_user_id)
       VALUES ($1, $2)
       ON CONFLICT (chat_id) DO UPDATE SET linked_user_id = EXCLUDED.linked_user_id`,
      [String(chatId), row.user_id]
    );

    // Помечаем токен использованным
    await db.query(
      `UPDATE telegram_bind_token
          SET consumed_at = NOW(),
              consumed_chat_id = $1,
              consumed_username = $2
        WHERE token = $3`,
      [String(chatId), username, token]
    );

    await db.query(
      `INSERT INTO auth_security_log (user_id, event, meta)
       VALUES ($1, 'tg_bind_confirmed', $2::jsonb)`,
      [row.user_id, JSON.stringify({ chat_id: String(chatId), username })]
    );

    botRequest('answerCallbackQuery',
      { callback_query_id: cb.id, text: '✅ Привязано!' });

    return send(chatId,
      `✅ <b>Telegram привязан к аккаунту Esep</b>\n\n` +
      `📧 ${String(row.email).replace(/</g, '&lt;')}\n\n` +
      `Теперь вы можете восстановить пароль через этот Telegram, если забудете его.\n\n` +
      `<i>Если вы не привязывали аккаунт — отвяжите Telegram через настройки в приложении.</i>`
    );
  } catch (err) {
    console.error('[bot/bind-confirm] failed:', err);
    botRequest('answerCallbackQuery',
      { callback_query_id: cb.id, text: '❌ Ошибка' });
  }
}

async function handleBindReject(cb, token) {
  const chatId = cb.from.id;
  try {
    const r = await db.query(
      `SELECT user_id FROM telegram_bind_token WHERE token = $1`,
      [token]
    );
    const userId = r.rows[0]?.user_id || null;

    // Помечаем токен недействительным
    await db.query(
      `UPDATE telegram_bind_token
          SET expires_at = NOW(),
              consumed_at = NOW(),
              consumed_chat_id = $1
        WHERE token = $2`,
      [String(chatId), token]
    );

    if (userId) {
      await db.query(
        `INSERT INTO auth_security_log (user_id, event, meta)
         VALUES ($1, 'tg_bind_rejected', $2::jsonb)`,
        [userId, JSON.stringify({ chat_id: String(chatId) })]
      );
    }

    botRequest('answerCallbackQuery',
      { callback_query_id: cb.id, text: '🛡 Отклонено' });
    return send(chatId,
      `🛡 <b>Привязка отклонена.</b>\n\n` +
      `Никаких аккаунтов мы к вашему Telegram не привязали.\n\n` +
      `Если кто-то прислал вам эту ссылку — будьте осторожны, возможно это ` +
      `попытка получить доступ к чужому аккаунту.`
    );
  } catch (err) {
    console.error('[bot/bind-reject] failed:', err);
    botRequest('answerCallbackQuery',
      { callback_query_id: cb.id, text: '❌ Ошибка' });
  }
}

async function handleLink(chatId, args) {
  const email = args.trim().toLowerCase();
  if (!email || !email.includes('@')) {
    return send(chatId, 'Укажите email: <code>/link your@email.com</code>');
  }

  const { rows } = await db.query('SELECT id, tier, name FROM users WHERE email = $1', [email]);
  if (!rows.length) {
    return send(chatId, `Email <code>${email}</code> не найден в Esep.\nСначала зарегистрируйтесь в приложении.`);
  }

  await db.query(
    'UPDATE bot_users SET linked_user_id = $1 WHERE chat_id = $2',
    [rows[0].id, String(chatId)],
  );

  const tierLabel = { free: 'Бесплатный', ip: 'ИП', accountant: 'Бухгалтер', corporate: 'Корпоративный' };
  const isPaid = rows[0].tier !== 'free';

  send(chatId,
    `✅ <b>Аккаунт привязан!</b>\n\n` +
    `Имя: ${rows[0].name || '—'}\n` +
    `Тариф: <b>${tierLabel[rows[0].tier] || rows[0].tier}</b>\n\n` +
    (isPaid
      ? 'Запросы к боту — без ограничений.'
      : `Бесплатный тариф: ${FREE_DAILY_LIMIT} запросов/день.\nДля безлимита — перейдите на платный тариф.`),
  );

  sendAdmin(
    `🔗 <b>Привязка бота</b>\n` +
    `Chat: <code>${chatId}</code> → ${email} (${rows[0].tier})`,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMART TEXT — обработка свободного текста (вопросы про налоги)
// ═══════════════════════════════════════════════════════════════════════════════

async function handleFreeText(chatId, text) {
  const lower = text.toLowerCase();

  // Попытка вытащить сумму из текста
  const numMatch = lower.match(/(\d[\d\s]*\d)/);
  const num = numMatch ? parseFloat(numMatch[1].replace(/\s/g, '')) : null;

  // Detect intent
  if ((lower.includes('налог') || lower.includes('сколько')) && num && num > 10000) {
    return handleCalc(chatId, String(num));
  }
  if (lower.includes('соцплатеж') || lower.includes('опв') || lower.includes('за себя')) {
    return handleSocial(chatId);
  }
  if (lower.includes('ставк') || lower.includes('мрп') || lower.includes('мзп')) {
    return handleRates(chatId);
  }
  if (lower.includes('есп') || lower.includes('совокупн')) {
    return handleEsp(chatId);
  }
  if (lower.includes('самозаня')) {
    if (num) return handleSelf(chatId, String(num));
    return send(chatId, 'Режим самозанятого: 4% от дохода, лимит 3 600 МРП/год.\nУкажите сумму: <code>/self 1000000</code>');
  }
  if (lower.includes('срок') || lower.includes('дедлайн') || lower.includes('когда сдавать')) {
    return handleDeadlines(chatId);
  }
  if (lower.includes('910') || lower.includes('упрощён') || lower.includes('упрощен')) {
    if (num) return handleCalc(chatId, String(num));
    return send(chatId, 'Упрощёнка (910): 4% от дохода (ИПН 4%, СН 0%).\nУкажите сумму: <code>/calc 5000000</code>');
  }

  // Default: не понял
  send(chatId,
    `Не совсем понял вопрос. Попробуйте:\n\n` +
    `/calc 5000000 — расчёт налога\n` +
    `/social — соцплатежи\n` +
    `/rates — ставки 2026\n` +
    `/deadlines — сроки\n\n` +
    `Или напишите сумму: <i>"сколько налогов с 3 млн?"</i>`,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// WEBHOOK — главный обработчик входящих обновлений
// ═══════════════════════════════════════════════════════════════════════════════

async function handleUpdate(update) {
  try {
    // Callback queries (inline buttons)
    if (update.callback_query) {
      return handleCallbackQuery(update.callback_query);
    }

    // Channel posts — capture chat_id and notify admin
    if (update.channel_post) {
      const cp = update.channel_post;
      const channelId = cp.chat.id;
      const channelTitle = cp.chat.title || '';
      console.log(`[bot] Channel post from: ${channelId} (${channelTitle})`);
      sendAdmin(
        `📢 <b>Канал обнаружен</b>\n\n` +
        `Название: ${channelTitle}\n` +
        `Chat ID: <code>${channelId}</code>\n\n` +
        `Добавь в Railway:\n<code>TELEGRAM_PRIVATE_CHANNEL_ID=${channelId}</code>`,
      );
      return;
    }

    const msg = update.message;
    if (!msg || !msg.text) return;

    const chatId = msg.chat.id;
    const text   = msg.text.trim();
    const from   = msg.from || {};

    // Commands that don't consume rate limit
    if (text === '/start' || text.startsWith('/start ')) {
      const payload = text.startsWith('/start ') ? text.slice(7).trim() : null;
      return handleStart(chatId, from, payload);
    }
    if (text === '/status' || text.startsWith('/status ')) {
      return handleStatus(chatId);
    }
    if (text === '/help' || text.startsWith('/help ')) {
      return handleHelp(chatId);
    }

    // Admin channel commands (no rate limit)
    const adminCmd = text.split(/\s+/)[0].toLowerCase();
    const adminArgs = text.slice(adminCmd.length).trim();
    if (await handleAdminChannelCommand(chatId, adminCmd, adminArgs)) return;

    // Rate limit check for everything else
    const { ok, remaining } = await checkAndBump(chatId);
    if (!ok) {
      return send(chatId,
        `⏳ Лимит бесплатных запросов исчерпан (${FREE_DAILY_LIMIT}/день).\n\n` +
        `Для безлимита — привяжите платный аккаунт Esep:\n<code>/link your@email.com</code>\n\n` +
        `Или попробуйте завтра.`,
        {
          reply_markup: {
            inline_keyboard: [
              [{ text: '🌐 Открыть Esep', url: 'https://esepkz.vercel.app' }],
              [{ text: '💬 Консультация', url: 'https://t.me/alibekovakarakat' }],
            ],
          },
        },
      );
    }

    // Parse command
    const cmd = text.split(/\s+/)[0].toLowerCase().replace(/@\w+$/, '');
    const args = text.slice(cmd.length).trim();

    switch (cmd) {
      case '/calc':      return handleCalc(chatId, args);
      case '/social':    return handleSocial(chatId);
      case '/rates':     return handleRates(chatId);
      case '/esp':       return handleEsp(chatId);
      case '/self':      return handleSelf(chatId, args);
      case '/deadlines': return handleDeadlines(chatId);
      case '/link':      return handleLink(chatId, args);
      default:
        // Free text
        return handleFreeText(chatId, text);
    }
  } catch (err) {
    console.error('[bot] handleUpdate error:', err);
  }
}

// ── Callback queries ────────────────────────────────────────────────────────
async function handleCallbackQuery(cb) {
  const data = cb.data || '';

  // Привязка Telegram (одноразовый токен с сайта)
  if (data.startsWith('bind_yes:')) {
    return handleBindConfirm(cb, data.slice('bind_yes:'.length));
  }
  if (data.startsWith('bind_no:')) {
    return handleBindReject(cb, data.slice('bind_no:'.length));
  }

  if (data === 'tax_ok') {
    return botRequest('answerCallbackQuery', {
      callback_query_id: cb.id,
      text: '✅ Отмечено — ставки актуальны',
    });
  }

  if (data === 'tax_auto_ok') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: '✅ Подтверждено!' });
    if (cb.message) {
      botRequest('editMessageReplyMarkup', {
        chat_id: cb.message.chat.id,
        message_id: cb.message.message_id,
        reply_markup: { inline_keyboard: [[{ text: '✅ Подтверждено', callback_data: 'noop' }]] },
      });
    }
    return;
  }

  if (data === 'tax_auto_revert') {
    try {
      const { revertLastAutoUpdate } = require('../jobs/taxMonitor');
      const result = await revertLastAutoUpdate();
      botRequest('answerCallbackQuery', {
        callback_query_id: cb.id,
        text: result.ok ? '↩️ Откат выполнен!' : result.error,
      });
      if (cb.message && result.ok) {
        botRequest('editMessageReplyMarkup', {
          chat_id: cb.message.chat.id,
          message_id: cb.message.message_id,
          reply_markup: { inline_keyboard: [[{ text: '↩️ Откачено', callback_data: 'noop' }]] },
        });
      }
    } catch (err) {
      console.error('[bot] tax_auto_revert error:', err.message);
      botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: 'Ошибка отката' });
    }
    return;
  }

  // Publish post from private channel → public channel
  if (data.startsWith('pub_channel_')) {
    const postId = parseInt(data.replace('pub_channel_', ''));
    try {
      const { rows } = await db.query('SELECT * FROM marketing_posts WHERE id = $1', [postId]);
      if (!rows.length) {
        return botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: 'Пост не найден' });
      }
      const post = rows[0];
      await postToChannel(`<b>${post.title}</b>\n\n${post.body}`, CHANNEL_CTA_KEYBOARD);
      await marketing.markPosted(postId);
      botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: '✅ Опубликовано в канал!' });
      // Update the message in private channel
      if (cb.message) {
        botRequest('editMessageReplyMarkup', {
          chat_id: cb.message.chat.id,
          message_id: cb.message.message_id,
          reply_markup: { inline_keyboard: [[{ text: '✅ Опубликовано', callback_data: 'noop' }]] },
        });
      }
    } catch (err) {
      console.error('[bot] pub_channel error:', err.message);
      botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: 'Ошибка публикации' });
    }
    return;
  }

  // Skip post
  if (data.startsWith('skip_post_')) {
    const postId = parseInt(data.replace('skip_post_', ''));
    await marketing.markPosted(postId);
    botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: '⏭ Пропущено' });
    if (cb.message) {
      botRequest('editMessageReplyMarkup', {
        chat_id: cb.message.chat.id,
        message_id: cb.message.message_id,
        reply_markup: { inline_keyboard: [[{ text: '⏭ Пропущено', callback_data: 'noop' }]] },
      });
    }
    return;
  }

  if (data === 'noop') {
    return botRequest('answerCallbackQuery', { callback_query_id: cb.id });
  }

  const chatId = cb.message?.chat?.id;
  if (!chatId) return;

  // ── Inline keyboards after calculations ──

  // Monthly breakdown: monthly_{income}
  if (data.startsWith('monthly_')) {
    const income = parseFloat(data.replace('monthly_', ''));
    if (!income) return;
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });

    const c = await getTaxConfig();
    const monthlyTax = income * (c.ipn_rate_910 + c.sn_rate_910) / 6;
    const opv   = c.mzp * c.opv_rate;
    const opvr  = c.mzp * c.opvr_rate;
    const so    = c.mzp * c.so_rate;
    const vosms = c.mzp * c.vosms_base_mult * c.vosms_rate_self;
    const socialMonth = opv + opvr + so + vosms;
    const totalMonth = monthlyTax + socialMonth;
    const fmt = (n) => Math.round(n).toLocaleString('ru-RU');

    return send(chatId,
      `📊 <b>Помесячная разбивка</b>\n` +
      `(доход ${fmt(income)} ₸ за полугодие)\n\n` +
      `<b>Каждый месяц (×6):</b>\n` +
      `  Налог (910): ~${fmt(monthlyTax)} ₸\n` +
      `  ОПВ: ${fmt(opv)} ₸\n` +
      `  ОПВР: ${fmt(opvr)} ₸\n` +
      `  СО: ${fmt(so)} ₸\n` +
      `  ВОСМС: ${fmt(vosms)} ₸\n\n` +
      `💰 <b>Итого в месяц: ~${fmt(totalMonth)} ₸</b>\n` +
      `📅 Налог платится раз в полугодие, соцплатежи — ежемесячно`,
    );
  }

  // Navigation callbacks
  if (data === 'go_social') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return handleSocial(chatId);
  }
  if (data === 'go_deadlines') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return handleDeadlines(chatId);
  }
  if (data === 'go_rates') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return handleRates(chatId);
  }
  if (data === 'prompt_calc') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return send(chatId, '🔢 Введите сумму дохода за полугодие:\n\nНапример: <code>/calc 5000000</code>\n\nИли просто напишите: <i>"сколько налогов с 3 млн?"</i>');
  }
  if (data === 'prompt_self') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return send(chatId, '🔢 Введите сумму дохода самозанятого:\n\nНапример: <code>/self 1000000</code>');
  }
  if (data === 'show_help') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return handleHelp(chatId);
  }

  // ── Welcome series: regime selection ──

  if (data === 'regime_910') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return send(chatId,
      `📋 <b>Упрощёнка (форма 910)</b>\n\n` +
      `Самый популярный режим для ИП в Казахстане.\n\n` +
      `<b>Ставка:</b> 4% от дохода (ИПН 4%, СН 0%)\n` +
      `<b>Лимит:</b> 300 000 МРП за полугодие\n` +
      `<b>Отчётность:</b> 910.00 раз в полугодие\n` +
      `<b>+ Соцплатежи:</b> ~21 675 ₸/мес за себя\n\n` +
      `Попробуйте расчёт:`,
      {
        reply_markup: {
          inline_keyboard: [
            [{ text: '🧮 Рассчитать 5 000 000 ₸', callback_data: 'demo_calc_5000000' }],
            [
              { text: '📖 Все команды', callback_data: 'show_help' },
              { text: '💼 Соцплатежи', callback_data: 'go_social' },
            ],
          ],
        },
      },
    );
  }

  if (data === 'regime_esp') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    const c = await getTaxConfig();
    const city = Math.round(c.mrp * c.esp_mrp_city_mult);
    return send(chatId,
      `🏷 <b>ЕСП (Единый совокупный платёж)</b>\n\n` +
      `Самый простой режим — фиксированная сумма.\n\n` +
      `<b>Город:</b> ${city.toLocaleString('ru-RU')} ₸/мес (1 МРП)\n` +
      `<b>Село:</b> ${Math.round(city / 2).toLocaleString('ru-RU')} ₸/мес (0.5 МРП)\n` +
      `<b>Лимит дохода:</b> ~5 млн ₸/год\n` +
      `<b>Включает:</b> ИПН + СО + ВОСМС + ОПВ\n\n` +
      `Подходит для мелкой торговли, услуг физлицам.`,
      {
        reply_markup: {
          inline_keyboard: [
            [
              { text: '📖 Все команды', callback_data: 'show_help' },
              { text: '📊 Ставки 2026', callback_data: 'go_rates' },
            ],
          ],
        },
      },
    );
  }

  if (data === 'regime_self') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return send(chatId,
      `👤 <b>Режим самозанятого</b>\n\n` +
      `Минимум бюрократии, без регистрации ИП.\n\n` +
      `<b>Ставка:</b> 4% от дохода (ЕСП)\n` +
      `<b>Лимит:</b> ~15.3 млн ₸/год\n` +
      `<b>Нельзя:</b> нанимать сотрудников\n` +
      `<b>Оплата:</b> через приложение e-Salyk Azamat\n\n` +
      `Попробуйте расчёт:`,
      {
        reply_markup: {
          inline_keyboard: [
            [{ text: '🧮 Рассчитать 1 000 000 ₸', callback_data: 'demo_self_1000000' }],
            [{ text: '📖 Все команды', callback_data: 'show_help' }],
          ],
        },
      },
    );
  }

  if (data === 'regime_our') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return send(chatId,
      `🏢 <b>ОУР (Общеустановленный режим)</b>\n\n` +
      `Для крупного бизнеса или тех, кто превысил лимит 910.\n\n` +
      `<b>ИПН:</b> 10% от чистого дохода\n` +
      `<b>НДС:</b> 16% (при обороте > 10 000 МРП)\n` +
      `<b>Отчётность:</b> ежеквартальная\n\n` +
      `Бот пока не считает ОУР — это сложный режим.\n` +
      `Рекомендуем обратиться к бухгалтеру.`,
      {
        reply_markup: {
          inline_keyboard: [
            [
              { text: '📋 Попробовать 910', callback_data: 'regime_910' },
              { text: '📖 Все команды', callback_data: 'show_help' },
            ],
          ],
        },
      },
    );
  }

  if (data === 'regime_unknown') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return send(chatId,
      `❓ <b>Какой режим выбрать?</b>\n\n` +
      `Кратко:\n\n` +
      `🏷 <b>ЕСП</b> — доход до ~5 млн/год, фикс. ~4 325 ₸/мес\n` +
      `👤 <b>Самозанятый</b> — до ~15 млн/год, 4%, без сотрудников\n` +
      `📋 <b>Упрощёнка 910</b> — до 300 000 МРП/полугодие, 4%\n` +
      `🏢 <b>ОУР</b> — без лимитов, 10% + НДС\n\n` +
      `Большинство ИП работают на <b>упрощёнке (910)</b>.\n` +
      `Попробуйте рассчитать:`,
      {
        reply_markup: {
          inline_keyboard: [
            [{ text: '🧮 Рассчитать 5 000 000 ₸ (910)', callback_data: 'demo_calc_5000000' }],
            [{ text: '👤 Рассчитать 1 000 000 ₸ (самозан.)', callback_data: 'demo_self_1000000' }],
            [{ text: '📖 Все команды', callback_data: 'show_help' }],
          ],
        },
      },
    );
  }

  // Demo calculations from welcome series (don't consume rate limit)
  if (data === 'demo_calc_5000000') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return handleCalc(chatId, '5000000');
  }
  if (data === 'demo_self_1000000') {
    botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return handleSelf(chatId, '1000000');
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADMIN NOTIFICATIONS — уведомления разработчику
// ═══════════════════════════════════════════════════════════════════════════════

/** Generate an admin link. Login is handled by /api/admin/login cookie flow. */
function adminLink(adminUrl, hash) {
  return `${adminUrl}/api/admin#${hash}`;
}

function notifyNewUser({ email, name }) {
  sendAdmin(
    `👤 <b>Регистрация в Esep</b>\n\nEmail: <code>${email}</code>\nИмя: ${name || '—'}`,
  );
}

function notifyTaxCheck({ mentions, adminUrl }) {
  const url = adminLink(adminUrl, 'tax');
  sendAdmin(
    `📋 <b>Возможны изменения в налогах</b>\n\n` +
    `Найдено упоминаний: <b>${mentions}</b>\n\n` +
    `Проверьте ставки и обновите:\n` +
    `<a href="${url}">Открыть редактор</a>`,
    {
      reply_markup: {
        inline_keyboard: [[
          { text: '⚙️ Редактор ставок', url },
          { text: '✅ Всё актуально', callback_data: 'tax_ok' },
        ]],
      },
    },
  );
}

/** Notify admin about auto-applied tax config changes with proof */
function notifyTaxAutoUpdate({ changes, sources, adminUrl }) {
  const url = adminLink(adminUrl, 'tax');
  let msg = `🤖 <b>Ставки обновлены автоматически</b>\n\n`;

  for (const c of changes) {
    msg += `• <b>${c.label}</b>: <code>${c.oldValue}</code> → <code>${c.newValue}</code>\n`;
  }

  msg += `\n📎 <b>Источники:</b>\n`;
  for (const s of sources) {
    msg += `• <a href="${s.url}">${s.title}</a>\n`;
  }

  msg += `\n<a href="${url}">Проверить в админке</a>`;

  sendAdmin(msg, {
    reply_markup: {
      inline_keyboard: [
        [
          { text: '✅ Подтверждаю', callback_data: 'tax_auto_ok' },
          { text: '↩️ Откатить', callback_data: 'tax_auto_revert' },
        ],
        [{ text: '⚙️ Открыть редактор', url }],
      ],
    },
  });
}

function sendMonthlyReminder({ month, adminUrl }) {
  const url = adminLink(adminUrl, 'tax');
  const reminders = {
    11: '📅 Ноябрь — проект бюджета на следующий год. Проверьте МРП/МЗП.',
    12: '📅 Декабрь — бюджет подписан. Обновите МРП и МЗП.',
    1:  '📅 Январь — новые ставки. Проверьте ОПВР, ВОСМС, СО.',
    4:  '📅 Апрель — возможны поправки НК РК. Проверьте ставки.',
  };
  const text = reminders[month];
  if (!text) return;
  sendAdmin(
    `${text}\n\n<a href="${url}">Редактор ставок</a>`,
    { reply_markup: { inline_keyboard: [[{ text: '⚙️ Проверить', url }]] } },
  );
}

function notifyArticleDraft({ title, adminUrl }) {
  const url = adminLink(adminUrl, 'articles');
  sendAdmin(
    `✍️ <b>Новый черновик</b>\n\n«${title}»\n\n<a href="${url}">Открыть</a>`,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// CHANNEL — автопостинг в @esepfinancialsupport
// ═══════════════════════════════════════════════════════════════════════════════

const CHANNEL_CTA_KEYBOARD = {
  reply_markup: {
    inline_keyboard: [
      [
        { text: '🌐 Открыть Esep', url: 'https://esepkz.vercel.app' },
        { text: '🧮 Калькулятор', url: 'https://t.me/EsepKZ_bot' },
      ],
      [
        { text: '💬 Консультация', url: 'https://t.me/alibekovakarakat' },
      ],
    ],
  },
};

// — Tax tips pool —
const TAX_TIPS = [
  {
    title: 'Знаете ли вы?',
    body: 'МРП в 2026 году вырос до 4 325 тенге (с 3 932 в 2025). Это влияет на лимиты по 910 форме, штрафы и госпошлины.',
  },
  {
    title: 'Соцплатежи "за себя"',
    body: 'Каждый ИП на упрощёнке обязан платить ОПВ, ОПВР, СО и ВОСМС ежемесячно — даже если дохода нет. Итого ~21 675 тенге/мес в 2026.',
  },
  {
    title: 'Лимит по упрощёнке (910)',
    body: 'Максимальный доход — 600 000 МРП за год (300 000 МРП за полугодие). Превышение = переход на другой режим.',
  },
  {
    title: 'ОПВР — новый взнос',
    body: 'С 2024 ИП обязаны платить ОПВР (обязательные пенсионные взносы работодателя) за себя: 3.5% от МЗП = 2 975 тенге/мес.',
  },
  {
    title: 'Сравнение режимов',
    body: 'Упрощёнка (910): 4% от дохода + соцплатежи.\nЕСП: фиксированная сумма (1 МРП/мес), но лимит дохода ~5 млн/год.\nСамозанятый: 4%, но нет найма сотрудников.\n\nВыбирайте режим под свой масштаб!',
  },
  {
    title: 'Срок подачи 910.00',
    body: '1-е полугодие (янв—июн): подача до 15 августа, оплата до 25 августа.\n2-е полугодие (июл—дек): подача до 15 февраля, оплата до 25 февраля.\n\nНе пропустите!',
  },
  {
    title: 'Что входит в ЕСП?',
    body: 'Единый совокупный платёж (ЕСП) = ИПН + СО + ВОСМС + ОПВ в одном платеже.\nГород: 4 325 тенге/мес | Село: 2 163 тенге/мес.\nИдеально для мелкой торговли и услуг.',
  },
  {
    title: 'ВОСМС в 2026',
    body: 'Работник: 2% от ЗП (база до 20 МЗП = 1 700 000 тенге).\nРаботодатель: 3% (база до 40 МЗП).\nИП за себя: 5% от 1.4 МЗП = 5 950 тенге/мес.',
  },
  {
    title: 'Штрафы за просрочку',
    body: 'Несвоевременная подача 910.00: от 15 до 30 МРП (64 875 — 129 750 тенге).\nНеуплата налога: пеня 1.25× ставка рефинансирования за каждый день.\n\nВедите учёт вовремя!',
  },
  {
    title: 'НДС — когда встаёте на учёт?',
    body: 'Порог: оборот свыше 10 000 МРП за 12 мес = 43 250 000 тенге.\nПосле регистрации: +16% к цене, но можно зачитывать входящий НДС.',
  },
];

// — Deadline reminders (month → array of reminders) —
const DEADLINE_REMINDERS = {
  1: ['До 25 января — соцплатежи за декабрь.'],
  2: [
    'До 15 февраля — подача 910.00 за 2-е полугодие.',
    'До 25 февраля — оплата налога по 910.00 за 2-е полугодие.',
    'До 25 февраля — соцплатежи за январь.',
  ],
  3: ['До 25 марта — соцплатежи за февраль.'],
  4: ['До 25 апреля — соцплатежи за март.'],
  5: ['До 25 мая — соцплатежи за апрель.'],
  6: ['До 25 июня — соцплатежи за май.'],
  7: ['До 25 июля — соцплатежи за июнь.'],
  8: [
    'До 15 августа — подача 910.00 за 1-е полугодие.',
    'До 25 августа — оплата налога по 910.00 за 1-е полугодие.',
    'До 25 августа — соцплатежи за июль.',
  ],
  9: ['До 25 сентября — соцплатежи за август.'],
  10: ['До 25 октября — соцплатежи за сентябрь.'],
  11: ['До 25 ноября — соцплатежи за октябрь.'],
  12: ['До 25 декабря — соцплатежи за ноябрь.'],
};

/**
 * Post a random tax tip to the channel
 */
async function postTaxTip() {
  const tip = TAX_TIPS[Math.floor(Math.random() * TAX_TIPS.length)];
  await postToChannel(
    `💡 <b>${tip.title}</b>\n\n${tip.body}\n\n` +
    `Считайте налоги точно — в боте @EsepKZ_bot или в приложении Esep.`,
    CHANNEL_CTA_KEYBOARD,
  );
}

/**
 * Post deadline reminders for the current month
 */
async function postDeadlineReminder() {
  const month = new Date().getMonth() + 1;
  const reminders = DEADLINE_REMINDERS[month];
  if (!reminders || !reminders.length) return;

  const list = reminders.map(r => `  • ${r}`).join('\n');
  await postToChannel(
    `⏰ <b>Налоговый дедлайн</b>\n\n${list}\n\n` +
    `Не забудьте оплатить вовремя!`,
    CHANNEL_CTA_KEYBOARD,
  );
}

/**
 * Post a published article from the DB to the channel
 */
async function postLatestArticle() {
  try {
    const { rows } = await db.query(
      `SELECT id, title, summary FROM articles
       WHERE status = 'published' AND channel_posted IS NOT TRUE
       ORDER BY published_at DESC LIMIT 1`,
    );
    if (!rows.length) return;

    const art = rows[0];
    await postToChannel(
      `📰 <b>${art.title}</b>\n\n${art.summary || ''}\n\n` +
      `Читайте полностью в приложении Esep.`,
      CHANNEL_CTA_KEYBOARD,
    );

    await db.query('UPDATE articles SET channel_posted = TRUE WHERE id = $1', [art.id]);
  } catch (err) {
    console.error('[bot] postLatestArticle error:', err.message);
  }
}

/**
 * Post a lead magnet — free calculator promo
 */
async function postLeadMagnet() {
  const messages = [
    '🧮 <b>Бесплатный калькулятор налогов ИП</b>\n\n' +
    'Не знаете сколько платить по упрощёнке? Напишите сумму дохода боту — мгновенный расчёт!\n\n' +
    'ИПН + все соцплатежи = точная сумма.',

    '📊 <b>Какой режим выгоднее?</b>\n\n' +
    'Упрощёнка, ЕСП или самозанятый? Зависит от дохода.\n' +
    'Бот @EsepKZ_bot сравнит все режимы за секунду.\n\n' +
    'Просто напишите: "сколько налогов с 3 млн?"',

    '💰 <b>Сколько реально платит ИП?</b>\n\n' +
    'Налог 4% — это не всё. Есть ОПВ, ОПВР, СО, ВОСМС — ещё ~21 500 тенге/мес.\n' +
    'Хотите точную сумму? Спросите бота @EsepKZ_bot.',
  ];

  const msg = messages[Math.floor(Math.random() * messages.length)];
  await postToChannel(msg, CHANNEL_CTA_KEYBOARD);
}

// — Scheduling engine (runs inside setInterval in production) —
let _schedulerStarted = false;

function startChannelScheduler() {
  if (_schedulerStarted) return;
  _schedulerStarted = true;

  // Post a tax tip every day at ~10:00 AM Almaty (UTC+5)
  // Check every hour, post when conditions match
  setInterval(async () => {
    try {
      const now = new Date();
      const almatyHour = (now.getUTCHours() + 5) % 24;
      const day = now.getDay(); // 0=Sun

      // 10:00 — daily tax tip (Mon-Fri)
      if (almatyHour === 10 && day >= 1 && day <= 5) {
        await postTaxTip();
      }

      // 09:00 on 1st and 15th of month — deadline reminder
      if (almatyHour === 9 && (now.getUTCDate() === 1 || now.getUTCDate() === 15)) {
        await postDeadlineReminder();
      }

      // 12:00 on Wednesday — lead magnet
      if (almatyHour === 12 && day === 3) {
        await postLeadMagnet();
      }

      // 14:00 on Monday — article (if any unpublished)
      if (almatyHour === 14 && day === 1) {
        await postLatestArticle();
      }

      // 08:00 every day — send daily marketing post to private channel
      if (almatyHour === 8) {
        await postDailyContent();
      }
    } catch (err) {
      console.error('[bot] scheduler error:', err.message);
    }
  }, 60 * 60 * 1000); // check every hour

  console.log('[bot] Channel scheduler started');
}

// — Send to private channel (drafts for admin) —
async function sendToPrivate(text, extra = {}) {
  if (!PRIVATE_CHANNEL_ID) {
    // Fallback: send to admin DM
    return sendAdmin(text, extra);
  }
  console.log(`[bot] sendToPrivate → ${PRIVATE_CHANNEL_ID}`);
  const result = await send(PRIVATE_CHANNEL_ID, text, extra);
  if (result && !result.ok) {
    console.error('[bot] sendToPrivate FAILED:', result.description);
    // Fallback to admin DM
    return sendAdmin(text, extra);
  }
  return result;
}

// — Post today's marketing content to private channel —
async function postDailyContent() {
  const post = await marketing.getTodayPost();
  if (!post) {
    console.log('[bot] No marketing post for today');
    return null;
  }

  const typeEmoji = {
    pain: '🔴 БОЛЬ', education: '📚 ОБУЧЕНИЕ', case: '📋 КЕЙС',
    selling: '💰 ПРОДАЖА', engagement: '💬 ВОВЛЕЧЕНИЕ',
  };
  const typeLabel = typeEmoji[post.type] || post.type;

  // Send to private channel as draft
  await sendToPrivate(
    `━━━━━━━━━━━━━━━━━━━━\n` +
    `${typeLabel} | ${post.scheduled}\n` +
    `━━━━━━━━━━━━━━━━━━━━\n\n` +
    `<b>${post.title}</b>\n\n` +
    `${post.body}`,
    {
      reply_markup: {
        inline_keyboard: [
          [
            { text: '✅ Опубликовать в канал', callback_data: `pub_channel_${post.id}` },
            { text: '✏️ Пропустить', callback_data: `skip_post_${post.id}` },
          ],
        ],
      },
    },
  );

  return post;
}

// — Admin commands for channel (in private chat with admin) —
async function handleAdminChannelCommand(chatId, cmd, args) {
  if (String(chatId) !== String(ADMIN_ID)) return false;

  switch (cmd) {
    // ── Публичный канал ──
    case '/post_tip':
      await postTaxTip();
      send(chatId, 'Совет опубликован в канал.');
      return true;

    case '/post_deadline':
      await postDeadlineReminder();
      send(chatId, 'Напоминание о дедлайнах опубликовано.');
      return true;

    case '/post_article':
      await postLatestArticle();
      send(chatId, 'Статья опубликована в канал (если есть неопубликованные).');
      return true;

    case '/post_lead':
      await postLeadMagnet();
      send(chatId, 'Лид-магнит опубликован.');
      return true;

    case '/post_custom':
      if (!args) {
        send(chatId, 'Использование: <code>/post_custom Текст поста</code>');
        return true;
      }
      await postToChannel(args, CHANNEL_CTA_KEYBOARD);
      send(chatId, 'Опубликовано в канал.');
      return true;

    case '/channel_stats':
      try {
        const r = await botRequest('getChatMemberCount', { chat_id: CHANNEL_ID });
        const count = r?.result || '?';
        send(chatId, `📊 Подписчиков в канале: <b>${count}</b>`);
      } catch {
        send(chatId, 'Не удалось получить статистику.');
      }
      return true;

    // ── Маркетинг-контент ──
    case '/draft':
    case '/today': {
      const post = await postDailyContent();
      if (!post) send(chatId, 'На сегодня постов нет. Все опубликованы.');
      return true;
    }

    case '/week': {
      const schedule = await marketing.getWeekSchedule();
      if (!schedule.length) {
        send(chatId, 'Расписание пусто. Контент закончился.');
        return true;
      }
      const lines = schedule.map(p => {
        const status = p.posted ? '✅' : '⏳';
        const typeShort = { pain: 'Боль', education: 'Обуч', case: 'Кейс', selling: 'Прод', engagement: 'Вовл' };
        return `${status} ${p.scheduled} [${typeShort[p.type] || p.type}] ${p.title}`;
      });
      send(chatId, `📅 <b>Расписание на неделю:</b>\n\n${lines.join('\n')}`);
      return true;
    }

    case '/mstats': {
      const stats = await marketing.getStats();
      send(chatId,
        `📊 <b>Маркетинг-статистика</b>\n\n` +
        `Всего постов: ${stats.total}\n` +
        `Опубликовано: ${stats.posted}\n` +
        `В очереди: ${stats.queued}`,
      );
      return true;
    }

    case '/admin_help':
      send(chatId,
        `🔧 <b>Админ-команды</b>\n\n` +
        `<b>Контент:</b>\n` +
        `/today — получить пост дня (в приватный канал)\n` +
        `/week — расписание на неделю\n` +
        `/mstats — статистика контента\n\n` +
        `<b>Публичный канал:</b>\n` +
        `/post_tip — налоговый совет\n` +
        `/post_lead — лид-магнит\n` +
        `/post_deadline — дедлайн\n` +
        `/post_article — статья из БД\n` +
        `/post_custom текст — свой пост\n` +
        `/channel_stats — подписчики\n`,
      );
      return true;

    default:
      return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SETUP — зарегистрировать webhook + команды
// ═══════════════════════════════════════════════════════════════════════════════

async function setupWebhook(baseUrl) {
  if (!TOKEN) return;
  const url = `${baseUrl}/api/bot/webhook`;
  const r = await botRequest('setWebhook', { url, allowed_updates: ['message', 'callback_query', 'channel_post'] });
  console.log('[bot] setWebhook:', r?.ok ? 'OK' : r?.description);

  // Start channel auto-posting scheduler
  startChannelScheduler();

  // Register command hints
  await botRequest('setMyCommands', {
    commands: [
      { command: 'calc',      description: 'Рассчитать налог 910' },
      { command: 'social',    description: 'Соцплатежи за себя' },
      { command: 'rates',     description: 'Актуальные ставки 2026' },
      { command: 'esp',       description: 'Расчёт ЕСП' },
      { command: 'self',      description: 'Налог самозанятого' },
      { command: 'deadlines', description: 'Сроки подачи и оплаты' },
      { command: 'status',    description: 'Статус и лимиты' },
      { command: 'link',      description: 'Привязать аккаунт Esep' },
      { command: 'help',      description: 'Список команд' },
    ],
  });
}

module.exports = {
  handleUpdate,
  notifyNewUser,
  notifyTaxCheck,
  notifyTaxAutoUpdate,
  sendMonthlyReminder,
  notifyArticleDraft,
  sendAdmin,
  setupWebhook,
  // Channel
  postToChannel,
  postTaxTip,
  postDeadlineReminder,
  postLatestArticle,
  postLeadMagnet,
  startChannelScheduler,
  // Private channel
  sendToPrivate,
  // Legacy compat
  handleCallback: (update) => handleUpdate(update),
  sendMessage: sendAdmin,
};
