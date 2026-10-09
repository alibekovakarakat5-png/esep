'use strict';
const { timingSafeEqual } = require('crypto');

function validSecret(secret) { return typeof secret === 'string' && /^[A-Za-z0-9_-]{32,256}$/.test(secret); }
function createTelegramWebhook({ secret, store, handleUpdate, logger = console }) {
  return async (req, res) => {
    if (!validSecret(secret)) return res.status(503).json({ ok: false });
    const provided = req.get('X-Telegram-Bot-Api-Secret-Token');
    if (typeof provided !== 'string' || Buffer.byteLength(provided) !== Buffer.byteLength(secret) ||
      !timingSafeEqual(Buffer.from(provided),Buffer.from(secret))) return res.status(403).json({ ok: false });
    const update = req.body;
    if (!update || !Number.isSafeInteger(update.update_id) || update.update_id < 0)
      return res.status(400).json({ ok: false });
    try {
      await store.processUpdate(update, handleUpdate);
      return res.json({ ok: true });
    } catch (e) {
      // No body, token, email or SQL details in logs/responses.
      logger.error('[bot] update failed', { update_id:update.update_id, code:e.code || 'BOT_PROCESSING_FAILED' });
      return res.status(503).json({ ok: false });
    }
  };
}
module.exports = { createTelegramWebhook, validSecret };
