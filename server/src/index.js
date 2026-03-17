const express = require('express');
const cors    = require('cors');
const db      = require('./db');

const authMiddleware                      = require('./middleware/auth');
const authRoutes                          = require('./routes/auth');
const txRoutes                            = require('./routes/transactions');
const invoiceRoutes                       = require('./routes/invoices');
const { router: adminRoutes }             = require('./routes/admin');
const { router: taxConfigRoutes,
        seedTaxConfig }                   = require('./routes/tax-config');
const articleRoutes                       = require('./routes/articles');
const { startMonitor }                    = require('./jobs/taxMonitor');

const app  = express();
const PORT = process.env.PORT ?? 3001;

// ── Auto-migrate ──────────────────────────────────────────────────────────────
async function migrate() {
  await db.query(`
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";

    CREATE TABLE IF NOT EXISTS users (
      id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
      email         TEXT        UNIQUE NOT NULL,
      name          TEXT        NOT NULL DEFAULT '',
      password_hash TEXT        NOT NULL,
      tier          TEXT        NOT NULL DEFAULT 'free',
      created_at    TIMESTAMPTZ DEFAULT NOW()
    );

    -- Add tier column if upgrading from existing DB
    ALTER TABLE users ADD COLUMN IF NOT EXISTS tier TEXT NOT NULL DEFAULT 'free';

    CREATE TABLE IF NOT EXISTS transactions (
      id          TEXT          PRIMARY KEY,
      user_id     UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      title       TEXT          NOT NULL,
      amount      NUMERIC(15,2) NOT NULL,
      is_income   BOOLEAN       NOT NULL,
      date        DATE          NOT NULL,
      client_name TEXT,
      source      TEXT,
      note        TEXT,
      category    TEXT,
      created_at  TIMESTAMPTZ   DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS invoices (
      id          TEXT        PRIMARY KEY,
      user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      number      TEXT        NOT NULL,
      client_name TEXT        NOT NULL,
      client_id   TEXT,
      status      TEXT        NOT NULL DEFAULT 'draft',
      notes       TEXT,
      due_date    DATE,
      created_at  TIMESTAMPTZ DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS invoice_items (
      id          TEXT          PRIMARY KEY,
      invoice_id  TEXT          NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
      description TEXT          NOT NULL,
      quantity    NUMERIC(10,3) NOT NULL DEFAULT 1,
      unit_price  NUMERIC(15,2) NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_tx_user   ON transactions(user_id);
    CREATE INDEX IF NOT EXISTS idx_inv_user  ON invoices(user_id);
    CREATE INDEX IF NOT EXISTS idx_items_inv ON invoice_items(invoice_id);

    CREATE TABLE IF NOT EXISTS tax_config (
      id         SERIAL      PRIMARY KEY,
      key        TEXT        UNIQUE NOT NULL,
      value      TEXT        NOT NULL,
      label      TEXT        NOT NULL DEFAULT '',
      updated_at TIMESTAMPTZ DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS articles (
      id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
      slug         TEXT        UNIQUE NOT NULL,
      title        TEXT        NOT NULL,
      summary      TEXT,
      body         TEXT,
      audience     TEXT        NOT NULL DEFAULT 'ip',  -- 'ip' | 'accountant' | 'all'
      tags         JSONB       DEFAULT '[]',
      status       TEXT        NOT NULL DEFAULT 'draft', -- 'draft' | 'published'
      published_at TIMESTAMPTZ,
      created_at   TIMESTAMPTZ DEFAULT NOW(),
      updated_at      TIMESTAMPTZ DEFAULT NOW(),
      channel_posted  BOOLEAN     DEFAULT FALSE
    );

    CREATE INDEX IF NOT EXISTS idx_articles_slug   ON articles(slug);
    CREATE INDEX IF NOT EXISTS idx_articles_status ON articles(status);

    -- Add column if table already exists without it
    ALTER TABLE articles ADD COLUMN IF NOT EXISTS channel_posted BOOLEAN DEFAULT FALSE;

    CREATE TABLE IF NOT EXISTS bot_users (
      chat_id         TEXT        PRIMARY KEY,
      linked_user_id  UUID        REFERENCES users(id) ON DELETE SET NULL,
      queries_today   INT         NOT NULL DEFAULT 0,
      last_query_date TEXT,
      created_at      TIMESTAMPTZ DEFAULT NOW()
    );
  `);
  await seedTaxConfig();
  console.log('✅  DB migrated');
}

// ── Middleware ────────────────────────────────────────────────────────────────
app.use(cors({
  origin: '*',
  allowedHeaders: ['Authorization', 'Content-Type'],
}));
app.use(express.json({ limit: '1mb' }));

// ── Routes ────────────────────────────────────────────────────────────────────
app.get('/api/health', (_req, res) => res.json({ ok: true, ts: new Date() }));

app.use('/api/auth',         authRoutes);
app.use('/api/transactions', authMiddleware, txRoutes);
app.use('/api/invoices',     authMiddleware, invoiceRoutes);
app.use('/api/admin',        adminRoutes);
app.use('/api/config/tax',   taxConfigRoutes);
app.use('/api/articles',     articleRoutes);

// ── Telegram bot webhook ──────────────────────────────────────────────────────
const tg = require('./bot/telegram');
app.post('/api/bot/webhook', (req, res) => {
  tg.handleUpdate(req.body);
  res.json({ ok: true });
});

// Test channel posting (admin only, one-time check)
app.get('/api/bot/channel-test', async (req, res) => {
  try {
    const result = await tg.postToChannel(
      '✅ <b>Esep подключен к каналу!</b>\n\n' +
      'Здесь будут налоговые советы, дедлайны и полезные материалы для ИП Казахстана.',
      {
        reply_markup: {
          inline_keyboard: [[
            { text: '🧮 Калькулятор', url: 'https://t.me/esep_bot' },
          ]],
        },
      },
    );
    res.json({ ok: true, telegram_response: result });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// ── 404 ───────────────────────────────────────────────────────────────────────
app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

// ── Error handler ─────────────────────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'Internal server error' });
});

// ── Start ─────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`✅  Есеп API → http://localhost:${PORT}`);
  console.log(`DATABASE_URL set: ${!!process.env.DATABASE_URL}`);
  migrate().catch(err => console.error('Migration failed (non-fatal):', err.message));
  startMonitor();

  // Auto-register Telegram webhook
  const baseUrl = process.env.ADMIN_URL ?? `https://esep-production.up.railway.app`;
  tg.setupWebhook(baseUrl).catch(e => console.error('[bot] webhook setup error:', e.message));
});
