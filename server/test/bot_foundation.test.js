'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {EventEmitter} = require('node:events');
const {randomUUID} = require('node:crypto');
const {PGlite} = require('@electric-sql/pglite');
const {parseAmount,textCalculation,startTag} = require('../src/bot/input');
const {createBotRequest,requireTelegramSuccess} = require('../src/bot/transport');
const {createBotStore,schema} = require('../src/services/bot_foundation');
const review = require('../src/services/marketing_review');
const work = require('../src/services/bot_workspace');
const REVIEW_NOW=new Date('2026-10-10T12:00:00.000Z');
const {createTelegramWebhook} = require('../src/routes/telegram-webhook');

test('money parser accepts supported inputs and rejects ambiguity, invalid numbers and form identifiers',()=>{
  for(const [s,n] of [['5000000',5e6],['5 000 000',5e6],['5\u202f000\u202f000',5e6],['3 млн',3e6],['1,5 млн ₸',1.5e6],['300 тыс.',300000],['120 000,50 тенге',120000.5]]) assert.equal(parseAmount(s),n,s);
  for(const s of ['','0','-500','Infinity','NaN','1e6','500abc','5 00 000','1.2.3','99999999999999','1,234,567']) assert.equal(parseAmount(s),null,s);
  assert.deepEqual(textCalculation('сколько налогов с 3 млн?'),{kind:'calc',amount:3e6});
  assert.deepEqual(textCalculation('сколько налогов с 3 млн за полугодие'),{kind:'calc',amount:3e6});
  assert.deepEqual(textCalculation('самозанятый доход 300 тыс'),{kind:'self',amount:300000});
  assert.deepEqual(textCalculation('зарплата 300000'),{kind:'salary',amount:300000});
  for(const s of ['что такое 910','налог по форме 910','налог 910','доход 3 млн или 5 млн','налог -10000','налог 01/10/2026','налог 300000abc','налог в 2026']) assert.equal(textCalculation(s),null,s);
  assert.equal(startTag('bind_secret'),'bind');assert.equal(startTag('reset_person@example.invalid'),'reset');
  assert.equal(startTag('campaign_42'),'campaign_42');assert.equal(startTag('personal text'),'other');
});

test('Telegram transport detects API, HTTP, malformed, connection and wall-clock failures without leaking token',async()=>{
  const client = (status,body) => ({request(_opts,cb){const req=new EventEmitter();req.destroy=()=>{};req.end=()=>{
    const res=new EventEmitter();res.statusCode=status;cb(res);res.emit('data',body);res.emit('end');};return req;}});
  assert.equal((await createBotRequest({token:'secret',client:client(200,'{"ok":true,"result":{}}')})('sendMessage',{})).ok,true);
  for(const [status,body] of [[200,'{"ok":false,"error_code":400,"description":"secret"}'],[500,'{"ok":true}'],[200,'bad json']]) {
    const r=await createBotRequest({token:'secret',client:client(status,body)})('sendMessage',{});
    assert.equal(r.ok,false);assert(!JSON.stringify(r).includes('secret'));assert.throws(()=>requireTelegramSuccess(r));
  }
  let destroyed=false;
  const stalled={request(){const r=new EventEmitter();r.end=()=>{};r.destroy=()=>{destroyed=true;};return r;}};
  assert.equal((await createBotRequest({token:'secret',client:stalled,timeoutMs:20})('sendMessage',{})).error_code,504);
  assert(destroyed);
  const broken={request(){throw Error('secret');}};
  assert.equal((await createBotRequest({token:'secret',client:broken})('sendMessage',{})).ok,false);
});

