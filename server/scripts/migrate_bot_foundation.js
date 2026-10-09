'use strict';
// Explicit schema-only migration. Never run as part of audit/test or ordinary app startup.
if (require.main === module) {
  if (!process.argv.includes('--apply')) {
    console.error('Use --apply only for an explicitly approved database.');
    process.exitCode = 1;
  } else {
    try { require('dotenv').config(); } catch {}
    if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required');
    const { Client } = require('pg');
    const { schema } = require('../src/services/bot_foundation');
    const c = new Client({connectionString:process.env.DATABASE_URL,
      ssl:process.env.DATABASE_URL.includes('railway') ? {rejectUnauthorized:false} : false});
    (async()=>{try {await c.connect();await c.query('BEGIN');await c.query(schema);await c.query('COMMIT');
      console.log('Bot foundation schema applied');
    } catch(e) {await c.query('ROLLBACK').catch(()=>{});console.error('Bot migration failed:',e.code || 'DATABASE_ERROR');process.exitCode=1;}
    finally {await c.end();}})();
  }
}
