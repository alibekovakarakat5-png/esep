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
    CREATE TABLE marketing_posts(id INT PRIMARY KEY,title TEXT,body TEXT,posted BOOLEAN DEFAULT false,posted_at TIMESTAMPTZ);
  `);
  await pg.exec(schema);await pg.exec(schema);
  const store=createBotStore(db);await store.assertReady();
  const calls=[],mutations=[];let sendFailure=null;
  const context={module:{exports:{}},process:{env:{TELEGRAM_BOT_TOKEN:'fixture',TELEGRAM_ADMIN_CHAT_ID:'999',TELEGRAM_WEBHOOK_SECRET:'x'.repeat(32)}},
    console:{log(){},error(){}},Buffer,setInterval(){throw Error('Unexpected scheduler');},
    require(name){
      if(name==='../db')return db;
      if(name==='./marketing')return {markPosted:async id=>{mutations.push('posted');await pg.query('UPDATE marketing_posts SET posted=true WHERE id=$1',[id]);}};
      if(name==='./transport')return {requireTelegramSuccess,createBotRequest:()=>async(method,body)=>{
        calls.push({method,...body});if(method==='sendMessage'&&sendFailure?.(body))return {ok:false,error_code:400};return {ok:true,result:{}};
      }};
      if(name==='../jobs/taxMonitor')return {revertLastAutoUpdate:async()=>{mutations.push('revert');return {ok:true};}};
      if(name==='../services/leads_db')return {detectIntent:s=>/бухгалтер|regime_buh/.test(s)?'b2b':'unknown'};
      const allowed={'./input':'../src/bot/input','../services/telegram_text':'../src/services/telegram_text','../services/bot_foundation':'../src/services/bot_foundation','../routes/telegram-webhook':'../src/routes/telegram-webhook'};
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
    assert(responses(101).some(s=>s.includes('A &lt; B &amp; C')));
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
    for(const text of ['/link victim@example.invalid','/reset victim@example.invalid','/status'])await post(message(text,106));
    assert(responses(106).every(s=>!s.includes('victim@example.invalid')&&!s.includes('Secret')));
    assert.equal((await pg.query('SELECT password_hash,telegram_chat_id FROM users WHERE id=$1',[id])).rows[0].password_hash,'unchanged');
    await post(message('5000000',106));assert.match(responses(106).at(-1),/Лимит/);
  });
  await t.test('all privileged callback paths reject non-admin before user tracking',async()=>{
    for(const data of ['tax_auto_revert','tax_ok','tax_auto_ok','pub_channel_1','skip_post_1'])await post(callback(data,107));
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
    await pg.query("INSERT INTO marketing_posts(id,title,body,posted) VALUES(1,'A < B','C & D',false)");
    sendFailure=b=>b.chat_id==='@esepfinancialsupport';await post(callback('pub_channel_1',999));sendFailure=null;
    assert.equal((await pg.query('SELECT posted FROM marketing_posts WHERE id=1')).rows[0].posted,false);
    await post(callback('pub_channel_1',999));assert.equal((await pg.query('SELECT posted FROM marketing_posts WHERE id=1')).rows[0].posted,true);
    const count=calls.filter(c=>c.chat_id==='@esepfinancialsupport').length;
    await post(callback('pub_channel_1',999));assert.equal(calls.filter(c=>c.chat_id==='@esepfinancialsupport').length,count);
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
    await post(message('/help',120));assert.match(responses(120).at(-1),/Команды/);
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
});