test('bot foundation: real SQL and HTTP with synthetic Telegram delivery',async t=>{
  const pg=new PGlite();t.after(()=>pg.close());
  // Serialize transactions on PGlite's one connection. Production pg uses dedicated clients.
  let queue=Promise.resolve();
  const db={query:(q,p)=>pg.query(q,p),connect:async()=>{
    const previous=queue;let release;queue=new Promise(r=>release=r);await previous;
    return {query:(q,p)=>pg.query(q,p),release};
  }};
  await pg.exec(`CREATE TABLE users(id UUID PRIMARY KEY,email TEXT UNIQUE,name TEXT,tier TEXT NOT NULL DEFAULT 'free',
    password_hash TEXT,telegram_chat_id TEXT UNIQUE,telegram_username TEXT,telegram_linked_at TIMESTAMPTZ);
    CREATE TABLE bot_users(chat_id TEXT PRIMARY KEY,linked_user_id UUID REFERENCES users(id),queries_today INT NOT NULL DEFAULT 0,last_query_date TEXT,created_at TIMESTAMPTZ DEFAULT NOW(),reminders_on BOOLEAN DEFAULT false);
    CREATE TABLE leads(id BIGSERIAL PRIMARY KEY,phone TEXT,name TEXT,tg_chat_id TEXT,tg_username TEXT,esep_user_id UUID,source TEXT DEFAULT 'tg_bot',intent TEXT DEFAULT 'unknown',status TEXT DEFAULT 'new',notes TEXT,last_activity_at TIMESTAMPTZ DEFAULT NOW(),created_at TIMESTAMPTZ DEFAULT NOW());
    CREATE UNIQUE INDEX leads_tg_uq ON leads(tg_chat_id) WHERE tg_chat_id IS NOT NULL;
    CREATE TABLE tax_config(key TEXT,value TEXT);
    CREATE TABLE telegram_bind_token(token TEXT PRIMARY KEY,user_id UUID REFERENCES users(id),expires_at TIMESTAMPTZ,consumed_at TIMESTAMPTZ,consumed_chat_id TEXT,consumed_username TEXT);
    CREATE TABLE auth_security_log(user_id UUID,event TEXT,meta JSONB);
    CREATE TABLE marketing_posts(id INT PRIMARY KEY,title TEXT,body TEXT,platform TEXT NOT NULL DEFAULT 'telegram',posted BOOLEAN DEFAULT false,posted_at TIMESTAMPTZ);
  `);
  await pg.exec(schema);await pg.exec(schema);
  await pg.exec(review.schema);
  await pg.exec(work.schema);
  const store=createBotStore(db);await store.assertReady();
  const calls=[],mutations=[];let sendFailure=null,scheduledTick;
  const context={module:{exports:{}},process:{env:{TELEGRAM_BOT_TOKEN:'fixture',TELEGRAM_ADMIN_CHAT_ID:'999',TELEGRAM_WEBHOOK_SECRET:'x'.repeat(32)}},
    console:{log(){},error(){}},Buffer,setInterval(fn){scheduledTick=fn;return 1;},
    require(name){
      if(name==='../db')return db;
      if(name==='./marketing')return {markPosted:async id=>{mutations.push('posted');await pg.query('UPDATE marketing_posts SET posted=true WHERE id=$1',[id]);}};
      if(name==='./transport')return {requireTelegramSuccess,createBotRequest:()=>async(method,body)=>{
        calls.push({method,...body});if(method==='sendMessage'&&sendFailure?.(body))return {ok:false,error_code:400};return {ok:true,result:{message_id:calls.length,chat:{id:body.chat_id},text:body.text}};
      }};
      if(name==='../jobs/taxMonitor')return {revertLastAutoUpdate:async()=>{mutations.push('revert');return {ok:true};}};
      if(name==='../services/leads_db')return {detectIntent:s=>/бухгалтер|regime_buh/.test(s)?'b2b':'unknown'};
      if(name==='../services/marketing_review')return {...review,canPublish:p=>review.canPublish(p,REVIEW_NOW)};
      if(name==='../services/bot_workspace')return work;
      if(name==='../services/bot_foundation')return {createBotStore:d=>createBotStore(d,{now:()=>REVIEW_NOW})};
      const allowed={'./ui':'../src/bot/ui','./input':'../src/bot/input','../services/telegram_text':'../src/services/telegram_text','../services/bot_foundation':'../src/services/bot_foundation','../routes/telegram-webhook':'../src/routes/telegram-webhook'};
      if(!allowed[name])throw Error('Unexpected dependency '+name);return require(allowed[name]);
    }};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../src/bot/telegram.js'),'utf8'),context);
  const bot=context.module.exports;
  const express=require('express'),app=express();app.use(express.json());
  app.post('/webhook',createTelegramWebhook({secret:'x'.repeat(32),store,handleUpdate:bot.handleUpdate,logger:{error(){}}}));
  app.post('/disabled',createTelegramWebhook({secret:'',store,handleUpdate:bot.handleUpdate}));
  const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));t.after(()=>new Promise(r=>server.close(r)));
  const base=`http://127.0.0.1:${server.address().port}`;let nextId=1;
  const message=(text,id=101)=>({update_id:nextId++,message:{chat:{id,type:'private'},from:{id,first_name:'A < B & C'},text}});
  const callback=(data,id=101)=>({update_id:nextId++,callback_query:{id:'fixture-'+nextId,from:{id},message:{chat:{id,type:'private'}},data}});
  async function post(body,secret='x'.repeat(32),route='/webhook') {
    return fetch(base+route,{method:'POST',headers:{'content-type':'application/json','X-Telegram-Bot-Api-Secret-Token':secret},body:JSON.stringify(body)});
  }
  const responses=id=>calls.filter(c=>c.method==='sendMessage'&&c.chat_id===id).map(c=>c.text);
  await t.test('webhook fails closed and does no work without a valid secret/update',async()=>{
    const n=calls.length;assert.equal((await post(message('/start'),'wrong')).status,403);
    assert.equal((await post(message('/start'),'','/disabled')).status,503);
    assert.equal((await post({update_id:'1'})).status,400);assert.equal(calls.length,n);
    assert.equal((await pg.query('SELECT count(*)::int AS n FROM bot_users')).rows[0].n,0);
  });
  await t.test('first start and repeated start: one contact and one new-user alert',async()=>{
    const u=message('/start');assert.equal((await post(u)).status,200);
    const count=calls.length;assert.equal((await post(u)).status,200);assert.equal(calls.length,count);
    await post(message('/start'));
    assert.equal(calls.filter(c=>c.chat_id==='999'&&c.text.includes('Новый пользователь')).length,1);
    assert(responses(101).some(s=>s.includes('Как будете пользоваться Esep')));
    assert.equal((await pg.query('SELECT count(*)::int AS n FROM leads')).rows[0].n,1);
  });
  await t.test('old lead without bot_users is not announced as new, sales fields survive',async()=>{
    await pg.query("INSERT INTO leads(tg_chat_id,source,status,notes) VALUES('102','existing','qualified','keep')");
    const count=calls.filter(c=>c.chat_id==='999').length;await post(message('/start',102));
    assert.equal(calls.filter(c=>c.chat_id==='999').length,count);
    const l=(await pg.query("SELECT source,status,notes FROM leads WHERE tg_chat_id='102'")).rows[0];
    assert.deepEqual(l,{source:'existing',status:'qualified',notes:'keep'});
  });
  await t.test('deep links, callbacks, source and last activity persist before result',async()=>{
    await post(message('/start calc_5000000',103));
    assert(responses(103).some(s=>s.includes('5 000 000')));
    let r=(await pg.query("SELECT * FROM bot_users WHERE chat_id='103'")).rows[0];assert.equal(r.first_start_payload,'calc_5000000');
    await post(message('/start campaign_42',103));
    await post(callback('regime_buh',103));
    r=(await pg.query("SELECT * FROM bot_users WHERE chat_id='103'")).rows[0];assert.equal(r.first_start_payload,'calc_5000000');assert.equal(r.last_start_payload,'campaign_42');
    assert.equal((await pg.query("SELECT intent FROM leads WHERE tg_chat_id='103'")).rows[0].intent,'b2b');
    await post(message('/start bind_private_token',104));
    assert.equal((await pg.query("SELECT first_start_payload FROM bot_users WHERE chat_id='104'")).rows[0].first_start_payload,'bind');
  });
  await t.test('promised text inputs calculate, form questions do not and bad input does not consume quota',async()=>{
    for(const text of ['5000000','5 000 000','сколько налогов с 3 млн?'])assert.equal((await post(message(text,105))).status,200);
    assert.equal(responses(105).filter(s=>s.includes('Расчёт по упрощёнке')).length,3);
    await post(message('что такое 910',105));await post(message('/calc 5oops',105));await post(message('доход 3 млн или 5 млн',105));
    assert.equal(responses(105).filter(s=>s.includes('Расчёт по упрощёнке')).length,3);
    assert.equal((await pg.query("SELECT queries_today FROM bot_users WHERE chat_id='105'")).rows[0].queries_today,3);
  });
  await t.test('legacy link/reset do not disclose or mutate any account, even after daily limit',async()=>{
    const id=randomUUID();await pg.query("INSERT INTO users(id,email,name,tier,password_hash) VALUES($1,'victim@example.invalid','Secret','accountant','unchanged')",[id]);
    await post(message('/start',106));await pg.query("UPDATE bot_users SET linked_user_id=$1,queries_today=5,last_query_date=$2 WHERE chat_id='106'",[id,new Date(Date.now()+5*3600e3).toISOString().slice(0,10)]);
    for(const text of ['/link victim@example.invalid','/reset victim@example.invalid','/status'])assert.equal((await post(message(text,106))).status,200);
    assert(responses(106).every(s=>!s.includes('victim@example.invalid')&&!s.includes('Secret')));
    assert.equal((await pg.query('SELECT password_hash,telegram_chat_id FROM users WHERE id=$1',[id])).rows[0].password_hash,'unchanged');
    await post(message('5000000',106));assert.match(responses(106).at(-1),/Лимит/);
  });
  await t.test('all privileged callback paths reject non-admin before user tracking',async()=>{
    for(const data of ['tax_auto_revert','tax_ok','tax_auto_ok','pub_channel_1','skip_post_1','wa:list','wa:open:1','wa:status:1:1:closed'])await post(callback(data,107));
    assert.equal(mutations.length,0);assert.equal((await pg.query("SELECT count(*)::int AS n FROM bot_users WHERE chat_id='107'")).rows[0].n,0);
  });
  await t.test('failed Telegram delivery is not acknowledged as success and retry does not recharge',async()=>{
    await post(message('/start',108));const u=message('/calc 300000',108);
    sendFailure=b=>b.chat_id===108;assert.equal((await post(u)).status,503);sendFailure=null;
    assert.equal((await post(u)).status,200);
    assert.equal((await pg.query("SELECT queries_today FROM bot_users WHERE chat_id='108'")).rows[0].queries_today,1);
    assert.equal((await pg.query('SELECT status FROM bot_updates WHERE update_id=$1',[u.update_id])).rows[0].status,'done');
  });
  await t.test('failed public post remains unpublished; admin can retry with a new callback',async()=>{
    const p=review.VAT_POST;
    await pg.query("INSERT INTO marketing_posts(id,title,body,platform,review_state,review_key,content_hash,reviewed_at,review_expires_at) VALUES(1,$1,$2,$3,$4,$5,$6,$7,$8)",[p.title,p.body,p.platform,p.review_state,p.review_key,p.content_hash,p.reviewed_at,p.review_expires_at]);
    const publish='pub_channel_1_'+p.content_hash.slice(0,16);
    const before=calls.length;await post(callback('pub_channel_1',999));
    assert.equal(calls.slice(before).filter(c=>c.chat_id==='@esepfinancialsupport').length,0);
    sendFailure=b=>b.chat_id==='@esepfinancialsupport';await post(callback(publish,999));sendFailure=null;
    assert.equal((await pg.query('SELECT posted FROM marketing_posts WHERE id=1')).rows[0].posted,false);
    await post(callback(publish,999));assert.equal((await pg.query('SELECT posted FROM marketing_posts WHERE id=1')).rows[0].posted,true);
    const count=calls.filter(c=>c.chat_id==='@esepfinancialsupport').length;
    await post(callback(publish,999));assert.equal(calls.filter(c=>c.chat_id==='@esepfinancialsupport').length,count);
    const receipt=(await pg.query('SELECT telegram_chat_id,telegram_message_id FROM marketing_posts WHERE id=1')).rows[0];
    assert.equal(receipt.telegram_chat_id,'@esepfinancialsupport');assert(receipt.telegram_message_id>0);
  });
  await t.test('old publish buttons, changed copies and legacy public commands cannot bypass review',async()=>{
    await pg.query("INSERT INTO marketing_posts(id,title,body) VALUES(2,'Old VAT','12%')");
    const count=calls.filter(c=>c.chat_id==='@esepfinancialsupport').length;
    await post(callback('pub_channel_2',999));
    for(const cmd of ['/post_tip','/post_deadline','/post_lead','/post_article','/post_custom 12%'])assert.equal((await post(message(cmd,999))).status,200);
    await assert.rejects(bot.postToChannel('unreviewed'),/MARKETING_REVIEW_REQUIRED/);
    await pg.query("UPDATE marketing_posts SET posted=false,body='changed' WHERE id=1");
    await post(callback('pub_channel_1_'+review.VAT_POST.content_hash.slice(0,16),999));
    assert.equal(calls.filter(c=>c.chat_id==='@esepfinancialsupport').length,count);
    assert.equal((await pg.query('SELECT posted FROM marketing_posts WHERE id=2')).rows[0].posted,false);
  });
  await t.test('private files receive explanation, groups are ignored',async()=>{
    const file=message(undefined,109);file.message.document={file_id:'fixture'};await post(file);assert.match(responses(109).at(-1),/Фото, документы/);
    const group=message('/reset victim@example.invalid',110);group.message.chat.type='group';const n=calls.length;await post(group);assert.equal(calls.length,n);
  });
  await t.test('safe binding consumes token once, replaces old link and rejects expiry',async()=>{
    const id=randomUUID();await pg.query("INSERT INTO users(id,email,tier,telegram_chat_id,telegram_linked_at) VALUES($1,'owner@example.invalid','accountant','111',NOW())",[id]);
    await pg.query("INSERT INTO bot_users(chat_id,linked_user_id) VALUES('111',$1)",[id]);
    await pg.query("INSERT INTO telegram_bind_token(token,user_id,expires_at) VALUES('valid',$1,NOW()+INTERVAL '5 minutes'),('expired',$1,NOW()-INTERVAL '1 minute')",[id]);
    await post(callback('bind_yes:valid',112));await post(callback('bind_yes:valid',113));await post(callback('bind_yes:expired',113));
    assert.equal((await pg.query('SELECT telegram_chat_id FROM users WHERE id=$1',[id])).rows[0].telegram_chat_id,'112');
    assert.equal((await pg.query("SELECT linked_user_id FROM bot_users WHERE chat_id='111'")).rows[0].linked_user_id,null);
    assert.equal((await pg.query("SELECT count(*)::int AS n FROM auth_security_log WHERE event='tg_bind_confirmed'")).rows[0].n,1);
    assert.equal(await store.verifiedAccount(111),null);assert.equal((await store.verifiedAccount(112)).id,id);
  });
  await t.test('in-flight duplicate is retriable; successful receipt survives a new store instance',async()=>{
    const update={update_id:99999};let enter,finish;const entered=new Promise(r=>enter=r),blocked=new Promise(r=>finish=r);let runs=0;
    const first=store.processUpdate(update,async()=>{runs++;enter();await blocked;});await entered;
    await assert.rejects(store.processUpdate(update,async()=>runs++),/IN_PROGRESS/);finish();await first;
    await createBotStore(db).processUpdate(update,async()=>runs++);assert.equal(runs,1);
  });
  await t.test('button and deep-link calculations obey the limit; reference help remains available',async()=>{
    for(let i=0;i<5;i++)await post(callback('demo_calc_5000000',120));
    await post(message('/start calc_5000000',120));assert.match(responses(120).at(-1),/Лимит/);
    await post(message('/help',120));assert.match(responses(120).at(-1),/разберёмся по шагам/);
    assert.equal((await pg.query("SELECT queries_today FROM bot_users WHERE chat_id='120'")).rows[0].queries_today,5);
  });
  await t.test('binding rollback leaves account and token unchanged if audit persistence fails',async()=>{
    const id=randomUUID();await pg.query("INSERT INTO users(id,email) VALUES($1,'rollback@example.invalid')",[id]);
    await pg.query("INSERT INTO telegram_bind_token(token,user_id,expires_at) VALUES('rollback',$1,NOW()+INTERVAL '5 minutes')",[id]);
    const faulty={...db,connect:async()=>{const c=await db.connect();return {release:()=>c.release(),query:(q,p)=>{
      if(q.includes('INSERT INTO auth_security_log'))throw Error('fixture failure');return c.query(q,p);
    }};}};
    await assert.rejects(createBotStore(faulty).confirmBinding('rollback',121,'fixture'),/fixture failure/);
    assert.equal((await pg.query('SELECT telegram_chat_id FROM users WHERE id=$1',[id])).rows[0].telegram_chat_id,null);
    assert.equal((await pg.query("SELECT consumed_at FROM telegram_bind_token WHERE token='rollback'")).rows[0].consumed_at,null);
  });
  await t.test('home tasks are attached to the message and every main button works without quota charges',async()=>{
    const ui=require('../src/bot/ui');
    await post(message('/menu',130));
    const home=calls.filter(c=>c.chat_id===130&&c.method==='sendMessage').at(-1);
    assert.equal(home.reply_markup.keyboard,undefined);
    const buttons=home.reply_markup.inline_keyboard.flat();assert.equal(buttons.length,3);
    assert.match(home.text,/кнопку под этим сообщением/);
    assert(!home.text.includes('/salary'));
    for(const button of buttons){
      const pressed=callback(button.callback_data,130);
      assert.equal((await post(pressed)).status,200,button.text);
      assert(calls.some(c=>c.method==='answerCallbackQuery'&&c.callback_query_id===pressed.callback_query.id));
      assert(!responses(130).at(-1).includes('разберёмся по шагам'),button.text);
    }
    for(const label of Object.values(ui.labels))assert.equal((await post(message(label,130))).status,200,label);
    assert.equal((await pg.query("SELECT queries_today FROM bot_users WHERE chat_id='130'")).rows[0].queries_today,0);
    assert.equal((await pg.query("SELECT intent FROM leads WHERE tg_chat_id='130'")).rows[0].intent,'b2b');
  });
  await t.test('salary and self prompts accept bare amounts and persist across bot process reload',async()=>{
    await post(callback('prompt_salary',131));await post(message('300 000',131));
    assert.match(responses(131).at(-1),/Расчёт зарплаты/);
    await post(callback('prompt_self',131));
    const reloaded={...context,module:{exports:{}}};
    vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../src/bot/telegram.js'),'utf8'),reloaded);
    const update=message('300 тыс',131);
    await store.processUpdate(update,reloaded.module.exports.handleUpdate);
    assert.match(responses(131).at(-1),/Режим самозанятого/);
    assert.equal((await pg.query("SELECT queries_today FROM bot_users WHERE chat_id='131'")).rows[0].queries_today,2);
  });
  await t.test('invalid amounts retain selection; explicit commands override; cancel and expiry do not silently reuse selection',async()=>{
    await post(callback('prompt_salary',132));await post(message('300 или 500',132));
    assert.match(responses(132).at(-1),/зарплата начислена/);
    assert.equal((await pg.query("SELECT queries_today FROM bot_users WHERE chat_id='132'")).rows[0].queries_today,0);
    await post(message('/self 300000',132));assert.match(responses(132).at(-1),/Режим самозанятого/);
    await post(message('/cancel',132));assert.equal(await store.calculationKind(132),null);
    await post(callback('prompt_salary',132));
    await pg.query("UPDATE bot_users SET calculation_expires_at=NOW()-INTERVAL '1 minute' WHERE chat_id='132'");
    await post(message('300000',132));assert.match(responses(132).at(-1),/Выберите расчёт ещё раз/);
    assert.equal((await pg.query("SELECT queries_today FROM bot_users WHERE chat_id='132'")).rows[0].queries_today,1);
  });
  await t.test('sample buttons obey quota and exhausted callback is acknowledged',async()=>{
    for(let i=0;i<5;i++)await post(callback('run_salary_300000',133));
    const blocked=callback('run_self_300000',133);await post(blocked);
    assert.match(responses(133).at(-1),/Лимит/);
    assert(calls.some(c=>c.method==='answerCallbackQuery'&&c.callback_query_id===blocked.callback_query.id));
    assert.equal((await pg.query("SELECT queries_today FROM bot_users WHERE chat_id='133'")).rows[0].queries_today,5);
  });
  await t.test('selection ordering recovers after a week without activity, including cancelled state',async()=>{
    await post(message('/menu',137));
    await pg.query("UPDATE bot_users SET calculation_update_id=9999999,calculation_updated_at=NOW()-INTERVAL '8 days' WHERE chat_id='137'");
    await post(callback('prompt_salary',137));
    assert.equal(await store.calculationKind(137),'salary');
    await post(message('300000',137));assert.match(responses(137).at(-1),/Расчёт зарплаты/);
  });
  await t.test('failed bare-amount delivery retries original calculation even after another menu choice',async()=>{
    await post(callback('prompt_self',134));const u=message('300000',134);
    sendFailure=b=>b.chat_id===134;assert.equal((await post(u)).status,503);sendFailure=null;
    await post(callback('prompt_salary',134));assert.equal((await post(u)).status,200);
    assert.match(responses(134).at(-1),/Режим самозанятого/);
    assert.equal(await store.calculationKind(134),'salary');
    assert.equal((await pg.query("SELECT queries_today FROM bot_users WHERE chat_id='134'")).rows[0].queries_today,1);
    const count=responses(134).length;await post(u);assert.equal(responses(134).length,count);
  });
  await t.test('menu selections are isolated per user and unknown buttons recover to home',async()=>{
    await post(callback('prompt_self',135));await post(callback('prompt_salary',136));
    await post(message('300000',135));await post(message('300000',136));
    assert.match(responses(135).at(-1),/Режим самозанятого/);assert.match(responses(136).at(-1),/Расчёт зарплаты/);
    await post(callback('obsolete_button',135));assert.match(responses(135).at(-1),/разберёмся по шагам/);
    for(const data of ['ui:reference','ui:form910','ui:commands','ui:help','ui:link','ui:menu'])assert.equal((await post(callback(data,135))).status,200);
  });
  await t.test('document flow through HTTP persists before receipt, survives failed delivery and resumes after reload',async()=>{
    const id=150,last=()=>calls.filter(c=>c.chat_id===id&&c.method==='sendMessage').at(-1);
    const press=async label=>{const b=last().reply_markup.inline_keyboard.flat().find(b=>label.test(b.text));assert(b,String(label));return post(callback(b.callback_data,id));};
    await post(message('/start docs_ig',id));assert.match(last().text,/Для кого/);
    await press(/Для клиентов/);await post(message('Клиент Тест',id));await post(message('09.2026',id));await press(/Выписка банка/);
    const save=callback(last().reply_markup.inline_keyboard.flat().find(b=>b.text==='Сохранить список').callback_data,id);
    sendFailure=b=>b.chat_id===id;assert.equal((await post(save)).status,503);sendFailure=null;
    let tasks=(await pg.query('SELECT * FROM bot_document_tasks WHERE chat_id=$1',[String(id)])).rows;
    assert.equal(tasks.length,1);assert.equal(tasks[0].client_name,'Клиент Тест');
    assert.equal((await post(save)).status,200);assert.match(last().text,/Список сохранён/);
    assert.equal((await pg.query('SELECT count(*)::int AS n FROM bot_document_tasks WHERE chat_id=$1',[String(id)])).rows[0].n,1);
    await press(/Текст запроса/);assert.match(last().text,/не отправлял сообщение клиенту/);assert.match(last().text,/Выписка банка/);
    const reloaded={...context,module:{exports:{}}};vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../src/bot/telegram.js'),'utf8'),reloaded);
    const update=message('/my@EsepKZ_bot',id);await store.processUpdate(update,reloaded.module.exports.handleUpdate);assert.match(last().text,/Мои задачи/);
    await press(/Клиент Тест/);await press(/Обсудить с Esep/);await press(/1–5/);await post(message('Хочу контролировать документы клиентов',id));
    assert.equal((await pg.query('SELECT count(*)::int AS n FROM bot_service_requests WHERE chat_id=$1',[String(id)])).rows[0].n,0);
    await press(/Отправить заявку/);assert.match(last().text,/Заявка №\d+ сохранена/);
    const request=(await pg.query('SELECT * FROM bot_service_requests WHERE chat_id=$1',[String(id)])).rows[0];assert.equal(String(request.task_id),String(tasks[0].id));assert.deepEqual(request.context.pending,['Выписка банка']);
    assert.equal((await pg.query('SELECT first_start_payload,queries_today FROM bot_users WHERE chat_id=$1',[String(id)])).rows[0].first_start_payload,'docs_ig');
    assert.equal((await pg.query('SELECT queries_today FROM bot_users WHERE chat_id=$1',[String(id)])).rows[0].queries_today,0);
    await post(message('/requests',999));assert.match(responses(999).at(-1),/Обращения в Esep/);
    await post(callback('wa:open:'+request.id,999));assert.match(responses(999).at(-1),/Хочу контролировать/);
  });
  await t.test('ordinary menu labels pause the draft and old reminder buttons use the new workspace',async()=>{
    await post(message('/docs',151));await post(callback('ws:role:1:clients',151));
    await post(message('🧮 Рассчитать',151));assert.match(responses(151).at(-1),/Что рассчитать/);
    assert.equal((await pg.query("SELECT active FROM bot_work_sessions WHERE chat_id='151'")).rows[0].active,false);
    await post(callback('remind_on',151));assert.match(responses(151).at(-1),/Мои задачи/);
    assert.equal((await pg.query("SELECT count(*)::int AS n FROM bot_task_reminders WHERE chat_id='151'")).rows[0].n,0);
    await post(callback('remind_off',151));assert.match(responses(151).at(-1),/Будущие напоминания отключены/);
  });
  await t.test('old public posting hours no longer publish directly to the channel',async()=>{
    bot.startChannelScheduler();assert.equal(typeof scheduledTick,'function');
    const count=calls.filter(c=>c.chat_id==='@esepfinancialsupport').length;
    for(const timestamp of ['2026-11-01T04:00:00Z','2026-10-12T05:00:00Z','2026-10-14T07:00:00Z','2026-10-12T09:00:00Z']){
      context.Date=class extends Date{constructor(...args){super(...(args.length?args:[timestamp]));}};
      await scheduledTick();
    }
    assert.equal(calls.filter(c=>c.chat_id==='@esepfinancialsupport').length,count);
  });
});
