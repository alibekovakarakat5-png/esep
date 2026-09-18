// Reconciliations have immutable company ownership and session-local inputs.
const express = require('express');
const multer = require('multer');
const defaultDb = require('../db');
const defaultParsers = require('../services/esf_xlsx_parser');
const { match, buildStats } = require('../services/esf_matcher');
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 30 * 1024 * 1024 } });
const fail = (status, message) => Object.assign(new Error(message), { status });
const day = v => v instanceof Date ? v.toISOString().slice(0,10) : String(v).slice(0,10);
const validDate = v => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v)
  && Number.isFinite(Date.parse(v)) && new Date(v).toISOString().slice(0,10) === v;

function createRouter(db = defaultDb, parsers = defaultParsers) {
 const router = express.Router();
 router.use((req,res,next) => {
  req.ownerId = req.userId || req.user?.id;
  if (!req.ownerId) return res.status(401).json({error:'Требуется авторизация'});
  next();
 });
 const wrap = fn => async (req,res) => {
  try { await fn(req,res); } catch(e) {
   res.status(e.status || 500).json({error:e.status ? e.message : 'Не удалось выполнить сверку. Изменения не сохранены.'});
  }
 };
 const sessionTask = fn => wrap(async (req,res) => {
  if (!/^[0-9a-f-]{36}$/i.test(req.params.id)) throw fail(404,'Сессия не найдена');
  const tx = await db.connect();
  try {
   await tx.query('BEGIN');
   const {rows} = await tx.query('SELECT * FROM esf_recon_session WHERE id=$1 AND user_id=$2 FOR UPDATE',[req.params.id,req.ownerId]);
   const s = rows[0];
   if (!s) throw fail(404,'Сессия не найдена');
   if (!s.accounting_client_id) throw fail(409,'Старая сверка без компании. Создайте новую и загрузите исходные файлы. Старые данные сохранены.');
   const owner = await tx.query('SELECT id FROM accounting_clients WHERE id=$1 AND user_id=$2',[s.accounting_client_id,req.ownerId]);
   if (!owner.rows.length) throw fail(404,'Компания не найдена');
   const result = await fn(req,tx,s);
   await tx.query('COMMIT'); res.json(result);
  } catch(e) { await tx.query('ROLLBACK'); throw e; } finally { tx.release(); }
 });
 const invalidate = async (tx,id) => {
  await tx.query('DELETE FROM esf_recon_result WHERE session_id=$1',[id]);
  await tx.query("UPDATE esf_recon_session SET status='draft',stats='{}'::jsonb,updated_at=NOW() WHERE id=$1",[id]);
 };
 router.post('/sessions',wrap(async (req,res) => {
  const {id,title,period_from,period_to,accounting_client_id} = req.body || {};
  if (id != null && (typeof id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))) throw fail(400,'Некорректный ID сверки');
  if (!validDate(period_from) || !validDate(period_to) || period_from > period_to) throw fail(400,'Укажите корректный период YYYY-MM-DD');
  if (typeof accounting_client_id !== 'string' || !accounting_client_id) throw fail(400,'Выберите обслуживаемую компанию');
  const {rows} = await db.query(`INSERT INTO esf_recon_session
   (user_id,title,period_from,period_to,accounting_client_id,client_bin,id)
   SELECT $1,$2,$3,$4,id,bin_or_iin,COALESCE($6::uuid,gen_random_uuid()) FROM accounting_clients
   WHERE id=$5 AND user_id=$1 AND bin_or_iin ~ '^[0-9]{12}$' AND is_active=true
   ON CONFLICT(id) DO UPDATE SET title=esf_recon_session.title
   WHERE esf_recon_session.user_id=EXCLUDED.user_id
     AND esf_recon_session.accounting_client_id=EXCLUDED.accounting_client_id
     AND esf_recon_session.period_from=EXCLUDED.period_from AND esf_recon_session.period_to=EXCLUDED.period_to RETURNING *`,
   [req.ownerId,typeof title==='string'?title.slice(0,250):'',period_from,period_to,accounting_client_id,id||null]);
  if (!rows.length) throw fail(400,'Компания недоступна или не заполнен ИИН/БИН из 12 цифр');
  res.status(201).json(rows[0]);
 }));
 router.get('/sessions',wrap(async (req,res) => {
  const {rows} = await db.query(`SELECT s.*,c.name AS client_name,(s.accounting_client_id IS NULL) AS requires_reimport
   FROM esf_recon_session s LEFT JOIN accounting_clients c ON c.id=s.accounting_client_id AND c.user_id=s.user_id
   WHERE s.user_id=$1 AND ($2::text IS NULL OR s.accounting_client_id=$2)
   ORDER BY s.created_at DESC LIMIT 100`,[req.ownerId,req.query.accounting_client_id || null]);
  res.json(rows);
 }));
 router.get('/sessions/:id',sessionTask(async (_,tx,s) => {
  const {rows} = await tx.query('SELECT name FROM accounting_clients WHERE id=$1',[s.accounting_client_id]);
  return {...s,client_name:rows[0].name};
 }));
 router.delete('/sessions/:id',sessionTask(async (_,tx,s) => {
  await tx.query('DELETE FROM esf_recon_session WHERE id=$1',[s.id]);return {ok:true};
 }));
 router.post('/sessions/:id/registry',upload.single('file'),sessionTask(async (req,tx,s) => {
  if (!req.file) throw fail(400,'Файл не передан');
  const rows = await parsers.parseEsfRegistry(req.file.buffer);
  if (!rows.length) throw fail(400,'В реестре не найдены строки ЭСФ');
  if (rows.some(r=>r.buyer_iin!==s.client_bin)) throw fail(400,'ИИН/БИН получателя в реестре отсутствует или не совпадает с выбранной компанией');
  const selected=rows.filter(r=>day(r.invoice_date)>=day(s.period_from)&&day(r.invoice_date)<=day(s.period_to));
  if (!selected.length) throw fail(400,'В файле нет ЭСФ за выбранный период');
  await invalidate(tx,s.id);
  await tx.query('DELETE FROM esf_recon_registry_row WHERE session_id=$1',[s.id]);
  for(const r of selected) await tx.query(`INSERT INTO esf_recon_registry_row
   (session_id,registration_no,invoice_no,invoice_date,status,seller_iin,seller_name,buyer_iin,amount_net,amount_vat,amount_total,raw_row)
   VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb)`,
   [s.id,r.registration_no,r.invoice_no,r.invoice_date,r.status,r.seller_iin,r.seller_name,r.buyer_iin,r.amount_net,r.amount_vat,r.amount_total,JSON.stringify(r.raw_row)]);
  await tx.query('UPDATE esf_recon_session SET registry_filename=$1 WHERE id=$2',[req.file.originalname,s.id]);
  return {inserted:selected.length,skipped:rows.length-selected.length,total_rows:rows.length};
 }));
 router.post('/sessions/:id/notice',upload.single('file'),sessionTask(async (req,tx,s) => {
  if (!req.file) throw fail(400,'Файл не передан');
  const rows=await parsers.parseForm300Notice(req.file.buffer);
  if(!rows.length) throw fail(400,'В извещении не найдены строки');
  await invalidate(tx,s.id);
  await tx.query('DELETE FROM esf_notice_row WHERE session_id=$1',[s.id]);
  for(const [i,r] of rows.entries()) await tx.query(`INSERT INTO esf_notice_row
   (session_id,row_index,seller_iin,seller_name,invoice_no,invoice_date,amount_net,amount_vat,amount_total,vat_rate,raw_row)
   VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb)`,
   [s.id,i+1,r.seller_iin,r.seller_name,r.invoice_no,r.invoice_date,r.amount_net,r.amount_vat,r.amount_total,r.vat_rate,JSON.stringify(r.raw_row)]);
  await tx.query('UPDATE esf_recon_session SET notice_filename=$1 WHERE id=$2',[req.file.originalname,s.id]);
  return {inserted:rows.length};
 }));
 router.post('/sessions/:id/match',sessionTask(async (_,tx,s) => {
  const esf=await tx.query('SELECT * FROM esf_recon_registry_row WHERE session_id=$1',[s.id]);
  const notice=await tx.query('SELECT * FROM esf_notice_row WHERE session_id=$1',[s.id]);
  if(!esf.rows.length||!notice.rows.length) throw fail(400,'Загрузите оба файла для полной сверки');
  const results=match(esf.rows,notice.rows),stats=buildStats(results);
  await invalidate(tx,s.id);
  for(const r of results) await tx.query(`INSERT INTO esf_recon_result
   (session_id,esf_id,notice_row_id,match_type,confidence,diff) VALUES ($1,$2,$3,$4,$5,$6::jsonb)`,
   [s.id,r.esf_id||null,r.notice_row_id||null,r.match_type,r.confidence,JSON.stringify(r.diff)]);
  await tx.query("UPDATE esf_recon_session SET status='matched',stats=$1::jsonb WHERE id=$2",[JSON.stringify(stats),s.id]);
  return {ok:true,stats};
 }));
 router.get('/sessions/:id/results',sessionTask(async (req,tx,s) => {
  const {rows}=await tx.query(`SELECT m.id,m.match_type,m.confidence,m.diff,
   e.registration_no,e.invoice_no AS esf_invoice_no,e.invoice_date AS esf_date,e.status AS esf_status,
   e.seller_iin AS esf_seller_iin,e.seller_name AS esf_seller_name,e.amount_total AS esf_total,e.amount_vat AS esf_vat,
   n.invoice_no AS notice_invoice_no,n.invoice_date AS notice_date,n.seller_iin AS notice_seller_iin,
   n.seller_name AS notice_seller_name,n.amount_total AS notice_total,n.amount_vat AS notice_vat
   FROM esf_recon_result m LEFT JOIN esf_recon_registry_row e ON e.id=m.esf_id AND e.session_id=m.session_id
   LEFT JOIN esf_notice_row n ON n.id=m.notice_row_id AND n.session_id=m.session_id
   WHERE m.session_id=$1 AND ($2::text IS NULL OR m.match_type=$2) ORDER BY m.match_type,m.id`,[s.id,req.query.type||null]);
  return rows;
 }));
 return router;
}
module.exports=createRouter();
module.exports.createRouter=createRouter;
