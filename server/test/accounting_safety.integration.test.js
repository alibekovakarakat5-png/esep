const {test}=require('node:test');
const assert=require('node:assert/strict');
const {PGlite}=require('@electric-sql/pglite');
const express=require('express');
const {createRouter}=require('../src/routes/esf-recon');
const {createFeeRouter}=require('../src/routes/accounting-fees');
const {migrateEsfAndAccount}=require('../src/services/esf_db');
const {SAFETY_SCHEMA}=require('../src/services/accounting_safety_schema');
const {parseEsfRegistry,parseForm300Notice}=require('../src/services/esf_xlsx_parser');
const ExcelJS=require('exceljs');
const user='11111111-1111-4111-8111-111111111111';
const other='22222222-2222-4222-8222-222222222222';

test('isolated PostgreSQL: migration, HTTP authorisation, imports, rollback and fees',async t=>{
 const pg=new PGlite();
 const db={query:async(sql,args)=>args ? pg.query(sql,args) : (await pg.exec(sql)).at(-1),
  connect:async()=>({query:(sql,args)=>pg.query(sql,args),release(){}})};
 await pg.exec(`CREATE TABLE users(id UUID PRIMARY KEY);
 CREATE TABLE accounting_clients(id TEXT PRIMARY KEY,user_id UUID REFERENCES users(id),name TEXT,
 bin_or_iin TEXT,monthly_fee NUMERIC DEFAULT 10000,is_active BOOLEAN DEFAULT true);
 INSERT INTO users VALUES('${user}'),('${other}');
 INSERT INTO accounting_clients(id,user_id,name,bin_or_iin) VALUES
 ('a','${user}','Alpha','123456789012'),('b','${user}','Beta','234567890123'),('foreign','${other}','Other','345678901234');`);
 await migrateEsfAndAccount(db);
 await pg.exec(SAFETY_SCHEMA); // idempotent
 let registry=[],notice=[];
 const parsers={parseEsfRegistry:async()=>registry,parseForm300Notice:async()=>notice};
 const app=express();app.use(express.json());
 app.use((req,res,next)=>{req.userId=req.headers['x-test-user'];next();});
 app.use('/esf',createRouter(db,parsers));app.use('/fees',createFeeRouter(db));
 app.use('/broken-fees',createFeeRouter({connect:async()=>{throw Error('offline');}}));
 const server=app.listen(0,'127.0.0.1');
 await new Promise(resolve=>server.once('listening',resolve));
 t.after(async()=>{await new Promise(resolve=>server.close(resolve));await pg.close();});
 const base=`http://127.0.0.1:${server.address().port}`;
 async function request(path,method='GET',body,owner=user) {
  const headers={};if(owner) headers['x-test-user']=owner;
  if(body && !(body instanceof FormData)) headers['content-type']='application/json';
  const res=await fetch(base+path,{method,headers,body:body instanceof FormData?body:body?JSON.stringify(body):undefined});
  return {status:res.status,body:await res.json()};
 }
 async function upload(id,kind) {
  const form=new FormData();form.append('file',new Blob(['test']),'same-name.xlsx');
  return request(`/esf/sessions/${id}/${kind}`,'POST',form);
 }
 const newSession=(id)=>request('/esf/sessions','POST',{accounting_client_id:id,period_from:'2026-07-01',period_to:'2026-09-30'});
 let a,b,a2;
 await t.test('requires authentication, valid company and dates',async()=>{
  assert.equal((await request('/esf/sessions','GET',undefined,null)).status,401);
  assert.equal((await newSession('foreign')).status,400);
  assert.equal((await newSession('missing')).status,400);
  assert.equal((await request('/esf/sessions','POST',{accounting_client_id:'a',period_from:'2026-02-30',period_to:'2026-03-31'})).status,400);
  const aa=await newSession('a');assert.equal(aa.status,201);a=aa.body.id;
  b=(await newSession('b')).body.id;a2=(await newSession('a')).body.id;
  assert.equal((await request(`/esf/sessions/${a}`,'GET',undefined,other)).status,404);
  assert.equal((await request(`/esf/sessions/${a}/match`,'POST',{},other)).status,404);
  assert.equal((await request(`/esf/sessions/${a}/results`,'GET',undefined,other)).status,404);
  assert.equal((await request(`/esf/sessions/${a}`,'DELETE',undefined,other)).status,404);
 });
 const row=(buyer,vat=160)=>({registration_no:'same-registration',invoice_no:'INV-1',invoice_date:'2026-08-01',
  status:'ISSUED',seller_iin:'999999999999',seller_name:'Supplier',buyer_iin:buyer,
  amount_net:1000,amount_vat:vat,amount_total:1160,raw_row:{}});
 await t.test('session retries reuse id and cannot change its organisation',async()=>{
  const body={id:'33333333-3333-4333-8333-333333333333',accounting_client_id:'a',period_from:'2026-07-01',period_to:'2026-09-30'};
  assert.equal((await request('/esf/sessions','POST',body)).status,201);
  assert.equal((await request('/esf/sessions','POST',body)).status,201);
  assert.equal((await request('/esf/sessions','POST',{...body,accounting_client_id:'b'})).status,400);
  assert.equal((await pg.query('SELECT count(*) FROM esf_recon_session WHERE id=$1',[body.id])).rows[0].count,1);
 });
 await t.test('same filename/registration/period does not mix companies or sessions',async()=>{
  registry=[row('123456789012')];assert.equal((await upload(a,'registry')).status,200);
  registry=[row('234567890123',320)];assert.equal((await upload(b,'registry')).status,200);
  registry=[row('123456789012',480)];assert.equal((await upload(a2,'registry')).status,200);
  const rows=(await pg.query('SELECT session_id,amount_vat FROM esf_recon_registry_row ORDER BY amount_vat')).rows;
  assert.deepEqual(rows.map(r=>Number(r.amount_vat)),[160,320,480]);
  notice=[row('123456789012')];assert.equal((await upload(a,'notice')).status,200);
  const matched=await request(`/esf/sessions/${a}/match`,'POST',{});
  assert.equal(matched.status,200);assert.equal(matched.body.stats.matched,1);assert.equal(matched.body.stats.total,1);
  const filtered=await request('/esf/sessions?accounting_client_id=b');assert.equal(filtered.body.length,1);
 });
 await t.test('wrong/missing buyer and empty period rejected without destroying previous results',async()=>{
  registry=[row('234567890123')];assert.equal((await upload(a,'registry')).status,400);
  registry=[row('')];assert.equal((await upload(a,'registry')).status,400);
  registry=[{...row('123456789012'),invoice_date:'2025-01-01'}];assert.equal((await upload(a,'registry')).status,400);
  assert.equal((await request(`/esf/sessions/${a}/results`)).body.length,1);
 });
 await t.test('database itself rejects foreign company and cross-session result links',async()=>{
  await assert.rejects(pg.query(`INSERT INTO esf_recon_session(user_id,accounting_client_id,title,period_from,period_to)
   VALUES ($1,'foreign','Wrong','2026-01-01','2026-03-31')`,[user]),/foreign key/i);
  const alien=(await pg.query('SELECT id FROM esf_recon_registry_row WHERE session_id=$1',[b])).rows[0].id;
  await assert.rejects(pg.query(`INSERT INTO esf_recon_result(session_id,esf_id,match_type,confidence,diff)
   VALUES ($1,$2,'only_esf',1,'{}')`,[a,alien]),/foreign key/i);
 });
 await t.test('SQL error halfway through replacement rolls back all changes',async()=>{
  registry=[row('123456789012'),row('123456789012')]; // duplicate unique registration
  assert.equal((await upload(a,'registry')).status,500);
  const rows=(await pg.query('SELECT * FROM esf_recon_registry_row WHERE session_id=$1',[a])).rows;
  assert.equal(rows.length,1);assert.equal(Number(rows[0].amount_vat),160);
  assert.equal((await request(`/esf/sessions/${a}/results`)).body.length,1);
 });
 await t.test('successful reimport invalidates results, keeps other company intact',async()=>{
  registry=[row('123456789012',200)];assert.equal((await upload(a,'registry')).status,200);
  assert.equal((await request(`/esf/sessions/${a}`)).body.status,'draft');
  assert.deepEqual((await request(`/esf/sessions/${a}/results`)).body,[]);
  assert.equal((await pg.query('SELECT * FROM esf_recon_registry_row WHERE session_id=$1',[b])).rows.length,1);
 });
 await t.test('legacy records preserved and quarantined',async()=>{
  const {rows}=await pg.query(`INSERT INTO esf_recon_session(user_id,title,period_from,period_to)
   VALUES ($1,'Legacy','2026-01-01','2026-03-31') RETURNING id`,[user]);
  assert.equal((await request(`/esf/sessions/${rows[0].id}/match`,'POST',{})).status,409);
  assert.equal((await request('/esf/sessions')).body.find(r=>r.id===rows[0].id).requires_reimport,true);
 });
 await t.test('monthly fees: auth, idempotency, retained historical amount, undo and month boundary',async()=>{
  assert.equal((await request('/fees/foreign/fees/2026-08','PUT',{received:true})).status,404);
  assert.equal((await request('/fees/a/fees/2026-13','PUT',{received:true})).status,400);
  assert.equal((await request('/fees/a/fees/2026-08','PUT',{received:'false'})).status,400);
  assert.equal((await request('/fees/a/fees/2026-08','PUT',{received:true},null)).status,401);
  assert.equal((await request('/broken-fees/a/fees/2026-08','PUT',{received:true})).status,500);
  assert.equal((await request('/fees/a/fees/2026-08','PUT',{received:true})).status,200);
  await pg.query('UPDATE accounting_clients SET monthly_fee=20000 WHERE id=$1',['a']);
  await request('/fees/a/fees/2026-08','PUT',{received:true});
  const history=await request('/fees/a/fees/2026-09','PUT',{received:true});
  assert.equal(history.body.payments.length,2);
  assert.deepEqual(history.body.payments.map(p=>Number(p.amount)),[20000,10000]);
  const cancelled=await request('/fees/a/fees/2026-08','PUT',{received:false});
  assert.equal(cancelled.body.payments[0].received,true);assert.equal(cancelled.body.payments[1].received,false);
 });
 await t.test('real XLSX parsers retain company identifier and matching fields',async()=>{
  const wb=new ExcelJS.Workbook(),sheet=wb.addWorksheet('300.07');
  sheet.addRow(['БИН поставщика','Номер счета','Дата выписки','БИН получателя','Сумма НДС','Итого','Регистрационный номер']);
  sheet.addRow(['999999999999','INV-1','01.08.2026','123456789012',160,1160,'REG-1']);
  const bytes=await wb.xlsx.writeBuffer();
  const parsed=await parseEsfRegistry(bytes);assert.equal(parsed.length,1);assert.equal(parsed[0].buyer_iin,'123456789012');
  assert.equal((await parseForm300Notice(bytes))[0].invoice_no,'INV-1');
 });
});
