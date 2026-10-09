'use strict';
const { randomUUID } = require('crypto');
const { startTag } = require('../bot/input');

const schema = `
  ALTER TABLE bot_users ADD COLUMN IF NOT EXISTS last_activity_at TIMESTAMPTZ;
  ALTER TABLE bot_users ADD COLUMN IF NOT EXISTS first_start_payload TEXT;
  ALTER TABLE bot_users ADD COLUMN IF NOT EXISTS last_start_payload TEXT;
  ALTER TABLE bot_users ADD COLUMN IF NOT EXISTS calculation_kind TEXT;
  ALTER TABLE bot_users ADD COLUMN IF NOT EXISTS calculation_expires_at TIMESTAMPTZ;
  ALTER TABLE bot_users ADD COLUMN IF NOT EXISTS calculation_update_id BIGINT;
  ALTER TABLE bot_users ADD COLUMN IF NOT EXISTS calculation_updated_at TIMESTAMPTZ;
  CREATE TABLE IF NOT EXISTS bot_updates (
    update_id BIGINT PRIMARY KEY,
    owner UUID NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('processing','done','failed')),
    claimed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    quota_chat_id TEXT
  );
  ALTER TABLE bot_updates ADD COLUMN IF NOT EXISTS calculation_kind TEXT;
`;

