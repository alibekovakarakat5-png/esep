/**
 * Telegram Bot — Esep
 *
 * Пользователям: справка и предварительные расчёты по командам
 * Администратору: уведомления о регистрациях, налогах, статьях
 *
 * Переменные среды:
 *   TELEGRAM_BOT_TOKEN      — токен от @BotFather
 *   TELEGRAM_ADMIN_CHAT_ID  — chat_id разработчика
 *   TELEGRAM_WEBHOOK_SECRET — общий секрет webhook (32-256 символов)
 */

const db        = require('../db');
const marketing = require('./marketing');
const { escapeTelegramText, marketingPostHtml } = require('../services/telegram_text');
const { detectIntent } = require('../services/leads_db');
const { parseAmount, textCalculation } = require('./input');
const { createBotRequest, requireTelegramSuccess } = require('./transport');
const { createBotStore } = require('../services/bot_foundation');
const { validSecret } = require('../routes/telegram-webhook');
const ui = require('./ui');
const store = createBotStore(db);

const TOKEN      = process.env.TELEGRAM_BOT_TOKEN;
const ADMIN_ID   = process.env.TELEGRAM_ADMIN_CHAT_ID;
const CHANNEL_ID = process.env.TELEGRAM_CHANNEL_ID || '@esepfinancialsupport';
const PRIVATE_CHANNEL_ID = process.env.TELEGRAM_PRIVATE_CHANNEL_ID || null;

// ═══════════════════════════════════════════════════════════════════════════════
// CORE — Bot API
// ═══════════════════════════════════════════════════════════════════════════════

const botRequest = createBotRequest({ token: TOKEN });

async function send(chatId, text, extra = {}) {
  return requireTelegramSuccess(await botRequest('sendMessage', { chat_id: chatId, text, parse_mode: 'HTML', ...extra }));
}

function sendAdmin(text, extra = {}) {
  if (!ADMIN_ID) return Promise.resolve({ ok: false, error_code: 503 });
  // Ancillary admin notifications must not fail a successful user request.
  return send(ADMIN_ID, text, extra).catch(e => {
    console.error('[bot] admin notification failed', e.code);
    return { ok: false, error_code: e.telegramCode || 503 };
  });
}

async function postToChannel(text, extra = {}) {
  console.log(`[bot] postToChannel → ${CHANNEL_ID}`);
  const result = await send(CHANNEL_ID, text, extra);
  console.log('[bot] postToChannel OK');
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
    self_emp_rate: 0.04, self_emp_month_limit: 300,
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

function almatyDay() {
  return new Date(Date.now() + 5 * 3600e3).toISOString().slice(0, 10);
}
async function allowCalculation(chatId, updateId) {
  const account = await store.verifiedAccount(chatId);
  if (account && account.tier !== 'free') return true;
  if (await store.consumeQuota(chatId, updateId, FREE_DAILY_LIMIT, almatyDay())) return true;
  await send(chatId, '⏳ <b>Лимит расчётов на сегодня</b>\n\nДоступно 5 бесплатных расчётов в день. Можно вернуться завтра, открыть справку или привязать платный аккаунт Esep.', ui.inline([[{text:'Мой Esep',callback_data:'ui:account'},{text:'Справка',callback_data:'ui:reference'}]]));
  return false;
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
    if (p.startsWith('self_')) {
      const amount = p.replace('self_', '');
      return handleSelf(chatId, amount);
    }

    // Восстановление пароля: /start reset_<email> или /start reset
    if (p === 'reset' || p.startsWith('reset_') || p.startsWith('reset ')) {
      const email = payload.replace(/^reset[_\s]?/i, '').trim();
      return handleReset(chatId, email);
    }

    // Реклама бухфирмам: /start buh (из Instagram/Meta) → сразу оффер бухгалтерам
    if (p === 'buh' || p === 'buhgalter' || p === 'firma' || p === 'partner') {
      return sendBuhOffer(chatId, from);
    }
  }

  return sendView(chatId,ui.home(from.first_name));
}

// ── Оффер для бухгалтерских фирм (B2B-ветка) ─────────────────────────────────
// Вызывается из кнопки regime_buh и deep-link /start buh. НЕ трогает B2C-поток.
async function sendBuhOffer(chatId, from = {}) {
  await sendView(chatId,ui.accountant());

  await sendAdmin(
    '🧮 <b>Пользователь выбрал раздел для бухгалтеров</b>\n' +
    'Имя: ' + escapeTelegramText([from.first_name, from.last_name].filter(Boolean).join(' ')) + '\n' +
    'Username: @' + escapeTelegramText(from.username || '—') + '\n' +
    'Выбор раздела не означает заявку на демо.'
  );
}

