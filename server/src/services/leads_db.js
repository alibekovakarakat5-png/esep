// ── Единая база лидов (TG + WhatsApp + приложение), склейка по телефону ──────
const db = require('../db');

function normalizePhone(raw) {
  if (!raw) return null;
  let d = String(raw).replace(/\D/g, '');       // только цифры
  if (!d) return null;
  if (d.length === 11 && d.startsWith('8')) d = '7' + d.slice(1); // 8XXX → 7XXX
  if (d.length === 10) d = '7' + d;              // XXXXXXXXXX → 7XXXXXXXXXX
  if (d.length !== 11 || !d.startsWith('7')) return null;         // не похоже на KZ-номер
  return '+' + d;
}

function detectIntent(text) {
  const s = String(text || '').toLowerCase();
  if (s.includes('regime_buh') || s.includes('бухгалтер') || s.includes('фирм') || s.includes('веду клиент')) return 'b2b';
  if (s.includes('самозанят')) return 'self';
  if (s.includes('910') || s.includes('упрощён') || s.includes('упрощен') || s.includes('ип')) return 'ip';
  return 'unknown';
}

async function migrateLeads() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS leads (
      id               BIGSERIAL    PRIMARY KEY,
      phone            TEXT,
      name             TEXT,
      tg_chat_id       TEXT,
      tg_username      TEXT,
      wa_jid           TEXT,
      esep_user_id     UUID         REFERENCES users(id) ON DELETE SET NULL,
      source           TEXT         NOT NULL DEFAULT 'tg_bot',
      intent           TEXT         NOT NULL DEFAULT 'unknown',
      status           TEXT         NOT NULL DEFAULT 'new',
      followups_sent   INT          NOT NULL DEFAULT 0,
      last_activity_at TIMESTAMPTZ  DEFAULT NOW(),
      created_at       TIMESTAMPTZ  DEFAULT NOW(),
      notes            TEXT
    );
    CREATE UNIQUE INDEX IF NOT EXISTS leads_phone_uq   ON leads(phone)      WHERE phone IS NOT NULL;
    CREATE UNIQUE INDEX IF NOT EXISTS leads_tg_uq      ON leads(tg_chat_id) WHERE tg_chat_id IS NOT NULL;
    CREATE INDEX        IF NOT EXISTS leads_status_idx ON leads(status);
    CREATE INDEX        IF NOT EXISTS leads_source_idx ON leads(source);
  `);
  console.log('✅  Leads migrated');
}

// Идемпотентный upsert. Ключи поиска по приоритету: phone → tg_chat_id → esep_user_id → wa_jid.
// COALESCE — не затираем существующее пустым значением.
async function upsertLead(p = {}) {
  const phone = normalizePhone(p.phone);
  const keys = [];
  if (phone) keys.push(['phone', phone]);
  if (p.tg_chat_id) keys.push(['tg_chat_id', String(p.tg_chat_id)]);
  if (p.esep_user_id) keys.push(['esep_user_id', p.esep_user_id]);
  if (p.wa_jid) keys.push(['wa_jid', String(p.wa_jid)]);
  if (!keys.length) return null;

  let existing = null;
  for (const [col, val] of keys) {
    const { rows } = await db.query(`SELECT * FROM leads WHERE ${col} = $1 LIMIT 1`, [val]);
    if (rows.length) { existing = rows[0]; break; }
  }

  const f = {
    phone, name: p.name || null,
    tg_chat_id: p.tg_chat_id ? String(p.tg_chat_id) : null,
    tg_username: p.tg_username || null,
    wa_jid: p.wa_jid ? String(p.wa_jid) : null,
    esep_user_id: p.esep_user_id || null,
    source: p.source || 'tg_bot',
    intent: p.intent || null,
  };

  if (existing) {
    await db.query(
      `UPDATE leads SET
         phone        = COALESCE($1, phone),
         name         = COALESCE($2, name),
         tg_chat_id   = COALESCE($3, tg_chat_id),
         tg_username  = COALESCE($4, tg_username),
         wa_jid       = COALESCE($5, wa_jid),
         esep_user_id = COALESCE($6, esep_user_id),
         intent       = CASE WHEN $7 IS NOT NULL AND $7 <> 'unknown' THEN $7 ELSE intent END,
         last_activity_at = NOW()
       WHERE id = $8`,
      [f.phone, f.name, f.tg_chat_id, f.tg_username, f.wa_jid, f.esep_user_id, f.intent, existing.id],
    );
    return existing.id;
  }

  const { rows } = await db.query(
    `INSERT INTO leads (phone, name, tg_chat_id, tg_username, wa_jid, esep_user_id, source, intent)
     VALUES ($1,$2,$3,$4,$5,$6,$7,COALESCE($8,'unknown')) RETURNING id`,
    [f.phone, f.name, f.tg_chat_id, f.tg_username, f.wa_jid, f.esep_user_id, f.source, f.intent],
  );
  return rows[0].id;
}

async function listLeads({ status, source, q, limit = 200 } = {}) {
  const where = [], args = [];
  if (status) { args.push(status); where.push(`status = $${args.length}`); }
  if (source) { args.push(source); where.push(`source = $${args.length}`); }
  if (q) { args.push(`%${q}%`); where.push(`(name ILIKE $${args.length} OR phone ILIKE $${args.length} OR tg_username ILIKE $${args.length})`); }
  args.push(limit);
  const { rows } = await db.query(
    `SELECT * FROM leads ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
     ORDER BY last_activity_at DESC NULLS LAST LIMIT $${args.length}`, args);
  return rows;
}

async function setLeadStatus(id, status, notes) {
  await db.query(
    `UPDATE leads SET status = COALESCE($1, status), notes = COALESCE($2, notes) WHERE id = $3`,
    [status || null, notes ?? null, id]);
}

module.exports = { migrateLeads, normalizePhone, detectIntent, upsertLead, listLeads, setLeadStatus };
