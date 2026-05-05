/**
 * trialMonitor — runs once an hour. Notifies Karakat (admin) about
 * trials nearing expiry so she can call/message the user before they
 * churn.
 *
 *   T-1 day  → "У @user остался 1 день trial — напомните оплатить"
 *   T-0      → "Trial у @user истёк сегодня. Free лимиты включены."
 *
 * Notifications are sent at most once per (user_id, kind) pair. We
 * track that in a tiny table created on first run.
 */
const db = require('../db');
const { sendAdmin } = require('../bot/telegram');

async function ensureTrackingTable() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS trial_alerts (
      user_id    TEXT NOT NULL,
      kind       TEXT NOT NULL,
      sent_at    TIMESTAMPTZ DEFAULT NOW(),
      PRIMARY KEY (user_id, kind)
    );
  `);
}

async function alreadyNotified(userId, kind) {
  const { rows } = await db.query(
    'SELECT 1 FROM trial_alerts WHERE user_id = $1 AND kind = $2',
    [userId, kind],
  );
  return rows.length > 0;
}

async function markNotified(userId, kind) {
  await db.query(
    'INSERT INTO trial_alerts (user_id, kind) VALUES ($1, $2) ON CONFLICT DO NOTHING',
    [userId, kind],
  );
}

async function tick() {
  try {
    const { rows } = await db.query(`
      SELECT id, email, name, phone, trial_expires_at,
             EXTRACT(EPOCH FROM (trial_expires_at - NOW())) / 3600 AS hours_left
        FROM users
       WHERE tier IN ('free', 'solo', 'accountant', 'accountant_pro')
         AND trial_expires_at IS NOT NULL
         AND (subscription_expires_at IS NULL OR subscription_expires_at < NOW())
         AND trial_expires_at > NOW() - INTERVAL '2 days'
    `);

    for (const u of rows) {
      const hours = Number(u.hours_left);
      // T-1 window: 12-36 hours left.
      if (hours > 12 && hours <= 36 && !(await alreadyNotified(u.id, 't-1'))) {
        await sendAdmin(
          `⏰ <b>Trial T-1</b>\n\n` +
          `<b>${escape(u.name || u.email)}</b>\n` +
          `📧 ${escape(u.email)}\n` +
          (u.phone ? `📞 +${escape(String(u.phone))}\n` : '') +
          `\nОсталось ~${Math.round(hours)} ч пробного периода.\n` +
          `<i>Позвоните и предложите оплатить тариф.</i>`,
        );
        await markNotified(u.id, 't-1');
      }
      // T-0: trial expired in the last 24 hours.
      if (hours <= 0 && hours >= -24 && !(await alreadyNotified(u.id, 't-0'))) {
        await sendAdmin(
          `🔴 <b>Trial истёк</b>\n\n` +
          `<b>${escape(u.name || u.email)}</b>\n` +
          `📧 ${escape(u.email)}\n` +
          (u.phone ? `📞 +${escape(String(u.phone))}\n` : '') +
          `\nКлиент попал на free-лимиты. Действия в приложении заблокированы.\n` +
          `<i>Напишите/позвоните — самое горячее время для продажи.</i>`,
        );
        await markNotified(u.id, 't-0');
      }
    }
  } catch (e) {
    console.error('[trialMonitor] tick error:', e);
  }
}

function escape(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

let interval;
async function startTrialMonitor() {
  await ensureTrackingTable();
  await tick();                            // run immediately on boot
  interval = setInterval(tick, 60 * 60 * 1000); // every hour
  console.log('[trialMonitor] started (hourly)');
}

function stopTrialMonitor() {
  if (interval) clearInterval(interval);
}

module.exports = { startTrialMonitor, stopTrialMonitor, tick };
