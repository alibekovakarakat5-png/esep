-- Есеп DB schema
-- Run automatically by PostgreSQL on first container start

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Users ──────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email         TEXT        UNIQUE NOT NULL,
    name          TEXT        NOT NULL DEFAULT '',
    password_hash TEXT        NOT NULL,
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ── Transactions ───────────────────────────────────────────────────────────────
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

-- ── Invoices ───────────────────────────────────────────────────────────────────
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

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_tx_user    ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_inv_user   ON invoices(user_id);
CREATE INDEX IF NOT EXISTS idx_items_inv  ON invoice_items(invoice_id);
