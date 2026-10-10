'use strict';
// Explicit, scoped queue migration and optional correction of the verified public post.
if(require.main===module){
  if(!process.argv.includes('--apply')){console.error('Explicit --apply is required');process.exitCode=1;}
  else {
    try{require('dotenv').config();}catch{}
    const {Client}=require('pg');
    const {applyReviewMigration}=require('../src/services/marketing_review');
    const {correctVatPost}=require('../src/services/marketing_correction');
    const {createBotRequest}=require('../src/bot/transport');
    if(!process.env.DATABASE_URL)throw Error('DATABASE_URL is required');
    const c=new Client({connectionString:process.env.DATABASE_URL,ssl:process.env.DATABASE_URL.includes('railway')?{rejectUnauthorized:false}:false});
    (async()=>{try{
      await c.connect();await c.query('BEGIN');
      const result=await applyReviewMigration(c);await c.query('COMMIT');
      console.log('[marketing-review] Migration complete',JSON.stringify(result));
      if(process.argv.includes('--correct-vat-post-169')){
        try {
          const corrected=await correctVatPost(c,createBotRequest({token:process.env.TELEGRAM_BOT_TOKEN}));
          console.log('[marketing-review] Channel correction',JSON.stringify(corrected));
        } catch(e) {
          // The publication guard must still deploy even if Telegram editing needs attention.
          console.error('[marketing-review] Channel correction needs attention:',e.code||e.message);
        }
      }
    }catch(e){await c.query('ROLLBACK').catch(()=>{});console.error('[marketing-review] Migration failed:',e.code||'DATABASE_ERROR');process.exitCode=1;}
    finally{await c.end();}})();
  }
}
