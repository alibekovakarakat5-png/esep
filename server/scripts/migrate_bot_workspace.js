'use strict';
// Explicit additive migration; no messages are sent and no historical consent is inferred.
if(require.main===module){
 if(!process.argv.includes('--apply')){console.error('Explicit --apply is required for the agreed database.');process.exitCode=1;}
 else{
  try{require('dotenv').config();}catch{}
  const {Client}=require('pg'),{schema}=require('../src/services/bot_workspace');
  if(!process.env.DATABASE_URL)throw Error('DATABASE_URL is required');
  const c=new Client({connectionString:process.env.DATABASE_URL,ssl:process.env.DATABASE_URL.includes('railway')?{rejectUnauthorized:false}:false});
  (async()=>{try{await c.connect();await c.query('BEGIN');await c.query(schema);await c.query('COMMIT');console.log('Bot workspace schema applied');}
   catch(e){await c.query('ROLLBACK').catch(()=>{});console.error('Bot workspace migration failed:',e.code||'DATABASE_ERROR');process.exitCode=1;}
   finally{await c.end();}})();
 }
}
