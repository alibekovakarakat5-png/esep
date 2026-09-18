const express = require('express');
function createFeeRouter(db = require('../db')) {
 const router = express.Router();
 router.put('/:id/fees/:month', async (req,res) => {
  if (!req.userId) return res.status(401).json({error:'Требуется авторизация'});
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(req.params.month) || typeof req.body?.received !== 'boolean')
   return res.status(400).json({error:'Укажите месяц YYYY-MM и received: true/false'});
  let tx;
  try {
   tx=await db.connect();
   await tx.query('BEGIN');
   const {rows}=await tx.query('SELECT id,monthly_fee FROM accounting_clients WHERE id=$1 AND user_id=$2 FOR UPDATE',
    [req.params.id,req.userId]);
   if (!rows.length) {await tx.query('ROLLBACK');return res.status(404).json({error:'Клиент не найден'});}
   await tx.query(`INSERT INTO accounting_fee_payments(client_id,month,amount,received)
    VALUES ($1,$2,$3,$4) ON CONFLICT(client_id,month) DO UPDATE SET
    received=EXCLUDED.received,updated_at=NOW()`,
    [req.params.id,req.params.month,rows[0].monthly_fee,req.body.received]);
   const history=await tx.query('SELECT month,amount,received,updated_at FROM accounting_fee_payments WHERE client_id=$1 ORDER BY month DESC',[req.params.id]);
   await tx.query('COMMIT');
   res.json({payments:history.rows});
  } catch(e) {if(tx) await tx.query('ROLLBACK').catch(()=>{});res.status(500).json({error:'Оплата не сохранена'});}
  finally {if(tx) tx.release();}
 });
 return router;
}
module.exports={createFeeRouter};
