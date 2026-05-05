const router = require('express').Router();
const db     = require('../db');
const { limitsFor } = require('../tiers');
const requireSubscription = require('../middleware/requireSubscription');

// GET /api/invoices
router.get('/', async (req, res) => {
  try {
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
  } catch (err) {
    console.error('GET /invoices error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// POST /api/invoices — gated by active subscription / trial
router.post('/', requireSubscription, async (req, res) => {
  try {
    const { id, number, clientName, clientId, status = 'draft', notes, dueDate, items = [] } = req.body;

    // BUG 1: input validation
    if (!id || !number || !clientName) {
      return res.status(400).json({
        error: 'Обязательные поля: id, number, clientName',
      });
    }

    // BUG 9: wrap tier limit check + inserts in a database transaction
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      // Check tier limit for free users
      const { rows: [user] } = await client.query('SELECT tier FROM users WHERE id = $1', [req.userId]);
      const limits = limitsFor(user?.tier);

      if (isFinite(limits.invoicesPerMonth)) {
        const { rows: [{ count }] } = await client.query(
          `SELECT COUNT(*) FROM invoices
           WHERE user_id = $1
             AND date_trunc('month', created_at) = date_trunc('month', NOW())`,
          [req.userId],
        );
        if (parseInt(count) >= limits.invoicesPerMonth) {
          await client.query('ROLLBACK');
          return res.status(403).json({
            error: `Лимит тарифа: не более ${limits.invoicesPerMonth} счетов в месяц. Перейдите на платный тариф.`,
            code: 'TIER_LIMIT',
            limit: limits.invoicesPerMonth,
          });
        }
      }

      await client.query(
        `INSERT INTO invoices (id, user_id, number, client_name, client_id, status, notes, due_date)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
         ON CONFLICT (id) DO NOTHING`,
        [id, req.userId, number, clientName, clientId, status, notes, dueDate],
      );

      for (const item of items) {
        await client.query(
          `INSERT INTO invoice_items (id, invoice_id, description, quantity, unit_price)
           VALUES ($1,$2,$3,$4,$5)
           ON CONFLICT (id) DO NOTHING`,
          [item.id, id, item.description, item.quantity, item.unitPrice],
        );
      }

      await client.query('COMMIT');
    } catch (txErr) {
      await client.query('ROLLBACK');
      throw txErr;
    } finally {
      client.release();
    }

    res.status(201).json({ ok: true });
  } catch (err) {
    console.error('POST /invoices error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// PUT /api/invoices/:id  (update status / fields)
router.put('/:id', async (req, res) => {
  try {
    const { status, notes, dueDate } = req.body;
    const result = await db.query(
      `UPDATE invoices
       SET status = COALESCE($1, status),
           notes  = COALESCE($2, notes),
           due_date = COALESCE($3, due_date)
       WHERE id = $4 AND user_id = $5`,
      [status, notes, dueDate, req.params.id, req.userId],
    );

    // BUG 8: return 404 for nonexistent resources
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Счёт не найден' });
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('PUT /invoices/:id error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// DELETE /api/invoices/:id
router.delete('/:id', async (req, res) => {
  try {
    const result = await db.query(
      'DELETE FROM invoices WHERE id=$1 AND user_id=$2',
      [req.params.id, req.userId],
    );

    // BUG 8: return 404 for nonexistent resources
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Счёт не найден' });
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('DELETE /invoices/:id error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

module.exports = router;
