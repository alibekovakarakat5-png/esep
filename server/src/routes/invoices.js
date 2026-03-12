const router = require('express').Router();
const db     = require('../db');
const { limitsFor } = require('../tiers');

// GET /api/invoices
router.get('/', async (req, res) => {
  const { rows: invoices } = await db.query(
    `SELECT id, number, client_name, client_id, status, notes, due_date, created_at
     FROM invoices
     WHERE user_id = $1
     ORDER BY created_at DESC`,
    [req.userId],
  );

  if (!invoices.length) return res.json([]);

  const ids = invoices.map((i) => i.id);
  const { rows: items } = await db.query(
    'SELECT id, invoice_id, description, quantity, unit_price FROM invoice_items WHERE invoice_id = ANY($1)',
    [ids],
  );

  const itemsById = {};
  for (const item of items) {
    (itemsById[item.invoice_id] ??= []).push({
      id:          item.id,
      description: item.description,
      quantity:    parseFloat(item.quantity),
      unitPrice:   parseFloat(item.unit_price),
    });
  }

  res.json(invoices.map((inv) => ({
    id:         inv.id,
    number:     inv.number,
    clientName: inv.client_name,
    clientId:   inv.client_id,
    status:     inv.status,
    notes:      inv.notes,
    dueDate:    inv.due_date?.toISOString().slice(0, 10) ?? null,
    createdAt:  inv.created_at.toISOString(),
    items:      itemsById[inv.id] ?? [],
  })));
});

// POST /api/invoices
router.post('/', async (req, res) => {
  const { id, number, clientName, clientId, status = 'draft', notes, dueDate, items = [] } = req.body;

  // Check tier limit for free users
  const { rows: [user] } = await db.query('SELECT tier FROM users WHERE id = $1', [req.userId]);
  const limits = limitsFor(user?.tier);

  if (isFinite(limits.invoicesPerMonth)) {
    const { rows: [{ count }] } = await db.query(
      `SELECT COUNT(*) FROM invoices
       WHERE user_id = $1
         AND date_trunc('month', created_at) = date_trunc('month', NOW())`,
      [req.userId],
    );
    if (parseInt(count) >= limits.invoicesPerMonth) {
      return res.status(403).json({
        error: `Лимит тарифа: не более ${limits.invoicesPerMonth} счетов в месяц. Перейдите на платный тариф.`,
        code: 'TIER_LIMIT',
        limit: limits.invoicesPerMonth,
      });
    }
  }

  await db.query(
    `INSERT INTO invoices (id, user_id, number, client_name, client_id, status, notes, due_date)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
     ON CONFLICT (id) DO NOTHING`,
    [id, req.userId, number, clientName, clientId, status, notes, dueDate],
  );

  for (const item of items) {
    await db.query(
      `INSERT INTO invoice_items (id, invoice_id, description, quantity, unit_price)
       VALUES ($1,$2,$3,$4,$5)
       ON CONFLICT (id) DO NOTHING`,
      [item.id, id, item.description, item.quantity, item.unitPrice],
    );
  }

  res.status(201).json({ ok: true });
});

// PUT /api/invoices/:id  (update status / fields)
router.put('/:id', async (req, res) => {
  const { status, notes, dueDate } = req.body;
  await db.query(
    `UPDATE invoices
     SET status = COALESCE($1, status),
         notes  = COALESCE($2, notes),
         due_date = COALESCE($3, due_date)
     WHERE id = $4 AND user_id = $5`,
    [status, notes, dueDate, req.params.id, req.userId],
  );
  res.json({ ok: true });
});

// DELETE /api/invoices/:id
router.delete('/:id', async (req, res) => {
  await db.query(
    'DELETE FROM invoices WHERE id=$1 AND user_id=$2',
    [req.params.id, req.userId],
  );
  res.json({ ok: true });
});

module.exports = router;