function createBotStore(db) {
  async function transaction(fn) {
    const c = await db.connect();
    try {
      await c.query('BEGIN');
      const result = await fn(c);
      await c.query('COMMIT');
      return result;
    } catch (e) { await c.query('ROLLBACK'); throw e; }
    finally { c.release(); }
  }
  return {
    async migrate() { await db.query(schema); },
    async assertReady() {
      await db.query('SELECT first_start_payload, last_activity_at, calculation_kind, calculation_expires_at, calculation_update_id, calculation_updated_at FROM bot_users LIMIT 0');
      await db.query('SELECT update_id, quota_chat_id, calculation_kind FROM bot_updates LIMIT 0');
    },
    async calculationKind(chatId) {
      const r=await db.query(`SELECT calculation_kind FROM bot_users
        WHERE chat_id=$1 AND calculation_expires_at>NOW()`,[String(chatId)]);
      const kind=r.rows[0]?.calculation_kind;
      return ['calc','self','salary'].includes(kind) ? kind : null;
    },
    async setCalculationKind(chatId,kind,updateId) {
      if(kind!==null&&!['calc','self','salary'].includes(kind))throw Error('INVALID_CALCULATION_KIND');
      if(!Number.isSafeInteger(updateId)||updateId<0)throw Error('INVALID_UPDATE_ID');
      // Do not let retries overwrite a newer selection. After a week of inactivity
      // Telegram may choose a new random update_id, so the ordering fence must expire.
      await db.query(`UPDATE bot_users SET calculation_kind=$2,
        calculation_expires_at=CASE WHEN $2::text IS NULL THEN NULL ELSE NOW()+INTERVAL '30 minutes' END,
        calculation_update_id=$3,calculation_updated_at=NOW() WHERE chat_id=$1
        AND (calculation_update_id IS NULL OR calculation_update_id<$3
          OR calculation_updated_at<NOW()-INTERVAL '7 days')`,[String(chatId),kind,updateId]);
    },
    async resolveCalculationKind(chatId,updateId) {
      return transaction(async c=>{
        const receipt=await c.query('SELECT calculation_kind FROM bot_updates WHERE update_id=$1 FOR UPDATE',[updateId]);
        if(!receipt.rows.length)throw Error('BOT_UPDATE_MISSING');
        if(receipt.rows[0].calculation_kind)return receipt.rows[0].calculation_kind;
        const r=await c.query(`SELECT calculation_kind,calculation_expires_at>NOW() AS valid
          FROM bot_users WHERE chat_id=$1`,[String(chatId)]);
        const selection=r.rows[0];
        const kind=['calc','self','salary'].includes(selection?.calculation_kind)
          ? (selection.valid?selection.calculation_kind:'expired') : 'calc';
        // Persist the interpretation so a delivery retry cannot use a later menu choice.
        await c.query('UPDATE bot_updates SET calculation_kind=$2 WHERE update_id=$1',[updateId,kind]);
        return kind;
      });
    },
    async publishPost(postId, deliver) {
      return transaction(async c => {
        const r = await c.query('SELECT * FROM marketing_posts WHERE id=$1 FOR UPDATE', [postId]);
        const post = r.rows[0];
        if (!post) return 'missing';
        if (post.posted) return 'already_posted';
        // Bounded Telegram request; release the row on failure, never mark failed delivery posted.
        await deliver(post);
        await c.query('UPDATE marketing_posts SET posted=TRUE,posted_at=NOW() WHERE id=$1', [postId]);
        return 'posted';
      });
    },
    async processUpdate(update, handler) {
      const owner = randomUUID();
      const claim = await db.query(`INSERT INTO bot_updates (update_id,owner,status)
        VALUES ($1,$2,'processing') ON CONFLICT (update_id) DO UPDATE
        SET owner=EXCLUDED.owner,status='processing',claimed_at=NOW()
        WHERE bot_updates.status='failed' OR
          (bot_updates.status='processing' AND bot_updates.claimed_at < NOW()-INTERVAL '5 minutes')
        RETURNING update_id`, [update.update_id, owner]);
      if (!claim.rows.length) {
        const r = await db.query('SELECT status FROM bot_updates WHERE update_id=$1', [update.update_id]);
        if (r.rows[0]?.status === 'done') return { duplicate: true };
        throw new Error('BOT_UPDATE_IN_PROGRESS');
      }
      try {
        await handler(update);
        await db.query(`UPDATE bot_updates SET status='done',completed_at=NOW()
          WHERE update_id=$1 AND owner=$2`, [update.update_id, owner]);
        return { duplicate: false };
      } catch (e) {
        await db.query(`UPDATE bot_updates SET status='failed' WHERE update_id=$1 AND owner=$2`, [update.update_id, owner]);
        throw e;
      }
    },
    async trackVisitor(chatId, from, payload, intent = 'unknown') {
      return transaction(async c => {
        const existingLead = await c.query('SELECT id FROM leads WHERE tg_chat_id=$1', [String(chatId)]);
        const inserted = await c.query(`INSERT INTO bot_users (chat_id,last_activity_at,first_start_payload,last_start_payload)
          VALUES ($1,NOW(),$2,$2) ON CONFLICT (chat_id) DO NOTHING RETURNING chat_id`,
        [String(chatId), payload === undefined ? null : startTag(payload)]);
        await c.query(`UPDATE bot_users SET last_activity_at=NOW(),
          first_start_payload=COALESCE(first_start_payload,$2),last_start_payload=COALESCE($2,last_start_payload)
          WHERE chat_id=$1`, [String(chatId), payload === undefined ? null : startTag(payload)]);
        // Atomic Telegram-only upsert. Never overwrites sales status, source, notes or verified links.
        await c.query(`INSERT INTO leads (tg_chat_id,tg_username,name,source,intent)
          VALUES ($1,$2,$3,'tg_bot',$4)
          ON CONFLICT (tg_chat_id) WHERE tg_chat_id IS NOT NULL DO UPDATE SET
          tg_username=COALESCE(EXCLUDED.tg_username,leads.tg_username),
          name=COALESCE(EXCLUDED.name,leads.name),last_activity_at=NOW(),
          intent=CASE WHEN EXCLUDED.intent<>'unknown' THEN EXCLUDED.intent ELSE leads.intent END`,
        [String(chatId), from.username || null, [from.first_name,from.last_name].filter(Boolean).join(' ') || null, intent]);
        return { isNew: inserted.rows.length === 1 && existingLead.rows.length === 0 };
      });
    },
    async verifiedAccount(chatId) {
      const r = await db.query(`SELECT id,email,name,tier FROM users
        WHERE telegram_chat_id=$1 AND telegram_linked_at IS NOT NULL`, [String(chatId)]);
      return r.rows[0] || null;
    },
    async consumeQuota(chatId, updateId, limit, day) {
      return transaction(async c => {
        // A retry after a delivery error must not charge twice for the same update.
        const receipt = await c.query('SELECT quota_chat_id FROM bot_updates WHERE update_id=$1 FOR UPDATE', [updateId]);
        if (receipt.rows[0]?.quota_chat_id === String(chatId)) return true;
        const r = await c.query(`UPDATE bot_users SET last_query_date=$2,
          queries_today=CASE WHEN last_query_date IS DISTINCT FROM $2 THEN 1 ELSE queries_today+1 END
          WHERE chat_id=$1 AND (last_query_date IS DISTINCT FROM $2 OR queries_today<$3)
          RETURNING queries_today`, [String(chatId), day, limit]);
        if (!r.rows.length) return false;
        await c.query('UPDATE bot_updates SET quota_chat_id=$2 WHERE update_id=$1', [updateId, String(chatId)]);
        return true;
      });
    },
    async confirmBinding(token, chatId, username) {
      return transaction(async c => {
        const r = await c.query(`SELECT user_id,consumed_at,expires_at,
          expires_at>NOW() AS valid FROM telegram_bind_token WHERE token=$1 FOR UPDATE`, [token]);
        const t = r.rows[0];
        if (!t || t.consumed_at || !t.valid) return null;
        // Lock affected accounts in a stable order. Unique chat index arbitrates concurrent binds.
        const accounts = await c.query(`SELECT id,email FROM users
          WHERE id=$1 OR telegram_chat_id=$2 ORDER BY id FOR UPDATE`, [t.user_id, String(chatId)]);
        const target = accounts.rows.find(u => u.id === t.user_id);
        if (!target) return null;
        await c.query(`UPDATE users SET telegram_chat_id=NULL,telegram_username=NULL,telegram_linked_at=NULL
          WHERE telegram_chat_id=$1`, [String(chatId)]);
        await c.query(`UPDATE bot_users SET linked_user_id=NULL WHERE linked_user_id=$1 OR chat_id=$2`, [t.user_id,String(chatId)]);
        await c.query(`UPDATE users SET telegram_chat_id=$1,telegram_username=$2,telegram_linked_at=NOW() WHERE id=$3`,
          [String(chatId),username || null,t.user_id]);
        await c.query(`INSERT INTO bot_users (chat_id,linked_user_id) VALUES ($1,$2)
          ON CONFLICT (chat_id) DO UPDATE SET linked_user_id=EXCLUDED.linked_user_id`, [String(chatId),t.user_id]);
        await c.query(`UPDATE telegram_bind_token SET consumed_at=NOW(),consumed_chat_id=$2,consumed_username=$3 WHERE token=$1`,
          [token,String(chatId),username || null]);
        await c.query(`INSERT INTO auth_security_log (user_id,event,meta) VALUES ($1,'tg_bind_confirmed',$2::jsonb)`,
          [t.user_id,JSON.stringify({chat_id:String(chatId),username:username || null})]);
        return target;
      });
    },
  };
}

module.exports = { createBotStore, schema };
