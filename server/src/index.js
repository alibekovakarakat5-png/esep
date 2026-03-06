const express = require('express');
const cors    = require('cors');
const db      = require('./db');

const authMiddleware   = require('./middleware/auth');
const authRoutes       = require('./routes/auth');
const txRoutes         = require('./routes/transactions');
const invoiceRoutes    = require('./routes/invoices');

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
      created_at    TIMESTAMPTZ DEFAULT NOW()
    );

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
  `);
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
});