// ── ROI-визард для бухфирм: 3 вопроса → выгода от автоматизации → демо ──
// Логика как на лендинге buhfirma: освобождённые часы + доп. ёмкость клиентов.
function roiStart(chatId) {
  return send(chatId,
    `📊 <b>Посчитаем вашу выгоду от Esep</b>\n\nОтветьте на 3 вопроса.\n\n<b>1/3.</b> Сколько бухгалтеров в фирме?`,
    { reply_markup: { inline_keyboard: [
      [{ text: '1', callback_data: 'roi:acc=1' }, { text: '2–3', callback_data: 'roi:acc=3' }],
      [{ text: '4–7', callback_data: 'roi:acc=5' }, { text: '8+', callback_data: 'roi:acc=8' }],
    ] } });
}
function roiAskClients(chatId, acc) {
  return send(chatId, `<b>2/3.</b> Клиентов на одного бухгалтера?`,
    { reply_markup: { inline_keyboard: [
      [{ text: 'до 10', callback_data: `roi:acc=${acc}:cpa=8` }, { text: '10–20', callback_data: `roi:acc=${acc}:cpa=15` }],
      [{ text: '20–40', callback_data: `roi:acc=${acc}:cpa=30` }, { text: '40+', callback_data: `roi:acc=${acc}:cpa=45` }],
    ] } });
}
function roiAskHours(chatId, acc, cpa) {
  return send(chatId, `<b>3/3.</b> Часов на одного клиента в месяц (учёт + отчётность)?`,
    { reply_markup: { inline_keyboard: [
      [{ text: '1–2 ч', callback_data: `roi:acc=${acc}:cpa=${cpa}:hrs=2` }, { text: '3–4 ч', callback_data: `roi:acc=${acc}:cpa=${cpa}:hrs=4` }],
      [{ text: '5+ ч', callback_data: `roi:acc=${acc}:cpa=${cpa}:hrs=6` }],
    ] } });
}
function roiResult(chatId, acc, cpa, hrs) {
  const f = (x) => Math.round(x).toLocaleString('ru-RU');
  const SHARE = 0.4, FEE = 20000; // доля автоматизируемой рутины; средний чек/клиент
  const total = acc * cpa;
  const hoursSaved = total * hrs * SHARE;
  const extra = Math.floor(total * SHARE);
  const rev = extra * FEE;
  return send(chatId,
    `📊 <b>Ваша выгода с Esep</b> (оценка по вашим ответам)\n\n` +
    `• Высвободится <b>~${f(hoursSaved)} ч/мес</b> рутины\n` +
    `• Это <b>+${f(extra)} клиентов</b> той же командой — без найма\n` +
    `• ≈ <b>+${f(rev)} ₸/мес</b> выручки (при среднем чеке 20 000 ₸/клиент)\n\n` +
    `Рутину (выписка → налог → формы, ЭСФ) Esep берёт на себя. Покажу на ваших клиентах за 15 минут — посчитаем точнее под вашу фирму 👇`,
    { reply_markup: { inline_keyboard: [
      [{ text: '💬 Записаться на демо', url: 'https://wa.me/77059914789' }],
      [{ text: '🌐 Подробнее', url: 'https://buhfirma.esepkz.com' }],
    ] } });
}
async function handleRoiStep(cb, data) {
  await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
  const chatId = cb.from.id;
  const p = {};
  data.replace(/^roi:/, '').split(':').forEach((kv) => { const [k, v] = kv.split('='); if (k) p[k] = v; });
  if (p.hrs !== undefined) return roiResult(chatId, +p.acc, +p.cpa, +p.hrs);
  if (p.cpa !== undefined) return roiAskHours(chatId, +p.acc, +p.cpa);
  if (p.acc !== undefined) return roiAskClients(chatId, +p.acc);
  return roiStart(chatId);
}

// ── /salary — расчёт зарплаты сотрудника (НК-2026).
// Логика 1:1 из lib/.../salary_calculator_screen.dart (выверенный источник).
function handleSalary(chatId, args) {
  const gross = parseAmount(args);
  if (!gross || gross <= 0) {
    return sendView(chatId,ui.prompt('salary',Boolean(args)));
  }
  const MZP = 85000, MRP = 4325; // НК-2026, см. kz_tax_constants.dart
  const f = (x) => Math.round(x).toLocaleString('ru-RU');
  // Удержания с сотрудника
  const opv = Math.min(gross, MZP * 50) * 0.10;
  const ipnBase = Math.max(0, gross - opv - 30 * MRP);
  const ipn = ipnBase * 0.10;
  const vosmsEe = Math.min(gross, MZP * 20) * 0.02;
  const deductions = opv + ipn + vosmsEe;
  const net = gross - deductions;
  // Расходы работодателя (сверху)
  const so = Math.max(MZP, Math.min(gross - opv, MZP * 7)) * 0.05;
  const opvr = Math.min(gross, MZP * 50) * 0.035;
  const oosms = Math.min(gross, MZP * 40) * 0.03;
  const empCosts = so + opvr + oosms;
  const totalCost = gross + empCosts;
  return send(chatId,
    `💼 <b>Расчёт зарплаты</b> (НК 2026)\n` +
    `Начислено (gross): <b>${f(gross)} ₸</b>\n\n` +
    `<b>Удержания с сотрудника:</b>\n` +
    `• ОПВ 10%: ${f(opv)} ₸\n` +
    `• ИПН 10%: ${f(ipn)} ₸ <i>(база: ЗП − ОПВ − 30 МРП)</i>\n` +
    `• ВОСМС 2%: ${f(vosmsEe)} ₸\n` +
    `  Итого удержано: ${f(deductions)} ₸\n\n` +
    `💰 <b>На руки: ${f(net)} ₸</b>\n\n` +
    `<b>Платит работодатель сверху:</b>\n` +
    `• СО 5%: ${f(so)} ₸\n` +
    `• ОПВР 3.5%: ${f(opvr)} ₸\n` +
    `• ООСМС 3%: ${f(oosms)} ₸\n` +
    `  Итого взносов: ${f(empCosts)} ₸\n\n` +
    `🏢 <b>Стоимость для работодателя: ${f(totalCost)} ₸</b>\n\n` +
    `<i>ОПВР не начисляется на пенсионеров (рожд. до 1975). Для дохода свыше 8500 МРП/год ИПН — 15%.</i>\n` +
    `Предварительный расчёт по настройкам бота.`,
    ui.inline([[{text:'Другая зарплата',callback_data:'prompt_salary'},{text:'Другой расчёт',callback_data:'ui:calculators'}]]));
}

