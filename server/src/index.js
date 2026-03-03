const express = require('express');
const cors    = require('cors');

const authMiddleware   = require('./middleware/auth');
const authRoutes       = require('./routes/auth');
const txRoutes         = require('./routes/transactions');
const invoiceRoutes    = require('./routes/invoices');

const app  = express();
const PORT = process.env.PORT ?? 3001;

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
app.listen(PORT, () => console.log(`✅  Есеп API → http://localhost:${PORT}`));
