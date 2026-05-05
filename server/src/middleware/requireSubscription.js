/**
 * requireActiveSubscription — gate for endpoints that require either
 * an active paid subscription OR an active 7-day trial. Returns 402
 * (Payment Required) with structured payload when locked out, so the
 * Flutter client can show the hard-paywall.
 *
 * Must run AFTER the auth middleware (uses req.userId).
 */
const db = require('../db');
const { normalizeTier } = require('../tiers');

module.exports = async function requireActiveSubscription(req, res, next) {
  if (!req.userId) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  try {
    const { rows } = await db.query(
      `SELECT tier, trial_started_at, trial_expires_at, subscription_expires_at
         FROM users WHERE id = $1`,
      [req.userId],
    );
    if (!rows.length) return res.status(401).json({ error: 'Invalid user' });

    const u = rows[0];
    const tier = normalizeTier(u.tier);
    const now = new Date();

    const subActive =
      tier !== 'free' &&
      (u.subscription_expires_at == null || new Date(u.subscription_expires_at) > now);

    const trialActive =
      u.trial_expires_at != null && new Date(u.trial_expires_at) > now;

    if (subActive || trialActive) {
      // Stash for downstream handlers — saves them re-querying.
      req.subscription = {
        tier,
        subscriptionActive: subActive,
        trialActive,
        trialExpiresAt: u.trial_expires_at,
        subscriptionExpiresAt: u.subscription_expires_at,
      };
      return next();
    }

    return res.status(402).json({
      error: 'subscription_required',
      message: 'Пробный период закончился. Подключите тариф чтобы продолжить.',
      tier,
      trialExpiresAt: u.trial_expires_at,
      subscriptionExpiresAt: u.subscription_expires_at,
    });
  } catch (e) {
    console.error('[requireSubscription] error:', e);
    return res.status(500).json({ error: 'Server error' });
  }
};
