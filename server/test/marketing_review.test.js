'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {PGlite}=require('@electric-sql/pglite');
const {VAT_POST,canPublish,legacyVatBody,applyReviewMigration,schema}=require('../src/services/marketing_review');
const {correctVatPost,replacementText,parsePublicPost}=require('../src/services/marketing_correction');
const NOW=new Date('2026-10-10T12:00:00Z');

test('only the exact reviewed content is publishable inside its review window',()=>{
  assert(canPublish(VAT_POST,NOW));
  for(const p of [{...VAT_POST,body:legacyVatBody(true)},{...VAT_POST,title:'changed'},
    {...VAT_POST,platform:'instagram'},{...VAT_POST,review_state:'pending'},
    {...VAT_POST,review_state:'skipped'},{...VAT_POST,review_key:'forged'},
    {...VAT_POST,review_expires_at:'2027-01-01'},null])assert.equal(canPublish(p,NOW),false);
  assert.equal(canPublish(VAT_POST,new Date('2026-11-10T00:00:00Z')),false);
  assert.equal(canPublish(VAT_POST,new Date('2026-10-09T23:59:59Z')),false);
});
test('queue migration preserves originals and never marks held posts published; correction is scoped and retryable',async t=>{
  const pg=new PGlite();t.after(()=>pg.close());
  const client={query:(q,p)=>q===schema?pg.exec(q):pg.query(q,p)};
  await pg.exec(`CREATE TABLE marketing_posts(id INT PRIMARY KEY,title TEXT,body TEXT,platform TEXT,
    posted BOOLEAN DEFAULT false,posted_at TIMESTAMPTZ,scheduled DATE,notes TEXT);`);
  for(const [id,title,body,posted] of [[1,VAT_POST.title,legacyVatBody(true),false],
    [2,'Unreviewed case','Unverified claims',false],[3,VAT_POST.title,legacyVatBody(false),true],
    [4,VAT_POST.title,'Manually edited text',false]]){
    await pg.query('INSERT INTO marketing_posts(id,title,body,posted,platform,notes) VALUES($1,$2,$3,$4,\'telegram\',\'keep\')',[id,title,body,posted]);
  }
  await pg.query('BEGIN');const migrated=await applyReviewMigration(client);await pg.query('COMMIT');
  assert.deepEqual(migrated,{snapshots:4,queued:3,updatedVatDrafts:1,held:2,legacyPublished:1});
  const rows=(await pg.query('SELECT * FROM marketing_posts ORDER BY id')).rows;
  assert(canPublish(rows[0],NOW));assert.equal(rows[0].posted,false);
  assert.equal(rows[1].body,'Unverified claims');assert.equal(rows[1].review_state,'pending');
  assert.equal(rows[2].body,legacyVatBody(false));assert.equal(rows[2].posted,true);
  assert.equal(rows[3].body,'Manually edited text');assert.equal(rows[3].review_state,'pending');
  assert(rows.every(x=>x.notes==='keep'));
  assert.equal((await pg.query('SELECT original FROM marketing_review_snapshots WHERE post_id=1')).rows[0].original.body,legacyVatBody(true));
  await pg.query("UPDATE marketing_posts SET body='later edit' WHERE id=1");
  await pg.query('BEGIN');assert.deepEqual(await applyReviewMigration(client),{alreadyApplied:true});await pg.query('COMMIT');
  assert.equal((await pg.query('SELECT body FROM marketing_posts WHERE id=1')).rows[0].body,'later edit');
  assert.equal((await pg.query('SELECT count(*)::int n FROM marketing_review_snapshots')).rows[0].n,4);
  const original=VAT_POST.title+'\n\n'+legacyVatBody(true);let actual=original,edits=0;
  const request=async(method,body)=>{
    assert.equal(method,'editMessageText');assert.equal(body.chat_id,'@esepfinancialsupport');assert.equal(body.message_id,169);
    edits++;actual=replacementText;return {ok:true,result:{message_id:169,text:replacementText}};
  };
  await assert.rejects(correctVatPost(pg,request,async()=> 'Another post'),/CONTENT_CHANGED/);
  assert.equal(edits,0);
  await assert.rejects(correctVatPost(pg,async()=>({ok:false,error_code:403}),async()=>actual),/delivery failed/);
  assert.equal((await pg.query('SELECT status,original_text FROM marketing_channel_corrections')).rows[0].status,'pending');
  assert.equal((await pg.query('SELECT original_text FROM marketing_channel_corrections')).rows[0].original_text,original);
  assert.equal((await correctVatPost(pg,request,async()=>actual)).changed,true);
  assert.equal((await correctVatPost(pg,request,async()=>actual)).changed,false);assert.equal(edits,1);
  assert.equal((await pg.query('SELECT status FROM marketing_channel_corrections')).rows[0].status,'done');
  await assert.rejects(correctVatPost(pg,request,async()=>original),/CORRECTED_POST_CHANGED/);assert.equal(edits,1);
});
test('public-page parser identifies the exact message instead of a neighbouring VAT post',()=>{
  const block=(id,text)=>`<div data-post="esepfinancialsupport/${id}"><div class="tgme_widget_message_text js-message_text">${text}</div></div>`;
  assert.equal(parsePublicPost(block(168,'wrong')+block(169,'A &lt; B<br/><br/>16%')+block(170,'wrong')),'A < B\n\n16%');
  assert.throws(()=>parsePublicPost(block(168,'169 inside text')),/NOT_FOUND/);
});
