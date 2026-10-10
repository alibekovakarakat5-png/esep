'use strict';
const {createHash}=require('node:crypto');

const VAT_POST={
  type:'education', platform:'telegram', title:'НДС для ИП — когда вставать на учёт?',
  body:'НДС в Казахстане: правила на 2026 год\n\n'+
    '• Базовая ставка НДС — 16%. Для отдельных операций предусмотрены другие ставки и освобождения.\n'+
    '• На общеустановленном порядке обязательная регистрация связана с превышением оборота 10 000 МРП за календарный год. В 2026 году это 43 250 000 ₸.\n'+
    '• Применяющие специальные налоговые режимы, включая упрощённую декларацию, не подлежат постановке на регистрационный учёт по НДС. Нельзя применять правило об этом пороге ко всем ИП одинаково.\n\n'+
    'Для конкретной ситуации сначала определите режим, вид операции и статус регистрации.\n\n'+
    'Проверено по разъяснениям КГД 10.10.2026:\n'+
    'https://www.gov.kz/situations/817/intro?lang=ru\n'+
    'https://www.gov.kz/memleket/entities/kgd/press/news/details/1113236?lang=ru',
  review_key:'vat-2026-10-10-v1', review_state:'verified',
  reviewed_at:'2026-10-10T00:00:00.000Z', review_expires_at:'2026-11-10T00:00:00.000Z',
};
function fingerprint(post) {
  return createHash('sha256').update(JSON.stringify([post.title,post.body,post.platform])).digest('hex');
}
VAT_POST.content_hash=fingerprint(VAT_POST);
Object.freeze(VAT_POST);
function canPublish(post,now=new Date()) {
  if(!post||post.review_key!==VAT_POST.review_key||post.review_state!=='verified')return false;
  const time=new Date(now).getTime();
  return Number.isFinite(time)&&time>=Date.parse(VAT_POST.reviewed_at)&&time<Date.parse(VAT_POST.review_expires_at)&&
    new Date(post.reviewed_at).getTime()===Date.parse(VAT_POST.reviewed_at)&&
    new Date(post.review_expires_at).getTime()===Date.parse(VAT_POST.review_expires_at)&&
    post.content_hash===VAT_POST.content_hash&&fingerprint(post)===VAT_POST.content_hash;
}
function legacyVatBody(old=false) {
  return `Порог НДС: оборот свыше ${old?'20 000':'10 000'} МРП за 12 месяцев.\n\n`+
    `В 2026: ${old?'20 000':'10 000'} × 4 325 = ${old?'86 500 000':'43 250 000'} тенге.\n\n`+
    `Что значит:\n— Если оборот < ${old?'86.5':'43.25'} млн — НДС не нужен\n`+
    `— Если превысил — обязан встать на учёт\n— Ставка НДС: ${old?'12':'16'}%\n`+
    '— Можно зачитывать входящий НДС\n\nСледи за оборотом в Есеп: @EsepKZ_bot';
}
function isLegacyVat(post) {
  return post?.title===VAT_POST.title&&post.platform==='telegram'&&
    [legacyVatBody(true),legacyVatBody(false)].includes(String(post.body).replace(/\r\n/g,'\n'));
}
const schema=`
  ALTER TABLE marketing_posts ADD COLUMN IF NOT EXISTS review_state TEXT NOT NULL DEFAULT 'pending';
  ALTER TABLE marketing_posts ADD COLUMN IF NOT EXISTS review_key TEXT;
  ALTER TABLE marketing_posts ADD COLUMN IF NOT EXISTS content_hash TEXT;
  ALTER TABLE marketing_posts ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;
  ALTER TABLE marketing_posts ADD COLUMN IF NOT EXISTS review_expires_at TIMESTAMPTZ;
  ALTER TABLE marketing_posts ADD COLUMN IF NOT EXISTS telegram_chat_id TEXT;
  ALTER TABLE marketing_posts ADD COLUMN IF NOT EXISTS telegram_message_id BIGINT;
  ALTER TABLE marketing_posts ADD COLUMN IF NOT EXISTS approved_by TEXT;
  ALTER TABLE marketing_posts ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
  CREATE TABLE IF NOT EXISTS marketing_review_snapshots (
    release_key TEXT NOT NULL, post_id INTEGER NOT NULL, original JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY(release_key,post_id)
  );
  CREATE TABLE IF NOT EXISTS marketing_review_releases (
    release_key TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );
  CREATE TABLE IF NOT EXISTS marketing_channel_corrections (
    correction_key TEXT PRIMARY KEY, chat_id TEXT NOT NULL, message_id BIGINT NOT NULL,
    original_text TEXT NOT NULL, replacement_text TEXT NOT NULL,
    status TEXT NOT NULL, edited_at TIMESTAMPTZ, last_error TEXT
  );
`;
// Caller owns the transaction. Preserve original rows before any body updates.
async function applyReviewMigration(c) {
  await c.query(schema);
  const key='marketing-review-2026-10-10-v1';
  await c.query("SELECT pg_advisory_xact_lock(6041010)");
  const done=await c.query('SELECT 1 FROM marketing_review_releases WHERE release_key=$1',[key]);
  if(done.rows.length)return {alreadyApplied:true};
  const rows=(await c.query('SELECT * FROM marketing_posts WHERE posted=FALSE OR title=$1 FOR UPDATE',[VAT_POST.title])).rows;
  let updated=0,queued=0,legacyPublished=0;
  for(const p of rows){
    await c.query('INSERT INTO marketing_review_snapshots(release_key,post_id,original) VALUES($1,$2,$3::jsonb) ON CONFLICT DO NOTHING',[key,p.id,JSON.stringify(p)]);
    if(p.posted){if(isLegacyVat(p))legacyPublished++;continue;}
    queued++;
    if(isLegacyVat(p)){
      await c.query(`UPDATE marketing_posts SET body=$2,review_state='verified',review_key=$3,
        content_hash=$4,reviewed_at=$5,review_expires_at=$6 WHERE id=$1`,
        [p.id,VAT_POST.body,VAT_POST.review_key,VAT_POST.content_hash,VAT_POST.reviewed_at,VAT_POST.review_expires_at]);
      updated++;
    }
  }
  await c.query('INSERT INTO marketing_review_releases(release_key) VALUES($1)',[key]);
  return {snapshots:rows.length,queued,updatedVatDrafts:updated,held:queued-updated,legacyPublished};
}
module.exports={VAT_POST,fingerprint,canPublish,legacyVatBody,isLegacyVat,schema,applyReviewMigration};
