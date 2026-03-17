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

    // Commands
    if (text === '/start' || text.startsWith('/start ')) {
      return handleStart(chatId, from);
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
async function handleCallbackQuery(cb) {
  const data = cb.data || '';

  if (data === 'tax_ok') {
    return botRequest('answerCallbackQuery', {
      callback_query_id: cb.id,
      text: '✅ Отмечено — ставки актуальны',
    });
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
// CHANNEL — автопостинг в @esepfinancialsupport
// ═══════════════════════════════════════════════════════════════════════════════

const CHANNEL_CTA_KEYBOARD = {
  reply_markup: {
    inline_keyboard: [
      [
        { text: '🧮 Калькулятор налогов', url: 'https://t.me/EsepKZ_bot' },
        { text: '📲 Скачать Esep', url: 'https://github.com/alibekovakarakat5-png/esep/releases/latest/download/esep.apk' },
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
    body: 'Каждый ИП на упрощёнке обязан платить ОПВ, ОПВР, СО и ВОСМС ежемесячно — даже если дохода нет. Итого ~21 525 тенге/мес в 2026.',
  },
  {
    title: 'Лимит по упрощёнке (910)',
    body: 'Максимальный доход — 24 038 МРП за полугодие (около 103.9 млн тенге). Превышение = переход на другой режим.',
  },
  {
    title: 'ОПВР — новый взнос',
    body: 'С 2024 ИП обязаны платить ОПВР (обязательные пенсионные взносы работодателя) за себя: 3.5% от МЗП = 2 975 тенге/мес.',
  },
  {
    title: 'Сравнение режимов',
    body: 'Упрощёнка (910): 3% от дохода + соцплатежи.\nЕСП: фиксированная сумма (1 МРП/мес), но лимит дохода ~5 млн/год.\nСамозанятый: 4%, но нет найма сотрудников.\n\nВыбирайте режим под свой масштаб!',
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
    body: 'Порог: оборот свыше 20 000 МРП за 12 мес = 86 500 000 тенге.\nПосле регистрации: +12% к цене, но можно зачитывать входящий НДС.',
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
    'ИПН + СН + все соцплатежи = точная сумма.',

    '📊 <b>Какой режим выгоднее?</b>\n\n' +
    'Упрощёнка, ЕСП или самозанятый? Зависит от дохода.\n' +
    'Бот @EsepKZ_bot сравнит все режимы за секунду.\n\n' +
    'Просто напишите: "сколько налогов с 3 млн?"',

    '💰 <b>Сколько реально платит ИП?</b>\n\n' +
    'Налог 3% — это не всё. Есть ОПВ, ОПВР, СО, ВОСМС — ещё ~21 500 тенге/мес.\n' +
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
