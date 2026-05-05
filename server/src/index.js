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
const { router: promoRoutes,
        seedPromos }                      = require('./routes/promos');
const articleRoutes                       = require('./routes/articles');
const binLookupRoutes                    = require('./routes/bin-lookup');
const lprRoutes                          = require('./routes/lpr-search');
const aiChatRoutes                       = require('./routes/ai-chat');
const { startMonitor }                    = require('./jobs/taxMonitor');
const { startLeadMonitor }                = require('./jobs/leadMonitor');
const { startPaymentMonitor }             = require('./jobs/paymentMonitor');
const { startTrialMonitor }               = require('./jobs/trialMonitor');
const { seedMarketingContent }            = require('./bot/marketing');
const { migrateKnowledge }                = require('./services/knowledge_db');
const { seedEsepPlatformKnowledge }       = require('./jobs/seedPlatformKnowledge');
const { migrateEsfAndAccount }            = require('./services/esf_db');
const esfReconRoutes                      = require('./routes/esf-recon');
const accountRoutes                       = require('./routes/account-monitor');
const { migrateTaxProfile }               = require('./services/tax_profile_db');
const taxProfileRoutes                    = require('./routes/tax-profile');
const kbkRoutes                           = require('./routes/kbk');
const { migrateAuthRecovery }             = require('./services/auth_recovery_db');
const authRecoveryRoutes                  = require('./routes/auth-recovery');

