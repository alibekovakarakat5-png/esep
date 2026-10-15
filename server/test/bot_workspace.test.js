'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {PGlite}=require('@electric-sql/pglite');
const {schema,createWorkspace,parseDate,parsePeriod}=require('../src/services/bot_workspace');

test('workspace dates reject ambiguity, impossible dates and already elapsed local 09:00',()=>{
 const now=new Date('2026-10-10T12:00:00Z');
 assert.equal(parseDate('11.10.2026',now).toISOString(),'2026-10-11T04:00:00.000Z');
 for(const s of ['31.02.2027','10.10.2026','11/10/2026','01.01.2029','00.10.2026'])assert.equal(parseDate(s,now),null,s);
 assert.equal(parsePeriod('09.2026'),'2026-09');assert.equal(parsePeriod('13.2026'),null);
});

test('saved document workflow, reminders and consented requests use real SQL',async t=>{
 const pg=new PGlite();t.after(()=>pg.close());
 let queue=Promise.resolve();
 const db={connect:async()=>{const before=queue;let release;queue=new Promise(r=>release=r);await before;return {query:(q,p)=>pg.query(q,p),release};}};
 db.query=async(q,p)=>{const c=await db.connect();try{return await c.query(q,p);}finally{c.release();}};
 await pg.exec("CREATE TABLE bot_users(chat_id TEXT PRIMARY KEY,first_start_payload TEXT,reminders_on BOOLEAN DEFAULT false);INSERT INTO bot_users VALUES('101','docs_ig',true),('999',null,true)");
 await pg.exec(schema);await pg.exec(schema);
 let clock=new Date('2026-10-10T12:00:00Z'),sequence=100;
 const options={adminId:'999',now:()=>clock};let app=createWorkspace(db,options);
 await app.assertReady();
 const row=async(q,p)=>(await db.query(q,p)).rows[0];
 const act=(id,input,updateId=sequence++)=>app.handle({chatId:id,updateId,username:'fixture_user',...(typeof input==='string'?(input.startsWith('ui:')||input.startsWith('ws:')||input.startsWith('wa:')?{data:input}:{text:input}):input)});
 const button=(v,pattern)=>{const b=v.extra.reply_markup.inline_keyboard.flat().find(b=>pattern.test(b.text));assert(b,'button '+pattern+' in '+v.text);return b.callback_data;};
 const click=(id,v,p)=>act(id,button(v,p));
 async function newTask(id,name='Клиент <А>'){
  let v=await act(id,'/docs');if(v.text.includes('Для кого'))v=await click(id,v,/Для клиентов/);
  v=await act(id,name);v=await act(id,'09.2026');v=await click(id,v,/Выписка банка/);v=await click(id,v,/Акты и накладные/);
  const save=button(v,/Сохранить список/),updateId=sequence++;
  const card=await act(id,save,updateId);const task=await row('SELECT * FROM bot_document_tasks WHERE chat_id=$1 ORDER BY id DESC LIMIT 1',[String(id)]);
  return {card,task,save,updateId};
 }
 async function remind(id,taskId,date='11.10.2026'){await act(id,`ws:remind:${taskId}`);return act(id,date);}
 async function request(id,taskId=0){let v=await act(id,`ws:request:${taskId}`);v=await click(id,v,/6–20/);return act(id,'Хочу видеть, что осталось собрать по 8 клиентам.');}

 await t.test('welcome persists explicit role, preserves direct tasks and replays updates',async()=>{
  let v=await act(808,'/start');assert.match(v.text,/Как будете пользоваться/);
  const updateId=sequence++;v=await act(808,'ws:welcomeRole:clients',updateId);
  assert.match(v.text,/расчётом для клиента/);
  assert.deepEqual(await act(808,'ws:welcomeRole:clients',updateId),v);
  app=createWorkspace(db,options);
  assert.match((await act(808,'/start')).text,/расчётом для клиента/);
  v=await act(808,'как перейти в Esep?');
  const url=v.extra.reply_markup.inline_keyboard.flat().find(b=>b.url).url;
  assert.equal(url,'https://app.esepkz.com/#/welcome?role=clients');
  assert.match(v.text,/не переносятся автоматически/);
  assert.equal(await act(808,'/start bind_private'),null);
  assert.equal(await act(808,'/start calc_300000'),null);
  assert.equal(await act(808,'/start CALC_300000'),null);
  await act(808,'/docs');await act(808,'Мой клиент');
  v=await act(808,'что умеешь');assert.match(v.text,/месяц|ММ.ГГГГ|Не получилось/);
  assert.equal((await row("SELECT role FROM bot_work_profiles WHERE chat_id='808'")).role,'clients');
  await act(809,'/start');await act(809,'ws:welcomeRole:unknown');
  assert.match((await act(809,'/start')).text,/Выберите, с чем нужна помощь/);
 });
 await t.test('three-action menu keeps role on return and every guide branch has a next step',async()=>{
  let v=await act(810,'/start');await act(810,'ws:welcomeRole:clients');
  for(const entry of ['/menu','ui:menu','ws:home','/start']){
   v=await act(810,entry);
   assert.match(v.text,/расчётом для клиента/);
   assert.deepEqual(v.extra.reply_markup.inline_keyboard.flat().map(b=>b.callback_data),['ui:calculators','ws:guide:question','ws:guide:next']);
  }
  for(const topic of ['question','next','payments','reporting','value','docs','app']){
   v=await act(810,'ws:guide:'+topic);
   const buttons=v.extra.reply_markup.inline_keyboard.flat();
   assert(buttons.length>=2);
   assert(!buttons.some(b=>['ws:new','ws:list'].includes(b.callback_data)));
   assert(buttons.some(b=>b.callback_data==='ws:home'));
  }
  assert.match((await act(810,'что мне нужно сделать?')).text,/Что сейчас нужно решить/);
  assert.match((await act(810,'задать вопрос')).text,/С чем нужна помощь/);
  assert.match((await act(810,'ws:guide:reporting')).text,/не полный календарь/);
 });
 let first;
 await t.test('draft validates, survives reload, escapes user text and saves one durable result',async()=>{
  let v=await act(101,'/start docs_ig');assert.match(v.text,/Для кого/);
  v=await click(101,v,/Для клиентов/);v=await act(101,'Клиент <А>');
  v=await act(101,'13.2026');assert.match(v.text,/Не получилось/);
  app=createWorkspace(db,options);v=await act(101,'09.2026');assert.match(v.text,/Клиент &lt;А&gt;/);
  v=await click(101,v,/Выписка банка/);v=await click(101,v,/Акты и накладные/);
  const save=button(v,/Сохранить список/),updateId=sequence++;
  v=await act(101,save,updateId);assert.match(v.text,/Список сохранён/);
  const duplicate=await act(101,save,updateId);assert.deepEqual(duplicate,v);
  await act(101,save);assert.equal((await row("SELECT COUNT(*)::int AS n FROM bot_document_tasks WHERE chat_id='101'")).n,1);
  first=await row("SELECT * FROM bot_document_tasks WHERE chat_id='101'");
  v=await act(101,`ws:open:${first.id}`);const token=button(v,/Выписка банка/);await act(101,token);await act(101,token);
  first=await row('SELECT * FROM bot_document_tasks WHERE id=$1',[first.id]);assert.equal(first.items[0].done,true);assert.equal(first.items[1].done,false);
  v=await act(101,`ws:text:${first.id}`);assert(!v.text.includes('• Выписка банка'));assert(v.text.includes('• Акты и накладные'));
  assert.match(v.text,/не отправлял/);
 });
 await t.test('another user cannot read, mutate, repeat or request help on a foreign task',async()=>{
  for(const action of ['open','text','item','remind','off','archive','repeat','request']){
   const v=await act(202,`ws:${action}:${first.id}:${first.revision}:0:0`);assert.match(v.text,/недоступен/);assert(!v.text.includes('Клиент'));
  }
  assert.equal((await row('SELECT * FROM bot_document_tasks WHERE id=$1',[first.id])).items[0].done,true);
  assert.equal((await row("SELECT COUNT(*)::int AS n FROM bot_service_requests")).n,0);
  assert.match((await act(202,'ws:open:not-a-number')).text,/недоступна/);
 });
 await t.test('a completed task cancels its reminder, and repeating resets every item',async()=>{
  let v=await remind(101,first.id);assert.match(v.text,/11.10.2026/);
  v=await act(101,`ws:open:${first.id}`);await click(101,v,/Акты и накладные/);
  assert.equal((await row('SELECT state FROM bot_task_reminders WHERE task_id=$1',[first.id])).state,'cancelled');
  assert.equal((await row('SELECT status FROM bot_document_tasks WHERE id=$1',[first.id])).status,'done');
  v=await act(101,`ws:repeat:${first.id}`);v=await click(101,v,/Сохранить список/);
  const repeated=await row('SELECT * FROM bot_document_tasks WHERE repeat_of=$1',[first.id]);assert.equal(repeated.period,'2026-10');assert(repeated.items.every(i=>!i.done));
  await act(101,`ws:repeat:${first.id}`);assert.equal((await row('SELECT COUNT(*)::int AS n FROM bot_document_tasks WHERE repeat_of=$1',[first.id])).n,1);
 });
 await t.test('pause returns numeric input to the calculator; draft can be resumed after process reload',async()=>{
  await act(303,'/docs');let v=await act(303,'ws:role:1:own');v=await act(303,'Мой магазин');
  assert.match((await act(303,'/menu')).text,/разберёмся по шагам/);assert.equal(await act(303,'300000'),null);
  app=createWorkspace(db,options);v=await act(303,'/my');v=await click(303,v,/Продолжить черновик/);assert.match(v.text,/За какой месяц/);
 });
 await t.test('requests require explicit consent and survive retries and failed owner notification',async()=>{
  let v=await request(101,first.id);assert.match(v.text,/разрешаете/);
  assert.equal((await row('SELECT COUNT(*)::int AS n FROM bot_service_requests')).n,0);
  const submit=button(v,/Отправить заявку/),updateId=sequence++;
  v=await act(101,submit,updateId);assert.match(v.text,/Заявка №/);
  assert.deepEqual(await act(101,submit,updateId),v);await act(101,submit);
  const r=await row('SELECT * FROM bot_service_requests');assert.equal(r.role,'clients');assert.equal(r.client_count,'6-20');assert(r.consent_at);assert.equal(r.context.taskLabel,'Клиент <А> · 09.2026');
  assert.equal((await row('SELECT COUNT(*)::int AS n FROM bot_service_requests')).n,1);
  let sends=0;await app.dispatch(async()=>{sends++;throw Object.assign(Error('failed'),{telegramCode:403});});
  assert.equal(sends,1);assert.equal((await row('SELECT * FROM bot_service_requests')).notification_state,'failed');
  assert.match((await act(999,'/requests')).text,/Обращения/);v=await act(999,`wa:open:${r.id}`);assert.match(v.text,/Хочу видеть/);
  assert.equal((await act(202,`ws:receipt:${r.id}`)).text,'Заявка недоступна.');
  await act(202,`wa:status:${r.id}:1:closed`);assert.equal((await row('SELECT status FROM bot_service_requests')).status,'new');
  await act(999,`wa:status:${r.id}:1:contacted`);assert.equal((await row('SELECT status FROM bot_service_requests')).status,'contacted');
  await act(999,`wa:status:${r.id}:1:closed`);assert.equal((await row('SELECT status FROM bot_service_requests')).status,'contacted');
 });
 await t.test('withdrawn request is not notified and general request keeps its task context separate',async()=>{
  let v=await request(404);v=await click(404,v,/Отправить заявку/);v=await click(404,v,/Отменить заявку/);assert.match(v.text,/Отменена/);
  let sends=0;await app.dispatch(async()=>{sends++;});assert.equal(sends,0);
  assert.equal((await row("SELECT notification_state FROM bot_service_requests WHERE chat_id='404'")).notification_state,'cancelled');
 });
 await t.test('reminders send only when due, once across concurrent workers, with a Telegram receipt',async()=>{
  const {task}=await newTask(505,'Тест напоминания');await remind(505,task.id);
  const calls=[];const send=async(chat,text)=>{calls.push({chat,text});return {ok:true,result:{message_id:calls.length,chat:{id:chat}}};};
  await app.dispatch(send);assert.equal(calls.length,0);
  clock=new Date('2026-10-11T04:01:00Z');await Promise.all([app.dispatch(send),createWorkspace(db,options).dispatch(send)]);
  assert.equal(calls.length,1);assert.equal(calls[0].chat,'505');assert.match(calls[0].text,/Осталось документов: 2/);
  const r=await row('SELECT * FROM bot_task_reminders WHERE task_id=$1',[task.id]);assert.equal(r.state,'sent');assert(r.delivered_at);assert.equal(r.message_id,1);
  await app.dispatch(send);assert.equal(calls.length,1);
 });
 await t.test('uncertain delivery is not marked sent or automatically duplicated, including a crash after send',async()=>{
  clock=new Date('2026-10-10T12:00:00Z');const {task}=await newTask(606);await remind(606,task.id);clock=new Date('2026-10-11T04:01:00Z');
  let calls=0;const timeout=async()=>{calls++;throw Object.assign(Error('timeout'),{telegramCode:504});};
  await app.dispatch(timeout);await app.dispatch(timeout);assert.equal(calls,1);
  assert.equal((await row('SELECT state FROM bot_task_reminders WHERE task_id=$1',[task.id])).state,'uncertain');
  assert.match((await act(606,`ws:open:${task.id}`)).text,/не подтверждена/);
  const {task:task2}=await newTask(607);await remind(607,task2.id,'12.10.2026');clock=new Date('2026-10-12T04:01:00Z');
  let fail=true;const broken={...db,connect:async()=>{const c=await db.connect();return {...c,query:(q,p)=>{if(fail&&q.includes('UPDATE bot_task_reminders SET state=$2')){fail=false;throw Error('commit path lost');}return c.query(q,p);}};}};
  const send=async(chat)=>{calls++;return {ok:true,result:{message_id:42,chat:{id:chat}}};};
  await assert.rejects(createWorkspace(broken,options).dispatch(send),/commit path lost/);
  assert.equal((await row('SELECT state FROM bot_task_reminders WHERE task_id=$1',[task2.id])).state,'sending');
  await db.query("UPDATE bot_task_reminders SET attempted_at=NOW()-INTERVAL '6 minutes' WHERE task_id=$1",[task2.id]);
  await app.dispatch(send);assert.equal(calls,2);assert.equal((await row('SELECT state FROM bot_task_reminders WHERE task_id=$1',[task2.id])).state,'uncertain');
 });
 await t.test('disable-all prevents future reminders; legacy subscription alone never sends',async()=>{
  clock=new Date('2026-10-10T12:00:00Z');const {task}=await newTask(707);await remind(707,task.id);await act(707,'ws:offAll');clock=new Date('2026-10-11T04:01:00Z');
  let sends=0;await app.dispatch(async()=>{sends++;});assert.equal(sends,0);
  assert.equal((await row("SELECT reminders_on FROM bot_users WHERE chat_id='101'")).reminders_on,true);
 });
 await t.test('completion between the durable claim and delivery prevents the reminder',async()=>{
  clock=new Date('2026-10-10T12:00:00Z');const {task}=await newTask(808);await remind(808,task.id);clock=new Date('2026-10-11T04:01:00Z');
  let claimed=false,completed=false,sends=0;
  const interrupted={...db,connect:async()=>{const c=await db.connect();return {...c,query:async(q,p)=>{
   const r=await c.query(q,p);if(q.includes("SET state='sending',attempted_at"))claimed=true;
   if(q==='COMMIT'&&claimed&&!completed){completed=true;await c.query("UPDATE bot_document_tasks SET status='done' WHERE id=$1",[task.id]);}return r;
  }};}};
  await createWorkspace(interrupted,options).dispatch(async()=>{sends++;});assert(completed);assert.equal(sends,0);
  assert.equal((await row('SELECT state FROM bot_task_reminders WHERE task_id=$1',[task.id])).state,'cancelled');
 });
 await t.test('owner notification stores a receipt and is not sent again',async()=>{
  let v=await request(909);await click(909,v,/Отправить заявку/);const calls=[];
  const send=async(chat,text)=>{calls.push({chat,text});return {ok:true,result:{message_id:91,chat:{id:chat}}};};
  await app.dispatch(send);await app.dispatch(send);assert.equal(calls.length,1);assert.equal(calls[0].chat,'999');assert.match(calls[0].text,/Хочу видеть/);
  const r=await row("SELECT * FROM bot_service_requests WHERE chat_id='909'");assert.equal(r.notification_state,'sent');assert.equal(r.message_id,91);assert(r.notified_at);
 });
 await t.test('delivery metrics require a matching receipt and do not double count retries',async()=>{
  await app.recordDelivered(101,12345,{ok:false});await app.recordDelivered(101,12345,{ok:true,result:{message_id:4,chat:{id:202}}});
  assert.equal((await row("SELECT COUNT(*)::int AS n FROM bot_work_events WHERE event='result_delivered'")).n,0);
  const receipt={ok:true,result:{message_id:4,chat:{id:101}}};await app.recordDelivered(101,12345,receipt);await app.recordDelivered(101,12345,receipt);
  assert.equal((await row("SELECT COUNT(*)::int AS n FROM bot_work_events WHERE event='result_delivered'")).n,1);
 });
 await t.test('audience distinguishes declared role and actions, hides data from non-admin, excludes owner',async()=>{
  await db.query("UPDATE bot_work_events SET created_at=NOW()-INTERVAL '2 days' WHERE chat_id='101' AND event='task_saved'");
  const v=await act(999,'/audience');assert.match(v.text,/Для клиентов/);assert.match(v.text,/Отправили заявку/);assert.match(v.text,/docs_ig: 1/);
  assert.match(v.text,/Вернулись к спискам в другой день: 1 чел/);assert.match(v.text,/Ответ бота доставлен: 1 чел., 1 действий/);
  assert.match((await act(202,'/audience')).text,/только владельцу/);
  const events=(await db.query('SELECT response FROM bot_work_operations WHERE response IS NOT NULL')).rows;
  for(const {response:r} of events){assert(r.text.length<=4096);for(const b of r.extra.reply_markup.inline_keyboard.flat()){if(b.callback_data)assert(Buffer.byteLength(b.callback_data)<=64);}}
 });
});
