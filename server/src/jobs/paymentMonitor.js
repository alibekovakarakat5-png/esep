/**
 * Payment Monitor — checks for expiring/expired subscriptions
 *
 * - Every hour: expire overdue payments, downgrade users to 'free'
 * - 3 days before: notify admin via Telegram
 * - On expiry: notify admin + user (if email exists)
 */

const db = require('../db');
const tg = require('../bot/telegram');

// ── Expire overdue payments & downgrade users ────────────────────────────────
async function expirePayments() {
  const client = await db.connect();
  try {
    await client.query('BEGIN');

    // Find payments that are paid/active but past expires_at
    const { rows: expired } = await client.query(`
      UPDATE payments
         SET status = 'expired'
       WHERE status = 'paid'
         AND expires_at IS NOT NULL
         AND expires_at < NOW()
       RETURNING id, user_id, tier, expires_at
    `);

    for (const p of expired) {
      // Check if user has another active payment
      const { rows: otherActive } = await client.query(
        `SELECT 1 FROM payments
          WHERE user_id = $1 AND status = 'paid' AND id != $2
            AND (expires_at IS NULL OR expires_at > NOW())
          LIMIT 1`,
        [p.user_id, p.id],
      );

      // Also check if user has active promo
      const { rows: activePromo } = await client.query(
        `SELECT 1 FROM promo_usages
          WHERE user_id = $1 AND expires_at > NOW()
          LIMIT 1`,
        [p.user_id],
      );

      if (otherActive.length === 0 && activePromo.length === 0) {
        // Downgrade to free
        await client.query(
          `UPDATE users
              SET tier = 'free',
                  subscription_expires_at = NULL
            WHERE id = $1`,
          [p.user_id],
        );
      }

      // Get user email for notification
      const { rows: userRows } = await client.query(
        `SELECT email, name FROM users WHERE id = $1`,
        [p.user_id],
      );
      const user = userRows[0];
      if (user) {
        const adminUrl = process.env.ADMIN_URL ?? 'https://esep-production.up.railway.app';
        tg.sendAdmin(
          `🔴 <b>Подписка истекла</b>\n\n` +
          `Клиент: ${user.email}\n` +
          `Тариф: ${p.tier}\n` +
          `Истекла: ${new Date(p.expires_at).toLocaleDateString('ru-RU')}\n\n` +
          `<a href="${adminUrl}/api/admin#payments">Открыть платежи</a>`,
        );
      }
    }

    if (expired.length > 0) {
      console.log(`[paymentMonitor] Expired ${expired.length} payment(s)`);
    }

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[paymentMonitor] expirePayments error:', err.message);
  } finally {
    client.release();
  }
}

// ── Notify admin about payments expiring in 3 days ───────────────────────────
async function notifyExpiringSoon() {
  try {
    const { rows } = await db.query(`
      SELECT p.id, p.user_id, p.tier, p.expires_at, u.email, u.name
        FROM payments p
        JOIN users u ON u.id = p.user_id
       WHERE p.status = 'paid'
         AND p.expires_at BETWEEN NOW() AND NOW() + INTERVAL '3 days'
       ORDER BY p.expires_at
    `);

    if (rows.length === 0) return;

    const adminUrl = process.env.ADMIN_URL ?? 'https://esep-production.up.railway.app';

    let msg = `⚠️ <b>Подписки истекают в ближ. 3 дня</b>\n\n`;
    for (const r of rows) {
      const d = new Date(r.expires_at).toLocaleDateString('ru-RU');
      msg += `• ${r.email} — ${r.tier} (${d})\n`;
    }
    msg += `\n<a href="${adminUrl}/api/admin#payments">Управление</a>`;

    tg.sendAdmin(msg);
  } catch (err) {
    console.error('[paymentMonitor] notifyExpiringSoon error:', err.message);
  }
}

// ── Run full check ──────────────────────────────────────────────────────────
async function runPaymentCheck() {
  await expirePayments();
  await notifyExpiringSoon();
}

// ── Start monitor (called from index.js) ────────────────────────────────────
function startPaymentMonitor() {
  // First check 60 sec after startup
  setTimeout(runPaymentCheck, 60_000);

  // Then every hour
  setInterval(runPaymentCheck, 60 * 60 * 1_000);

  console.log('[paymentMonitor] Started — checking every hour');
}

module.exports = { startPaymentMonitor, runPaymentCheck, expirePayments };