// ── Env validation ───────────────────────────────────────────────────────────
const REQUIRED_ENV = ['DATABASE_URL', 'JWT_SECRET'];
for (const key of REQUIRED_ENV) {
  if (!process.env[key]) {
    console.error(`[FATAL] Missing required env var: ${key}`);
    process.exit(1);
  }
}

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
      trial_started_at TIMESTAMPTZ,
      trial_expires_at TIMESTAMPTZ,
      subscription_expires_at TIMESTAMPTZ,
      created_at    TIMESTAMPTZ DEFAULT NOW()
    );

    -- Add tier column if upgrading from existing DB
    ALTER TABLE users ADD COLUMN IF NOT EXISTS tier TEXT NOT NULL DEFAULT 'free';
    ALTER TABLE users ADD COLUMN IF NOT EXISTS trial_started_at TIMESTAMPTZ;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS trial_expires_at TIMESTAMPTZ;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_expires_at TIMESTAMPTZ;
    -- Контакт для саппорта
    ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;
    UPDATE users SET tier = 'solo' WHERE tier = 'ip';
    UPDATE users SET tier = 'accountant_pro' WHERE tier IN ('corporate', 'accountantPro');

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

    CREATE TABLE IF NOT EXISTS payments (
      id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      tier          TEXT        NOT NULL,
      period        TEXT        NOT NULL DEFAULT 'monthly',  -- 'monthly' | 'quarterly' | 'yearly'
      amount        NUMERIC(10,2) NOT NULL,
      status        TEXT        NOT NULL DEFAULT 'pending',  -- pending | paid | expired | refunded
      payment_method TEXT       DEFAULT 'kaspi_pay',
      kaspi_txn_id  TEXT,
      note          TEXT,
      expires_at    TIMESTAMPTZ,
      paid_at       TIMESTAMPTZ,
      created_at    TIMESTAMPTZ DEFAULT NOW()
    );

    ALTER TABLE payments ADD COLUMN IF NOT EXISTS note TEXT;

    CREATE INDEX IF NOT EXISTS idx_payments_user   ON payments(user_id);
    CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);
    CREATE INDEX IF NOT EXISTS idx_payments_expires ON payments(status, expires_at);

    CREATE TABLE IF NOT EXISTS promo_codes (
      id            SERIAL      PRIMARY KEY,
      code          TEXT        UNIQUE NOT NULL,
      grant_tier    TEXT        NOT NULL DEFAULT 'solo',
      duration_days INT         NOT NULL DEFAULT 30,
      max_uses      INT         NOT NULL DEFAULT 0,  -- 0 = unlimited
      used_count    INT         NOT NULL DEFAULT 0,
      description   TEXT        DEFAULT '',
      active        BOOLEAN     DEFAULT TRUE,
      expires_at    TIMESTAMPTZ,
      created_at    TIMESTAMPTZ DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS promo_usages (
      id         SERIAL      PRIMARY KEY,
      promo_id   INT         NOT NULL REFERENCES promo_codes(id) ON DELETE CASCADE,
      user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      expires_at TIMESTAMPTZ NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(promo_id, user_id)
    );

    CREATE INDEX IF NOT EXISTS idx_promo_usages_user ON promo_usages(user_id);
    UPDATE promo_codes SET grant_tier = 'solo' WHERE grant_tier = 'ip';
    UPDATE promo_codes SET grant_tier = 'accountant_pro' WHERE grant_tier IN ('corporate', 'accountantPro');

    CREATE TABLE IF NOT EXISTS bot_users (
      chat_id         TEXT        PRIMARY KEY,
      linked_user_id  UUID        REFERENCES users(id) ON DELETE SET NULL,
      queries_today   INT         NOT NULL DEFAULT 0,
      last_query_date TEXT,
      created_at      TIMESTAMPTZ DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS marketing_posts (
      id          SERIAL      PRIMARY KEY,
      type        TEXT        NOT NULL DEFAULT 'tip',
      title       TEXT        NOT NULL,
      body        TEXT        NOT NULL,
      platform    TEXT        NOT NULL DEFAULT 'telegram',
      scheduled   DATE,
      posted      BOOLEAN     DEFAULT FALSE,
      posted_at   TIMESTAMPTZ,
      created_at  TIMESTAMPTZ DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS lead_keywords (
      id      SERIAL PRIMARY KEY,
      keyword TEXT   NOT NULL UNIQUE
    );

    CREATE TABLE IF NOT EXISTS lpr_contacts (
      id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      bin          TEXT,
      company_name TEXT        NOT NULL,
      director_name TEXT,
      phone        TEXT,
      email        TEXT,
      source       TEXT        DEFAULT 'manual',
      city         TEXT,
      activity     TEXT,
      notes        TEXT,
      created_at   TIMESTAMPTZ DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS idx_lpr_user ON lpr_contacts(user_id);
    CREATE INDEX IF NOT EXISTS idx_lpr_company ON lpr_contacts(company_name);

    INSERT INTO lead_keywords (keyword) VALUES
      ('налог'), ('910 форма'), ('ИП Казахстан'), ('бухгалтер'), ('упрощёнка'),
      ('упрощенка'), ('МРП'), ('соцплатеж'), ('ОПВ'), ('ВОСМС'),
      ('патент'), ('ЕСП'), ('самозанят'), ('декларация'), ('налоговая')
    ON CONFLICT DO NOTHING;
  `);
  await seedTaxConfig();
  await seedPromos();
  await seedMarketingContent();
  console.log('✅  DB migrated');

  // RAG / Knowledge DB
  try {
    await migrateKnowledge();
    await seedEsepPlatformKnowledge();
  } catch (err) {
    console.error('[knowledge] migration failed:', err.message);
    // Не падаем — сервер должен работать даже если RAG ещё не готов
  }

  // ЭСФ-сверщик + монитор лицевого счёта
  try {
    await migrateEsfAndAccount();
  } catch (err) {
    console.error('[esf+account] migration failed:', err.message);
  }

  // Налоговый профиль компании
  try {
    await migrateTaxProfile();
  } catch (err) {
    console.error('[tax-profile] migration failed:', err.message);
  }

  // Auth recovery (Telegram-привязка + сброс пароля)
  try {
    await migrateAuthRecovery();
  } catch (err) {
    console.error('[auth-recovery] migration failed:', err.message);
  }
}

// ── Middleware ────────────────────────────────────────────────────────────────
const ALLOWED_ORIGINS = [
  // Production — основные домены
  'https://esepkz.com',
  'https://www.esepkz.com',
  'https://app.esepkz.com',
  'https://api.esepkz.com',
  // Старые URL (на переходный период — потом удалим)
  'https://esepkz.vercel.app',
  'https://alibekovakarakat5-png.github.io',
  'https://esep-production.up.railway.app',
  // Local dev
  'http://localhost:5500',
  'http://localhost:8080',
  'http://localhost:3000',
  'http://localhost:3334',
  'http://localhost:5173',
];
app.use(cors({
  origin: (origin, cb) => {
    if (!origin || ALLOWED_ORIGINS.some(o => origin.startsWith(o))) return cb(null, true);
    cb(null, false);
  },
  allowedHeaders: ['Authorization', 'Content-Type'],
}));
app.use(express.json({ limit: '1mb' }));

// ── Simple rate limiter for auth routes ─────────────────────────────────────
const authAttempts = new Map();
app.use('/api/auth', (req, _res, next) => {
  if (req.method !== 'POST') return next();
  const ip = req.ip || req.headers['x-forwarded-for'] || 'unknown';
  const now = Date.now();
  const record = authAttempts.get(ip) || { count: 0, resetAt: now + 60_000 };
  if (now > record.resetAt) { record.count = 0; record.resetAt = now + 60_000; }
  record.count++;
  authAttempts.set(ip, record);
  if (record.count > 10) {
    return _res.status(429).json({ error: 'Слишком много попыток. Попробуйте через минуту.' });
  }
  next();
});

// ── Routes ────────────────────────────────────────────────────────────────────
app.get('/api/health', (_req, res) => res.json({ ok: true, ts: new Date() }));

app.use('/api/auth',         authRoutes);
app.use('/api/transactions', authMiddleware, txRoutes);
app.use('/api/invoices',     authMiddleware, invoiceRoutes);
app.use('/api/admin',        adminRoutes);
app.use('/api/config/tax',   taxConfigRoutes);
app.use('/api/promos',       promoRoutes);
app.use('/api/articles',     articleRoutes);
app.use('/api/bin',          binLookupRoutes);
app.use('/api/lpr',          authMiddleware, lprRoutes);
app.use('/api/ai-chat',      authMiddleware, aiChatRoutes);
app.use('/api/esf-recon',    authMiddleware, esfReconRoutes);
app.use('/api/account',      authMiddleware, accountRoutes);
app.use('/api/tax-profile',  authMiddleware, taxProfileRoutes);
app.use('/api/kbk',          authMiddleware, kbkRoutes);

// Auth recovery: только привязка Telegram (всё под авторизацией).
// Восстановление пароля идёт через TG-бота (команда /reset email).
app.use('/api/auth', authMiddleware, authRecoveryRoutes);

// ── Telegram bot webhook ──────────────────────────────────────────────────────
const tg = require('./bot/telegram');
app.post('/api/bot/webhook', (req, res) => {
  tg.handleUpdate(req.body);
  res.json({ ok: true });
});

// Test channel posting (admin only)
const { adminAuth: adminCheck } = require('./routes/admin');
app.get('/api/bot/channel-test', adminCheck, async (req, res) => {
  try {
    const result = await tg.postToChannel(
      '✅ <b>Esep подключен к каналу!</b>\n\n' +
      'Здесь будут налоговые советы, дедлайны и полезные материалы для ИП Казахстана.',
      {
        reply_markup: {
          inline_keyboard: [[
            { text: '🧮 Калькулятор', url: 'https://t.me/EsepKZ_bot' },
          ]],
        },
      },
    );
    res.json({ ok: true, telegram_response: result });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});

// ── Manual lead scan trigger (admin) ──────────────────────────────────────────
const { runLeadScan } = require('./jobs/leadMonitor');
app.get('/api/admin/lead-scan', adminCheck, async (req, res) => {
  try {
    await runLeadScan();
    res.json({ ok: true, message: 'Lead scan complete, digest sent to private channel' });
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
  startLeadMonitor();
  startPaymentMonitor();
  startTrialMonitor().catch(err => console.error('[trialMonitor] failed to start:', err.message));

  // Auto-register Telegram webhook
  const baseUrl = process.env.ADMIN_URL ?? `https://api.esepkz.com`;
  tg.setupWebhook(baseUrl).catch(e => console.error('[bot] webhook setup error:', e.message));
});
