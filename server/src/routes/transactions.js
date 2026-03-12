const router = require('express').Router();
const db     = require('../db');
const { limitsFor } = require('../tiers');

// GET /api/transactions
router.get('/', async (req, res) => {
  const { rows } = await db.query(
    `SELECT id, title, amount, is_income, date,
            client_name, source, note, category
     FROM transactions
     WHERE user_id = $1
     ORDER BY date DESC, created_at DESC`,
    [req.userId],
  );

  res.json(rows.map((r) => ({
    id:         r.id,
    title:      r.title,
    amount:     parseFloat(r.amount),
    isIncome:   r.is_income,
    date:       r.date.toISOString().slice(0, 10),
    clientName: r.client_name,
    source:     r.source,
    note:       r.note,
    category:   r.category,
  })));
});

// POST /api/transactions  (bulk sync: array or single object)
router.post('/', async (req, res) => {
  const items = Array.isArray(req.body) ? req.body : [req.body];

  // Check tier limit for free users
  const { rows: [user] } = await db.query('SELECT tier FROM users WHERE id = $1', [req.userId]);
  const limits = limitsFor(user?.tier);

  if (isFinite(limits.txPerMonth)) {
    const now = new Date();
    const { rows: [{ count }] } = await db.query(
      `SELECT COUNT(*) FROM transactions
       WHERE user_id = $1
         AND date_trunc('month', created_at) = date_trunc('month', NOW())`,
      [req.userId],
    );
    if (parseInt(count) + items.length > limits.txPerMonth) {
      return res.status(403).json({
        error: `Лимит тарифа: не более ${limits.txPerMonth} операций в месяц. Перейдите на платный тариф.`,
        code: 'TIER_LIMIT',
        limit: limits.txPerMonth,
      });
    }
  }

  for (const t of items) {
    await db.query(
      `INSERT INTO transactions
         (id, user_id, title, amount, is_income, date, client_name, source, note, category)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
       ON CONFLICT (id) DO NOTHING`,
      [t.id, req.userId, t.title, t.amount, t.isIncome,
       t.date, t.clientName, t.source, t.note, t.category],
    );
  }

  res.status(201).json({ ok: true });
});

// PUT /api/transactions/:id
router.put('/:id', async (req, res) => {
  const { title, amount, isIncome, date, clientName, source, note, category } = req.body;
  await db.query(
    `UPDATE transactions
     SET title=$1, amount=$2, is_income=$3, date=$4,
         client_name=$5, source=$6, note=$7, category=$8
     WHERE id=$9 AND user_id=$10`,
    [title, amount, isIncome, date, clientName, source, note, category,
     req.params.id, req.userId],
  );
  res.json({ ok: true });
});

// DELETE /api/transactions/:id
router.delete('/:id', async (req, res) => {
  await db.query(
    'DELETE FROM transactions WHERE id=$1 AND user_id=$2',
    [req.params.id, req.userId],
  );
  res.json({ ok: true });
});

module.exports = router;