async function handleCalc(chatId, args) {
  const income = parseAmount(args);
  if (!income || income <= 0) {
    return sendView(chatId,ui.prompt('calc',Boolean(args)));
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

  return send(chatId,
    '🧮 <b>Расчёт по упрощёнке (910)</b>\n' +
    'Доход за полугодие: <b>' + fmt(income) + ' ₸</b>\n\n' +
    '<b>Налоги (' + rate + '): ' + fmt(total) + ' ₸</b>\n' +
    'ИПН: ' + fmt(ipn) + ' ₸ · СН: ' + fmt(sn) + ' ₸\n\n' +
    '<b>Соцплатежи за 6 месяцев: ' + fmt(social6) + ' ₸</b>\n' +
    'В месяц: ОПВ ' + fmt(opv) + ' · ОПВР ' + fmt(opvr) + '\n' +
    'СО ' + fmt(so) + ' · ВОСМС ' + fmt(vosms) + ' ₸\n\n' +
    '💰 <b>Общий итог: ' + fmt(grand) + ' ₸</b>' + warn +
    '\n\nПредварительный расчёт по настройкам бота. Соцплатежи — по минимальной базе. Можно ввести другую сумму.',
    ui.inline([
      [{text:'Другая сумма',callback_data:'prompt_calc'},{text:'Другой расчёт',callback_data:'ui:calculators'}],
      [{text:'Разбивка по месяцам',callback_data:'monthly_'+Math.round(income)},{text:'Сроки',callback_data:'go_deadlines'}],
    ]));
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

  return send(chatId,
    `📋 <b>Ежемесячные соцплатежи ИП "за себя"</b>\n` +
    `(база: 1 МЗП = ${fmt(c.mzp)} ₸)\n\n` +
    `  ОПВ 10%: <b>${fmt(opv)} ₸</b>\n` +
    `  ОПВР 3.5%: <b>${fmt(opvr)} ₸</b>\n` +
    `  СО 5%: <b>${fmt(so)} ₸</b>\n` +
    `  ВОСМС 5%×1.4МЗП: <b>${fmt(vosms)} ₸</b>\n\n` +
    `💰 <b>Итого: ${fmt(total)} ₸/мес</b>\n` +
    `  (без ОПВР, до 1975 г.р.: ${fmt(totalNoOpvr)} ₸)\n\n` +
    `📅 Срок оплаты: до 25 числа следующего месяца`,
    ui.inline([[{text:'Другой расчёт',callback_data:'ui:calculators'},{text:'Сроки',callback_data:'go_deadlines'}]]),
  );
}

async function handleRates(chatId) {
  const c = await getTaxConfig();
  const fmt = (n) => typeof n === 'number' ? n.toLocaleString('ru-RU') : n;
  const halfYearLimitMrp = (c['910_year_mrp'] ?? 600000) / 2;

  return send(chatId,
    `📊 <b>Параметры расчётов · 2026</b>\n\n` +
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
    `  Самозанятый: ${formatRate(c.self_emp_rate)}, лимит ${fmt(c.self_emp_month_limit)} МРП/мес\n` +
    `  НДС: ${formatRate(c.vat_rate)}, порог ${fmt(c.vat_threshold_mrp)} МРП`,
    ui.inline([[{text:'К расчётам',callback_data:'ui:calculators'},{text:'Справка',callback_data:'ui:reference'}]]),
  );
}

async function handleSelf(chatId, args) {
  const income = parseAmount(args);
  if (!income || income <= 0) {
    return sendView(chatId,ui.prompt('self',Boolean(args)));
  }
  const c = await getTaxConfig();
  const tax   = income * c.self_emp_rate;
  const limit = c.mrp * c.self_emp_month_limit;
  const fmt = (n) => Math.round(n).toLocaleString('ru-RU');
  const warn = income > limit
    ? `\n\n⚠️ Доход за месяц превышает лимит (${fmt(limit)} ₸/мес)`
    : '';

  return send(chatId,
    `👤 <b>Режим самозанятого</b>\n\n` +
    `Доход/мес: <b>${fmt(income)} ₸</b>\n` +
    `Ставка: ${c.self_emp_rate * 100}%\n` +
    `Налог: <b>${fmt(tax)} ₸</b>\n\n` +
    `Лимит: ${fmt(limit)} ₸/мес (${c.self_emp_month_limit} МРП/мес)` + warn,
    ui.inline([[{text:'Другая сумма',callback_data:'prompt_self'},{text:'Другой расчёт',callback_data:'ui:calculators'}]]),
  );
}

async function handleDeadlines(chatId) {
  const user=await getUserState(chatId);
  return send(chatId,
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
    {
      ...ui.inline([[{text:user.reminders_on?'🔕 Выключить напоминания':'🔔 Напоминать мне о сроках',callback_data:user.reminders_on?'remind_off':'remind_on'}]]),
    },
  );
}

async function handleStatus(chatId) {
  const user = await getUserState(chatId);
  const today = almatyDay();

  // Queries remaining
  let queriesUsed = 0;
  if (user.last_query_date === today) {
    queriesUsed = user.queries_today || 0;
  }
  const remaining = Math.max(0, FREE_DAILY_LIMIT - queriesUsed);

  // Linked account info
  let accountLine = 'Аккаунт Esep: <b>не привязан</b>';
  let tierLine = 'Тариф: Бесплатный';
  let unlimited = false;

  const account = await store.verifiedAccount(chatId);
  if (account) {
    accountLine = 'Аккаунт: <b>' + escapeTelegramText(account.email) + '</b>';
    const tierLabel = {free:'Бесплатный',ip:'ИП',accountant:'Бухгалтер',corporate:'Корпоративный'};
    tierLine = 'Тариф: <b>' + escapeTelegramText(tierLabel[account.tier] || account.tier) + '</b>';
    unlimited = account.tier !== 'free';
  }


  const limitLine = unlimited
    ? 'Расчёты: <b>безлимит</b>'
    : `Расчётов осталось сегодня: <b>${remaining} из ${FREE_DAILY_LIMIT}</b>`;

  return send(chatId,
    `📊 <b>Ваш статус</b>\n\n` +
    `${limitLine}\n` +
    `${accountLine}\n` +
    `${tierLine}\n\n` +
    (unlimited ? '' : 'Для безлимита можно привязать платный аккаунт Esep.'),
    ui.inline([[{text:account?'Открыть кабинет':'Привязать аккаунт',...(account?{url:'https://app.esepkz.com'}:{callback_data:'ui:link'})}],[{text:user.reminders_on?'🔕 Выключить напоминания':'🔔 Включить напоминания',callback_data:user.reminders_on?'remind_off':'remind_on'}]]),
  );
}

function sendView(chatId,view) { return send(chatId,view.text,view.extra); }
function handleHelp(chatId) { return sendView(chatId,ui.home()); }
function handleNavigation(chatId,action,from={}) {
  if(action==='menu')return sendView(chatId,ui.home(from.first_name));
  if(action==='deadlines')return handleDeadlines(chatId);
  if(action==='account')return handleStatus(chatId);
  if(action==='accountant')return sendBuhOffer(chatId,from);
  if(action==='link')return handleLink(chatId);
  const views={calculators:ui.calculators,reference:ui.reference,help:ui.help,commands:ui.commands,support:ui.support,form910:ui.form910};
  return sendView(chatId,(views[action]||ui.home)());
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
//   - Токен, привязка и журнал изменяются атомарно в одной транзакции.
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

    const safeEmail = escapeTelegramText(row.email);
    const safeName = escapeTelegramText(row.name);

    return send(chatId,
      `🔐 <b>Привязка Telegram к Esep</b>\n\n` +
      `Кто-то запросил привязать <b>этот Telegram</b> к аккаунту:\n\n` +
      `📧 ${safeEmail}\n` +
      (safeName ? `👤 ${safeName}\n` : '') +
      `\n<b>Это вы?</b>\n\n` +
      `Если этот аккаунт ваш — нажмите "Это я". Если нет — нажмите "Это не я", ` +
      `и мы ничего не привяжем.\n\n` +
      `<i>Подтверждайте только свой аккаунт.</i>`,
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
    console.error('[bot/bind] failed:', err.code || 'FAILED');
    return send(chatId, '❌ Ошибка привязки. Попробуйте снова.');
  }
}

async function handleBindConfirm(cb, token) {
  const account = await store.confirmBinding(token, cb.from.id, cb.from.username);
  await botRequest('answerCallbackQuery', {callback_query_id:cb.id,
    text:account ? '✅ Привязано!' : 'Ссылка недействительна или использована'});
  return send(cb.from.id, account
    ? '✅ <b>Telegram привязан к аккаунту Esep</b>\n' + escapeTelegramText(account.email) +
      '\nОтвязать его можно в настройках Esep.'
    : 'Ссылка недействительна, просрочена или уже использована. Запросите новую ссылку в настройках Esep.');
}

async function handleBindReject(cb, token) {
  const chatId = cb.from.id;
  try {
    // Do not rewrite an already consumed token, including after a successful bind.
    const r = await db.query(
      `UPDATE telegram_bind_token
          SET expires_at = NOW(),
              consumed_at = NOW(),
              consumed_chat_id = $1
        WHERE token = $2 AND consumed_at IS NULL AND expires_at > NOW()
        RETURNING user_id`,
      [String(chatId), token]
    );
    const userId = r.rows[0]?.user_id || null;
    if (!userId) return send(chatId, 'Ссылка недействительна или уже использована. Существующая привязка не изменена.');

    if (userId) {
      await db.query(
        `INSERT INTO auth_security_log (user_id, event, meta)
         VALUES ($1, 'tg_bind_rejected', $2::jsonb)`,
        [userId, JSON.stringify({ chat_id: String(chatId) })]
      );
    }

    await botRequest('answerCallbackQuery',
      { callback_query_id: cb.id, text: '🛡 Отклонено' });
    return send(chatId,
      `🛡 <b>Привязка отклонена.</b>\n\n` +
      `Никаких аккаунтов мы к вашему Telegram не привязали.\n\n` +
      `Если кто-то прислал вам эту ссылку — будьте осторожны, возможно это ` +
      `попытка получить доступ к чужому аккаунту.`
    );
  } catch (err) {
    console.error('[bot/bind-reject] failed:', err.code || 'FAILED');
    await botRequest('answerCallbackQuery',
      { callback_query_id: cb.id, text: '❌ Ошибка' });
  }
}

// Legacy password mutation is disabled until a complete verified recovery flow exists.
function handleReset(chatId) {
  return send(chatId, 'Восстановление пароля через бота временно отключено. ' +
    'Если вы вошли в Esep, смените пароль в настройках. Если войти не получается, обратитесь в поддержку.',
    ui.inline([[{text:'Связаться с поддержкой',url:'https://wa.me/77059914789'}]]));
}
function handleLink(chatId) {
  return send(chatId, '🔗 Для безопасной привязки войдите в Esep → Настройки → Telegram. ' +
    'Откройте одноразовую ссылку и подтвердите свой аккаунт. Указывать email в чате не нужно.',
    ui.inline([[{text:'Открыть Esep',url:'https://app.esepkz.com'}]]));
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMART TEXT — обработка свободного текста (вопросы про налоги)
// ═══════════════════════════════════════════════════════════════════════════════

async function handleFreeText(chatId, text, calculation) {
  const lower = text.toLowerCase();
  if (calculation) {
    const handlers = {calc:handleCalc,self:handleSelf,salary:handleSalary};
    return handlers[calculation.kind](chatId,String(calculation.amount));
  }
  if (lower.includes('соцплатеж') || lower.includes('опв') || lower.includes('за себя')) return handleSocial(chatId);
  if (lower.includes('ставк') || lower.includes('мрп') || lower.includes('мзп')) return handleRates(chatId);
  if (lower.includes('срок') || lower.includes('дедлайн') || lower.includes('когда сдавать')) return handleDeadlines(chatId);
  if (lower.includes('910') || lower.includes('упрощ')) return sendView(chatId,ui.form910());
  const selected=await store.calculationKind(chatId);
  if(selected)return sendView(chatId,ui.prompt(selected,true));
  if(/^(привет|здравствуйте|добрый день|спасибо)[!.\s]*$/u.test(lower))return handleHelp(chatId);
  return send(chatId,'Давайте выберем задачу — так я подскажу, что ввести дальше.',ui.inline([[{text:'🧮 Рассчитать',callback_data:'ui:calculators'},{text:'📚 Справка',callback_data:'ui:reference'}]]));
}

// ═══════════════════════════════════════════════════════════════════════════════
// WEBHOOK — главный обработчик входящих обновлений
// ═══════════════════════════════════════════════════════════════════════════════

async function handleUpdate(update) {
  const cb = update.callback_query;
  // Authorize privileged callbacks before tracking or any database mutation.
  if (cb && /^(?:tax_|pub_channel_|skip_post_)/.test(cb.data || '')) {
    if (!ADMIN_ID || String(cb.from?.id) !== String(ADMIN_ID)) {
      return botRequest('answerCallbackQuery',{callback_query_id:cb.id,text:'Это действие доступно только администратору.'});
    }
    return handleCallbackQuery(cb);
  }
  const msg = cb?.message || update.message;
  const from = cb?.from || msg?.from;
  if (!msg || msg.chat?.type !== 'private' || !from || from.is_bot || String(msg.chat.id) !== String(from.id)) return;
  const chatId = msg.chat.id;
  const text = typeof msg.text === 'string' && !cb ? msg.text.trim() : '';
  const commandToken = text.split(/\s+/)[0];
  const cmd = commandToken.toLowerCase().replace(/@\w+$/, '');
  const args = text.slice(commandToken.length).trim();
  const payload = cmd === '/start' ? args : undefined;
  const navigation = ui.textAction(text);
  const b2b = cb?.data === 'regime_buh' || cb?.data === 'ui:accountant' || navigation === 'accountant' || (cmd === '/start' && /^(buh|buhgalter|firma|partner)$/i.test(args));
  const intent = b2b ? 'b2b' : detectIntent(cb?.data || text);
  const visitor = await store.trackVisitor(chatId,from,payload,intent);
  if (visitor.isNew && String(chatId) !== String(ADMIN_ID)) {
    await sendAdmin('🤖 <b>Новый пользователь бота</b>\nИмя: ' +
      escapeTelegramText([from.first_name,from.last_name].filter(Boolean).join(' ')) +
      '\nUsername: @' + escapeTelegramText(from.username || '—') + '\nChat ID: <code>' + chatId + '</code>');
  }
  const explicitKind = ({'/calc':'calc','/self':'self','/salary':'salary'})[cmd];
  const startMatch=cmd==='/start'&&args.match(/^(calc|self)_(.+)$/i);
  const sample=cb?.data?.match(/^run_(calc|self|salary)_(\d+)$/);
  const promptKind=({'prompt_calc':'calc','prompt_self':'self','prompt_salary':'salary'})[cb?.data];
  let freeCalc=text&&!cmd.startsWith('/')&&!navigation?textCalculation(text):null;
  if(freeCalc&&parseAmount(text)!==null){
    const kind=await store.resolveCalculationKind(chatId,update.update_id);
    if(kind==='expired')return send(chatId,'Прошло больше 30 минут. Выберите расчёт ещё раз, чтобы я верно понял сумму.',ui.inline([[{text:'Выбрать расчёт',callback_data:'ui:calculators'}]]));
    freeCalc.kind=kind;
  }
  const wordPrompt=!cb&&!navigation&&!cmd.startsWith('/')&&!freeCalc&&
    (/самозанят/u.test(text.toLowerCase())?'self':/зарплат/u.test(text.toLowerCase())?'salary':null);
  const selectedKind=explicitKind||promptKind||sample?.[1]||startMatch?.[1]?.toLowerCase()||freeCalc?.kind||wordPrompt;
  const directCalc = explicitKind && parseAmount(args) !== null;
  const startCalc = startMatch && parseAmount(startMatch[2]) !== null;
  const buttonCalc = cb && (sample&&parseAmount(sample[2])!==null || /^demo_(calc|self)_/.test(cb.data) || /^monthly_/.test(cb.data));
  if ((directCalc || startCalc || buttonCalc || freeCalc) && !await allowCalculation(chatId,update.update_id)) {
    if(cb)await botRequest('answerCallbackQuery',{callback_query_id:cb.id,text:'Лимит расчётов на сегодня исчерпан.'});
    return;
  }
  const demoKind=cb?.data==='demo_calc_5000000'?'calc':cb?.data==='demo_self_1000000'?'self':null;
  if(selectedKind||demoKind)await store.setCalculationKind(chatId,selectedKind||demoKind,update.update_id);
  else if(cb||navigation||['/start','/help','/menu','/cancel','/status','/social','/rates','/deadlines','/link','/reset'].includes(cmd))await store.setCalculationKind(chatId,null,update.update_id);
  if (cb) {
    if(sample&&parseAmount(sample[2])!==null){await botRequest('answerCallbackQuery',{callback_query_id:cb.id});return ({calc:handleCalc,self:handleSelf,salary:handleSalary})[sample[1]](chatId,sample[2]);}
    return handleCallbackQuery(cb);
  }
  if (!text) return send(chatId,'Фото, документы и голосовые сообщения бот пока не разбирает. Выберите задачу ниже или введите сумму текстом.',ui.inline([[{text:'Выбрать расчёт',callback_data:'ui:calculators'}]]));
  if(navigation)return handleNavigation(chatId,navigation,from);
  if(wordPrompt)return sendView(chatId,ui.prompt(wordPrompt));
  if (await handleAdminChannelCommand(chatId,cmd,args)) return;
  switch (cmd) {
    case '/start': return handleStart(chatId,from,args);
    case '/help': case '/menu': case '/cancel': return handleHelp(chatId);
    case '/status': return handleStatus(chatId);
    case '/calc': return handleCalc(chatId,args);
    case '/self': return handleSelf(chatId,args);
    case '/salary': return handleSalary(chatId,args);
    case '/social': return handleSocial(chatId);
    case '/rates': return handleRates(chatId);
    case '/deadlines': return handleDeadlines(chatId);
    case '/link': return handleLink(chatId);
    case '/reset': return handleReset(chatId);
    default: return handleFreeText(chatId,text,freeCalc);
  }
}

// ── Визард «не знаю свой режим»: 3 вопроса → режим + расчёт + гайд по выписке ──
function startRegimeQuiz(chatId) {
  return send(chatId,
    `❓ <b>Не знаете свой режим?</b> Ответьте на 3 вопроса — подскажу.\n\n<b>1/3.</b> Вы оформили ИП?`,
    { reply_markup: { inline_keyboard: [
      [{ text: '✅ Да, ИП оформлено', callback_data: 'quiz:ip=1' }],
      [{ text: '🙅 Нет, работаю без ИП', callback_data: 'quiz:ip=0' }],
    ] } });
}
function quizAskIncome(chatId, ip) {
  return send(chatId, `<b>2/3.</b> Доход примерно в месяц?`,
    { reply_markup: { inline_keyboard: [
      [{ text: 'До 1,3 млн ₸', callback_data: `quiz:ip=${ip}:inc=low` }],
      [{ text: '1,3 – 3,6 млн ₸', callback_data: `quiz:ip=${ip}:inc=mid` }],
      [{ text: 'Больше 3,6 млн ₸', callback_data: `quiz:ip=${ip}:inc=high` }],
    ] } });
}
function quizAskEmployees(chatId, ip, inc) {
  return send(chatId, `<b>3/3.</b> Есть наёмные сотрудники?`,
    { reply_markup: { inline_keyboard: [
      [{ text: '👤 Нет, работаю один', callback_data: `quiz:ip=${ip}:inc=${inc}:emp=0` }],
      [{ text: '👥 Есть сотрудники', callback_data: `quiz:ip=${ip}:inc=${inc}:emp=1` }],
    ] } });
}
function regimeResult(chatId, ip, inc, emp) {
  let title, body;
  if (ip === '0' && inc === 'low' && emp === '0') {
    title = '👤 Вам подходит САМОЗАНЯТЫЙ';
    body = `Налог <b>4%</b> от дохода, <b>без деклараций</b>, регистрация в e-Salyq Business. ` +
      `Лимит 300 МРП/мес (~1,3 млн ₸), без сотрудников.\n\nРасчёт: /self`;
  } else if (inc === 'high' || (ip === '0' && (inc === 'mid' || emp === '1'))) {
    title = '🏢 У вас, скорее всего, ОУР (общий режим)';
    body = `Доход в зоне НДС/общего режима — сложнее (ИПН 10%, возможно НДС 16%). ` +
      `Лучше разобрать индивидуально — мы поможем. Прикинуть: /calc`;
  } else {
    title = '📋 Ваш режим — УПРОЩЁНКА (форма 910)';
    body = `Налог <b>4%</b> от дохода + соцплатежи «за себя» ~21 675 ₸/мес. Декларация 910 — раз в полгода.` +
      (emp === '1' ? ` С сотрудниками — ещё форма 200 ежеквартально.` : '') +
      `\n\nНапишите доход (например, <code>5000000</code>) — посчитаю точно.`;
  }
  return send(chatId, `${title}\n\n${body}`,
    { reply_markup: { inline_keyboard: [
      [{ text: '📎 Как выгрузить выписку Kaspi', callback_data: 'kaspi_guide' }],
      [{ text: '✨ Попробовать Esep бесплатно', url: 'https://app.esepkz.com' }],
      [{ text: '🔔 Напоминать о сроках', callback_data: 'remind_on' }],
    ] } });
}
async function handleQuizStep(cb, data) {
  await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
  const chatId = cb.from.id;
  const p = {};
  data.replace(/^quiz:/, '').split(':').forEach((kv) => { const [k, v] = kv.split('='); if (k) p[k] = v; });
  if (p.emp !== undefined) return regimeResult(chatId, p.ip, p.inc, p.emp);
  if (p.inc !== undefined) return quizAskEmployees(chatId, p.ip, p.inc);
  if (p.ip !== undefined) return quizAskIncome(chatId, p.ip);
  return startRegimeQuiz(chatId);
}
function sendKaspiGuide(chatId) {
  return send(chatId,
    `📎 <b>Как выгрузить выписку — за 1 минуту</b>\n\n` +
    `<b>Kaspi (счёт ИП):</b>\n1. Приложение Kaspi → «Мой банк» → счёт\n` +
    `2. «Выписка» → период (за полугодие)\n3. Формат <b>Excel</b> → сохранить\n\n` +
    `<b>Kaspi Business:</b> kaspi.kz/pay → Счета → Выписка → Excel\n` +
    `<b>Halyk / Forte:</b> онлайн-банк → Счета → Выписка → XLS\n\n` +
    `Готовый файл загрузите в Esep или пришлите нам — посчитаем сами. Не получается? Поможем 👇`,
    { reply_markup: { inline_keyboard: [
      [{ text: '💬 Помочь с выпиской', url: 'https://wa.me/77059914789' }],
      [{ text: '✨ Открыть Esep', url: 'https://app.esepkz.com' }],
    ] } });
}

// ── Callback queries ────────────────────────────────────────────────────────
async function handleCallbackQuery(cb) {
  const data = cb.data || '';
  if (data.startsWith('quiz:')) return handleQuizStep(cb, data);
  if (data.startsWith('roi:')) return handleRoiStep(cb, data);

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
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: '✅ Подтверждено!' });
    if (cb.message) {
      await botRequest('editMessageReplyMarkup', {
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
      await botRequest('answerCallbackQuery', {
        callback_query_id: cb.id,
        text: result.ok ? '↩️ Откат выполнен!' : result.error,
      });
      if (cb.message && result.ok) {
        await botRequest('editMessageReplyMarkup', {
          chat_id: cb.message.chat.id,
          message_id: cb.message.message_id,
          reply_markup: { inline_keyboard: [[{ text: '↩️ Откачено', callback_data: 'noop' }]] },
        });
      }
    } catch (err) {
      console.error('[bot] tax_auto_revert error:', err.message);
      await botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: 'Ошибка отката' });
    }
    return;
  }

  // Publish post from private channel → public channel
  if (data.startsWith('pub_channel_')) {
    const postId = parseInt(data.replace('pub_channel_', ''));
    try {
      if (!Number.isSafeInteger(postId) || postId <= 0) return;
      const status = await store.publishPost(postId, post => postToChannel(marketingPostHtml(post), CHANNEL_CTA_KEYBOARD));
      if (status !== 'posted') {
        return botRequest('answerCallbackQuery', { callback_query_id: cb.id,
          text: status === 'missing' ? 'Пост не найден' : 'Уже опубликован или пропущен' });
      }
      await botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: '✅ Опубликовано в канал!' });
      // Update the message in private channel
      if (cb.message) {
        await botRequest('editMessageReplyMarkup', {
          chat_id: cb.message.chat.id,
          message_id: cb.message.message_id,
          reply_markup: { inline_keyboard: [[{ text: '✅ Опубликовано', callback_data: 'noop' }]] },
        });
      }
    } catch (err) {
      console.error('[bot] pub_channel error:', err.message);
      await botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: 'Ошибка публикации' });
    }
    return;
  }

  // Skip post
  if (data.startsWith('skip_post_')) {
    const postId = parseInt(data.replace('skip_post_', ''));
    await marketing.markPosted(postId);
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: '⏭ Пропущено' });
    if (cb.message) {
      await botRequest('editMessageReplyMarkup', {
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

  if(data.startsWith('ui:')){
    await botRequest('answerCallbackQuery',{callback_query_id:cb.id});
    return handleNavigation(chatId,data.slice(3),cb.from);
  }

  // ── Inline keyboards after calculations ──

  // Monthly breakdown: monthly_{income}
  if (data.startsWith('monthly_')) {
    const income = parseAmount(data.replace('monthly_', ''));
    if (!income) return;
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });

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
      ui.inline([[{text:'Другая сумма',callback_data:'prompt_calc'},{text:'Сроки',callback_data:'go_deadlines'}]]),
    );
  }

  // Navigation callbacks
  if (data === 'go_social') {
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return handleSocial(chatId);
  }
  if (data === 'go_deadlines') {
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return handleDeadlines(chatId);
  }
  if (data === 'remind_on' || data === 'remind_off') {
    const on = data === 'remind_on';
    try {
      await db.query(
        `INSERT INTO bot_users (chat_id, reminders_on) VALUES ($1, $2)
         ON CONFLICT (chat_id) DO UPDATE SET reminders_on = $2`,
        [String(cb.from.id), on],
      );
    } catch (e) { return send(cb.from.id,'Не удалось сохранить настройку напоминаний. Попробуйте ещё раз.'); }
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id, text: on ? '🔔 Напоминания включены' : 'Выключено' });
    return send(cb.from.id,on?'🔔 Напоминания включены. Настройку можно изменить в «Мой Esep».':'🔕 Напоминания выключены.',
      ui.inline([[{text:on?'Выключить напоминания':'Включить напоминания',callback_data:on?'remind_off':'remind_on'}]]));
  }
  if (data === 'go_rates') {
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return handleRates(chatId);
  }
  if (['prompt_calc','prompt_self','prompt_salary'].includes(data)) {
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return sendView(chatId,ui.prompt(data.slice(7)));
  }
  if (data === 'show_help') {
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return handleHelp(chatId);
  }

  // ── Welcome series: regime selection ──

  if (data === 'regime_910') {
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
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

  if (data === 'regime_self') {
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return send(chatId,
      `👤 <b>Режим самозанятого</b>\n\n` +
      `Минимум бюрократии, без регистрации ИП.\n\n` +
      `<b>Ставка:</b> 4% от дохода (ИПН 0% + ОПВ/ОПВР/СО/ОСМС по 1%)\n` +
      `<b>Лимит:</b> 300 МРП/мес (≈1,3 млн ₸)\n` +
      `<b>Нельзя:</b> нанимать сотрудников\n` +
      `<b>Оплата:</b> через приложение E-Salyq Business\n\n` +
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
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
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
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return startRegimeQuiz(chatId);
  }
  if (data === 'kaspi_guide') {
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return sendKaspiGuide(chatId);
  }

  // Demo calculations use the same quota as command and deep-link calculations.
  if (data === 'demo_calc_5000000') {
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return handleCalc(chatId, '5000000');
  }
  if (data === 'demo_self_1000000') {
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return handleSelf(chatId, '1000000');
  }

  // B2B-ветка: бухгалтер выбрал «веду клиентов» в приветствии
  if (data === 'regime_buh') {
    await botRequest('answerCallbackQuery', { callback_query_id: cb.id });
    return sendBuhOffer(chatId, cb.from || {});
  }
  await botRequest('answerCallbackQuery',{callback_query_id:cb.id,text:'Откройте меню для выбора действия.'});
  return handleHelp(chatId);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADMIN NOTIFICATIONS — уведомления разработчику
// ═══════════════════════════════════════════════════════════════════════════════

/** Generate an admin link. Login is handled by /api/admin/login cookie flow. */
function adminLink(adminUrl, hash) {
  return `${adminUrl}/api/admin#${hash}`;
}

function notifyNewUser({ email, name, phone }) {
  // Распознаём ИП по префиксу в имени
  const isIP = /^ИП\b|^IP\b/i.test((name || '').trim());
  const role = isIP ? '🏢 ИП' : '👤 Физлицо';

  let msg = `${role} <b>Новая регистрация в Esep</b>\n\n`;
  msg += `📧 Email: <code>${email}</code>\n`;
  msg += `👋 Имя: ${name || '—'}\n`;
  if (phone) {
    msg += `📞 Телефон: <code>${phone}</code>`;
    // Для удобной связи через WhatsApp/Telegram добавим кликабельную ссылку
    const waNum = phone.replace(/\D/g, '');
    msg += `\n💬 <a href="https://wa.me/${waNum}">WhatsApp</a> · <a href="tg://resolve?phone=${waNum}">Telegram</a>`;
  } else {
    msg += `📞 Телефон: <i>не указан</i>`;
  }

  sendAdmin(msg, { parse_mode: 'HTML', disable_web_page_preview: true });
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
        { text: '🌐 Открыть Esep', url: 'https://esepkz.com' },
        { text: '🧮 Калькулятор', url: 'https://t.me/EsepKZ_bot' },
      ],
      [
        { text: '💬 Консультация', url: 'https://wa.me/77059914789' },
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
    body: 'Упрощёнка (910): 4% от дохода + соцплатежи.\nСамозанятый: 4% (ИПН 0%), лимит 300 МРП/мес, без найма сотрудников.\nОУР: 10% ИПН с прибыли, без лимита дохода.\n\nВыбирайте режим под свой масштаб!',
  },
  {
    title: 'Срок подачи 910.00',
    body: '1-е полугодие (янв—июн): подача до 15 августа, оплата до 25 августа.\n2-е полугодие (июл—дек): подача до 15 февраля, оплата до 25 февраля.\n\nНе пропустите!',
  },
  {
    title: 'Режим самозанятых с 2026',
    body: 'С 2026 года патент и ЕСП отменены — вместо них режим самозанятых.\nПлатёж 4% от дохода: ИПН 0% + ОПВ, ОПВР, СО, ОСМС по 1%.\nЛимит дохода — 300 МРП/мес. Учёт через приложение E-Salyq Business.',
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
      `📰 <b>${escapeTelegramText(art.title)}</b>\n\n${escapeTelegramText(art.summary)}\n\n` +
      `Читайте полностью в приложении Esep.`,
      CHANNEL_CTA_KEYBOARD,
    );

    await db.query('UPDATE articles SET channel_posted = TRUE WHERE id = $1', [art.id]);
  } catch (err) {
    console.error('[bot] postLatestArticle error:', err.code || 'FAILED');
    throw err;
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
    'Упрощёнка, самозанятый или ОУР? Зависит от дохода.\n' +
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
  if (!PRIVATE_CHANNEL_ID) return requireTelegramSuccess(await sendAdmin(text,extra));
  try { return await send(PRIVATE_CHANNEL_ID,text,extra); }
  catch { return requireTelegramSuccess(await sendAdmin(text,extra)); }
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
    `${escapeTelegramText(typeLabel)} | ${escapeTelegramText(post.scheduled)}\n` +
    `━━━━━━━━━━━━━━━━━━━━\n\n` +
    marketingPostHtml(post),
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
      await send(chatId, 'Совет опубликован в канал.');
      return true;

    case '/post_deadline':
      await postDeadlineReminder();
      await send(chatId, 'Напоминание о дедлайнах опубликовано.');
      return true;

    case '/post_article':
      await postLatestArticle();
      await send(chatId, 'Статья опубликована в канал (если есть неопубликованные).');
      return true;

    case '/post_lead':
      await postLeadMagnet();
      await send(chatId, 'Лид-магнит опубликован.');
      return true;

    case '/post_custom':
      if (!args) {
        await send(chatId, 'Использование: <code>/post_custom Текст поста</code>');
        return true;
      }
      await postToChannel(args, CHANNEL_CTA_KEYBOARD);
      await send(chatId, 'Опубликовано в канал.');
      return true;

    case '/channel_stats':
      try {
        const r = requireTelegramSuccess(await botRequest('getChatMemberCount', { chat_id: CHANNEL_ID }));
        const count = r.result;
        await send(chatId, `📊 Подписчиков в канале: <b>${count}</b>`);
      } catch {
        await send(chatId, 'Не удалось получить статистику.');
      }
      return true;

    // ── Маркетинг-контент ──
    case '/draft':
    case '/today': {
      const post = await postDailyContent();
      if (!post) await send(chatId, 'На сегодня постов нет. Все опубликованы.');
      return true;
    }

    case '/week': {
      const schedule = await marketing.getWeekSchedule();
      if (!schedule.length) {
        await send(chatId, 'Расписание пусто. Контент закончился.');
        return true;
      }
      const lines = schedule.map(p => {
        const status = p.posted ? '✅' : '⏳';
        const typeShort = { pain: 'Боль', education: 'Обуч', case: 'Кейс', selling: 'Прод', engagement: 'Вовл' };
        return `${status} ${p.scheduled} [${typeShort[p.type] || p.type}] ${p.title}`;
      });
      await send(chatId, `📅 <b>Расписание на неделю:</b>\n\n${lines.map(escapeTelegramText).join('\n')}`);
      return true;
    }

    case '/mstats': {
      const stats = await marketing.getStats();
      await send(chatId,
        `📊 <b>Маркетинг-статистика</b>\n\n` +
        `Всего постов: ${stats.total}\n` +
        `Опубликовано: ${stats.posted}\n` +
        `В очереди: ${stats.queued}`,
      );
      return true;
    }

    case '/admin_help':
      await send(chatId,
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
  const secret = process.env.TELEGRAM_WEBHOOK_SECRET;
  if (!validSecret(secret)) throw new Error('TELEGRAM_WEBHOOK_SECRET must contain 32-256 allowed characters');
  await store.assertReady();
  const url = `${baseUrl}/api/bot/webhook`;
  const r = await botRequest('setWebhook', { url, secret_token: secret, allowed_updates: ['message', 'callback_query', 'channel_post'] });
  requireTelegramSuccess(r);
  console.log('[bot] setWebhook: OK');

  // Start channel auto-posting scheduler
  startChannelScheduler();

  // Register command hints
  requireTelegramSuccess(await botRequest('setMyCommands', {
    commands: [
      { command: 'menu',      description: 'Главное меню' },
      { command: 'cancel',    description: 'Отменить выбор расчёта' },
      { command: 'salary',    description: 'Рассчитать зарплату' },
      { command: 'calc',      description: 'Рассчитать налог 910' },
      { command: 'social',    description: 'Соцплатежи за себя' },
      { command: 'rates',     description: 'Параметры расчётов 2026' },
      { command: 'self',      description: 'Налог самозанятого' },
      { command: 'deadlines', description: 'Сроки подачи и оплаты' },
      { command: 'status',    description: 'Статус и лимиты' },
      { command: 'link',      description: 'Привязать аккаунт Esep' },
      { command: 'help',      description: 'Меню и помощь' },
    ],
  }));
}

module.exports = {
  handleUpdate,
  send,
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
