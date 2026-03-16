const router = require('express').Router();
const db     = require('../db');
const { limitsFor } = require('../tiers');

// GET /api/transactions
router.get('/', async (req, res) => {
  try {
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
  } catch (err) {
    console.error('GET /transactions error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// POST /api/transactions  (bulk sync: array or single object)
router.post('/', async (req, res) => {
  try {
    const items = Array.isArray(req.body) ? req.body : [req.body];

    // BUG 1: input validation
    for (const t of items) {
      if (!t.id || !t.title || t.amount === undefined || t.amount === null || t.isIncome === undefined || !t.date) {
        return res.status(400).json({
          error: 'Каждая транзакция должна содержать: id, title, amount, isIncome, date',
        });
      }
    }

    // BUG 9: wrap tier limit check + inserts in a database transaction
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      // Check tier limit for free users
      const { rows: [user] } = await client.query('SELECT tier FROM users WHERE id = $1', [req.userId]);
      const limits = limitsFor(user?.tier);

      if (isFinite(limits.txPerMonth)) {
        const { rows: [{ count }] } = await client.query(
          `SELECT COUNT(*) FROM transactions
           WHERE user_id = $1
             AND date_trunc('month', created_at) = date_trunc('month', NOW())`,
          [req.userId],
        );
        if (parseInt(count) + items.length > limits.txPerMonth) {
          await client.query('ROLLBACK');
          return res.status(403).json({
            error: `Лимит тарифа: не более ${limits.txPerMonth} операций в месяц. Перейдите на платный тариф.`,
            code: 'TIER_LIMIT',
            limit: limits.txPerMonth,
          });
        }
      }

      for (const t of items) {
        await client.query(
          `INSERT INTO transactions
             (id, user_id, title, amount, is_income, date, client_name, source, note, category)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
           ON CONFLICT (id) DO NOTHING`,
          [t.id, req.userId, t.title, t.amount, t.isIncome,
           t.date, t.clientName, t.source, t.note, t.category],
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
    console.error('POST /transactions error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// PUT /api/transactions/:id
router.put('/:id', async (req, res) => {
  try {
    const { title, amount, isIncome, date, clientName, source, note, category } = req.body;
    const result = await db.query(
      `UPDATE transactions
       SET title=$1, amount=$2, is_income=$3, date=$4,
           client_name=$5, source=$6, note=$7, category=$8
       WHERE id=$9 AND user_id=$10`,
      [title, amount, isIncome, date, clientName, source, note, category,
       req.params.id, req.userId],
    );

    // BUG 8: return 404 for nonexistent resources
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Транзакция не найдена' });
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('PUT /transactions/:id error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// DELETE /api/transactions/:id
router.delete('/:id', async (req, res) => {
  try {
    const result = await db.query(
      'DELETE FROM transactions WHERE id=$1 AND user_id=$2',
      [req.params.id, req.userId],
    );

    // BUG 8: return 404 for nonexistent resources
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Транзакция не найдена' });
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('DELETE /transactions/:id error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

module.exports = router;
