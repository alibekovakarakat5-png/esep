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

const https = require('https');
const db    = require('../db');

const TOKEN    = process.env.TELEGRAM_BOT_TOKEN;
const ADMIN_ID = process.env.TELEGRAM_ADMIN_CHAT_ID;

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

// ═══════════════════════════════════════════════════════════════════════════════
// TAX DATA — загружаем из БД (tax_config)
// ═══════════════════════════════════════════════════════════════════════════════

async function getTaxConfig() {
  try {
    const { rows } = await db.query('SELECT key, value FROM tax_config');
    const cfg = {};
    for (const r of rows) cfg[r.key] = parseFloat(r.value) || r.value;
    return cfg;
  } catch {
    // Fallback if DB not ready
    return {
      mrp: 4325, mzp: 85000,
      ipn_rate_910: 0.015, sn_rate_910: 0.015,
      opv_rate: 0.10, opvr_rate: 0.035, so_rate: 0.05,
      vosms_rate_self: 0.05, vosms_base_mult: 1.4,
      esp_mrp_city_mult: 1, esp_mrp_rural_mult: 0.5,
      esp_year_mrp_limit: 1175,
      self_emp_rate: 0.04, self_emp_year_limit: 3528,
      '910_half_year_mrp': 24038,
    };
  }
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

async function handleStart(chatId, from) {
  send(chatId,
    `Привет, ${from.first_name || 'друг'}! Я — <b>Esep Bot</b> 🧮\n\n` +
    `Помогаю ИП Казахстана считать налоги и разбираться в ставках.\n\n` +
    `<b>Команды:</b>\n` +
    `/calc 5000000 — налог 910 за полугодие\n` +
    `/social — соцплатежи за себя (ежемесячно)\n` +
    `/rates — актуальные ставки 2026\n` +
    `/esp — расчёт ЕСП\n` +
    `/self 1000000 — налог самозанятого\n` +
    `/deadlines — сроки сдачи\n` +
    `/link email — привязать аккаунт Esep\n\n` +
    `Или просто спросите: <i>"сколько налогов с 3 млн?"</i>\n\n` +
    `Бесплатно: ${FREE_DAILY_LIMIT} запросов/день\n` +
    `Без ограничений: подключите платный тариф Esep`,
    {
      reply_markup: {
        inline_keyboard: [
          [{ text: '📲 Скачать Esep', url: 'https://github.com/alibekovakarakat5-png/esep/releases/latest/download/esep.apk' }],
          [{ text: '🧮 Калькулятор онлайн', url: 'https://esep.kz/calculator' }],
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
  const limit = c.mrp * c['910_half_year_mrp'];
  const ipn  = income * c.ipn_rate_910;
  const sn   = income * c.sn_rate_910;
  const total = ipn + sn;
  const rate  = (c.ipn_rate_910 + c.sn_rate_910) * 100;

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
    `<b>Налоги (${rate}%):</b>\n` +
    `  ИПН (1.5%): ${fmt(ipn)} ₸\n` +
    `  СН (1.5%): ${fmt(sn)} ₸\n` +
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
  );
}

async function handleRates(chatId) {
  const c = await getTaxConfig();
  const fmt = (n) => typeof n === 'number' ? n.toLocaleString('ru-RU') : n;

  send(chatId,
    `📊 <b>Актуальные ставки 2026</b>\n\n` +
    `🔹 МРП: <b>${fmt(c.mrp)} ₸</b>\n` +
    `🔹 МЗП: <b>${fmt(c.mzp)} ₸</b>\n\n` +
    `<b>Упрощёнка (910):</b>\n` +
    `  ИПН: ${c.ipn_rate_910 * 100}% | СН: ${c.sn_rate_910 * 100}%\n` +
    `  Итого: ${(c.ipn_rate_910 + c.sn_rate_910) * 100}%\n` +
    `  Лимит: ${fmt(c['910_half_year_mrp'])} МРП = ${fmt(Math.round(c.mrp * c['910_half_year_mrp']))} ₸/полугодие\n\n` +
    `<b>Соцплатежи "за себя":</b>\n` +
    `  ОПВ: ${c.opv_rate * 100}% | ОПВР: ${c.opvr_rate * 100}%\n` +
    `  СО: ${c.so_rate * 100}% | ВОСМС: ${c.vosms_rate_self * 100}%×${c.vosms_base_mult}МЗП\n\n` +
    `<b>Другие режимы:</b>\n` +
    `  ЕСП: ${fmt(c.esp_mrp_city_mult)} МРП/мес город, лимит ${fmt(c.esp_year_mrp_limit)} МРП/год\n` +
    `  Самозанятый: ${c.self_emp_rate * 100}%, лимит ${fmt(c.self_emp_year_limit)} МРП/год\n` +
    `  НДС: 12%, порог 20 000 МРП`,
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
    return send(chatId, 'Режим самозанятого: 4% от дохода, лимит 3 528 МРП/год.\nУкажите сумму: <code>/self 1000000</code>');
  }
  if (lower.includes('срок') || lower.includes('дедлайн') || lower.includes('когда сдавать')) {
    return handleDeadlines(chatId);
  }
  if (lower.includes('910') || lower.includes('упрощён') || lower.includes('упрощен')) {
    if (num) return handleCalc(chatId, String(num));
    return send(chatId, 'Упрощёнка (910): 3% от дохода (1.5% ИПН + 1.5% СН).\nУкажите сумму: <code>/calc 5000000</code>');
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

    const msg = update.message;
    if (!msg || !msg.text) return;

    const chatId = msg.chat.id;
    const text   = msg.text.trim();
    const from   = msg.from || {};

    // Commands
    if (text === '/start' || text.startsWith('/start ')) {
      return handleStart(chatId, from);
    }

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
              [{ text: '📲 Скачать Esep', url: 'https://github.com/alibekovakarakat5-png/esep/releases/latest/download/esep.apk' }],
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
      case '/help':      return handleStart(chatId, from);
      default:
        // Free text
        return handleFreeText(chatId, text);
    }
  } catch (err) {
    console.error('[bot] handleUpdate error:', err);
  }
}

// ── Callback queries ────────────────────────────────────────────────────────
function handleCallbackQuery(cb) {
  if (cb.data === 'tax_ok') {
    botRequest('answerCallbackQuery', {
      callback_query_id: cb.id,
      text: '✅ Отмечено — ставки актуальны',
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADMIN NOTIFICATIONS — уведомления разработчику
// ═══════════════════════════════════════════════════════════════════════════════

function notifyNewUser({ email, name }) {
  sendAdmin(
    `👤 <b>Регистрация в Esep</b>\n\nEmail: <code>${email}</code>\nИмя: ${name || '—'}`,
  );
}

function notifyTaxCheck({ mentions, adminUrl }) {
  const pass = process.env.ADMIN_PASSWORD ?? '';
  const url  = `${adminUrl}/api/admin?pass=${pass}#tax`;
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

function sendMonthlyReminder({ month, adminUrl }) {
  const pass = process.env.ADMIN_PASSWORD ?? '';
  const url  = `${adminUrl}/api/admin?pass=${pass}#tax`;
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

function notifyArticleDraft({ title, id, adminUrl }) {
  const pass = process.env.ADMIN_PASSWORD ?? '';
  const url  = `${adminUrl}/api/admin?pass=${pass}#articles`;
  sendAdmin(
    `✍️ <b>Новый черновик</b>\n\n«${title}»\n\n<a href="${url}">Открыть</a>`,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// SETUP — зарегистрировать webhook + команды
// ═══════════════════════════════════════════════════════════════════════════════

async function setupWebhook(baseUrl) {
  if (!TOKEN) return;
  const url = `${baseUrl}/api/bot/webhook`;
  const r = await botRequest('setWebhook', { url, allowed_updates: ['message', 'callback_query'] });
  console.log('[bot] setWebhook:', r?.ok ? 'OK' : r?.description);

  // Register command hints
  await botRequest('setMyCommands', {
    commands: [
      { command: 'calc',      description: 'Рассчитать налог 910' },
      { command: 'social',    description: 'Соцплатежи за себя' },
      { command: 'rates',     description: 'Актуальные ставки 2026' },
      { command: 'esp',       description: 'Расчёт ЕСП' },
      { command: 'self',      description: 'Налог самозанятого' },
      { command: 'deadlines', description: 'Сроки подачи и оплаты' },
      { command: 'link',      description: 'Привязать аккаунт Esep' },
      { command: 'help',      description: 'Помощь' },
    ],
  });
}

module.exports = {
  handleUpdate,
  notifyNewUser,
  notifyTaxCheck,
  sendMonthlyReminder,
  notifyArticleDraft,
  sendAdmin,
  setupWebhook,
  // Legacy compat
  handleCallback: (update) => handleUpdate(update),
  sendMessage: sendAdmin,
};
