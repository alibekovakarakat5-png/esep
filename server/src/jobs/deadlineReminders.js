/**
 * Напоминания о налоговых сроках для подписчиков бота (bot_users.reminders_on).
 * Раз в день проверяет дату (Алматы) и за 3 дня до дедлайна шлёт напоминание.
 * Боту это разрешено — пишем только тем, кто нажал /start И подписался.
 */
const db = require('../db');
const tg = require('../bot/telegram');

// Текст напоминания на сегодня (дата по Алматы, UTC+5) или null.
function dueReminder(now) {
  const a = new Date(now.getTime() + 5 * 3600e3);
  const m = a.getUTCMonth() + 1, d = a.getUTCDate();
  if (m === 8 && d === 12) return '📅 Через 3 дня — сдача декларации <b>910 за 1 полугодие</b> (до 15 августа). Не пропустите штраф!';
  if (m === 8 && d === 22) return '💸 Через 3 дня — <b>оплата налога по 910</b> за 1 полугодие (до 25 августа) + соцплатежи.';
  if (m === 2 && d === 12) return '📅 Через 3 дня — сдача <b>910 за 2 полугодие</b> (до 15 февраля).';
  if (m === 2 && d === 22) return '💸 Через 3 дня — <b>оплата налога по 910</b> за 2 полугодие (до 25 февраля) + соцплатежи.';
  if (d === 22) return '💼 Через 3 дня — <b>соцплатежи «за себя»</b> (ОПВ, ОПВР, СО, ВОСМС) за этот месяц, до 25 числа.';
  return null;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function runDeadlineReminders(forceText) {
  const text = forceText || dueReminder(new Date());
  if (!text) return;
  let subs = [];
  try {
    const { rows } = await db.query(`SELECT chat_id FROM bot_users WHERE reminders_on = true`);
    subs = rows;
  } catch (e) { console.error('[reminders] query failed:', e.message); return; }
  console.log(`[reminders] отправка ${subs.length} подписчикам`);
  const extra = {
    reply_markup: {
      inline_keyboard: [
        [{ text: '🧮 Посчитать налог', callback_data: 'prompt_calc' }],
        [{ text: '🔕 Отключить напоминания', callback_data: 'remind_off' }],
      ],
    },
  };
  for (const s of subs) {
    try { await tg.send(s.chat_id, text, extra); } catch { /* единичный сбой не критичен */ }
    await sleep(250); // мягкий темп
  }
}

function startDeadlineReminders() {
  if (!process.env.TELEGRAM_BOT_TOKEN) { console.log('[reminders] TELEGRAM_BOT_TOKEN not set — disabled'); return; }
  function msUntil(h, min) {
    const now = new Date(); const t = new Date(now);
    t.setUTCHours(h, min, 0, 0); if (t <= now) t.setUTCDate(t.getUTCDate() + 1);
    return t - now;
  }
  setTimeout(function tick() {
    runDeadlineReminders().catch((e) => console.error('[reminders]', e.message));
    setTimeout(tick, msUntil(4, 30)); // 04:30 UTC ≈ 09:30 Алматы
  }, msUntil(4, 30));
  console.log('[reminders] started — daily ~09:30 Almaty');
}

module.exports = { startDeadlineReminders, runDeadlineReminders, dueReminder };
