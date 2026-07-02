const router = require('express').Router();
const crypto = require('crypto');
const db     = require('../db');
const { limitsFor } = require('../tiers');
const requireSubscription = require('../middleware/requireSubscription');

// GET /api/invoices
// Формат ответа — snake_case, 1-в-1 с Invoice.fromJson модели Flutter
// (lib/core/models/invoice.dart). ЭСФ-реквизиты лежат в колонке esf (JSONB)
// и разворачиваются в корень объекта.
router.get('/', async (req, res) => {
  try {
    // due_date форматируем в SQL: node-pg парсит DATE как локальную полночь,
    // и toISOString() на не-UTC серверах сдвигает дату на день назад.
    const { rows: invoices } = await db.query(
      `SELECT id, number, client_name, client_id, buyer_iin, payment_link, esf,
              status, notes, to_char(due_date, 'YYYY-MM-DD') AS due_date, created_at
       FROM invoices
       WHERE user_id = $1
       ORDER BY created_at DESC`,
      [req.userId],
    );

    if (!invoices.length) return res.json([]);

    const ids = invoices.map((i) => i.id);
    const { rows: items } = await db.query(
      `SELECT id, invoice_id, description, quantity, unit_price,
              unit_code, unit_name, esf_unit_code, catalog_tru_id, tru_origin_code
       FROM invoice_items WHERE invoice_id = ANY($1)`,
      [ids],
    );

    const itemsById = {};
    for (const item of items) {
      (itemsById[item.invoice_id] ??= []).push({
        id:          item.id,
        description: item.description,
        quantity:    parseFloat(item.quantity),
        unit_price:  parseFloat(item.unit_price),
        ...(item.unit_code       ? { unit_code: item.unit_code }             : {}),
        ...(item.unit_name       ? { unit_name: item.unit_name }             : {}),
        ...(item.esf_unit_code   ? { esf_unit_code: item.esf_unit_code }     : {}),
        ...(item.catalog_tru_id  ? { catalog_tru_id: item.catalog_tru_id }   : {}),
        ...(item.tru_origin_code ? { tru_origin_code: item.tru_origin_code } : {}),
      });
    }

    res.json(invoices.map((inv) => ({
      id:          inv.id,
      number:      inv.number,
      client_name: inv.client_name,
      ...(inv.client_id    ? { client_id: inv.client_id }       : {}),
      ...(inv.buyer_iin    ? { buyer_iin: inv.buyer_iin }       : {}),
      ...(inv.payment_link ? { payment_link: inv.payment_link } : {}),
      status:      inv.status,
      ...(inv.notes ? { notes: inv.notes } : {}),
      ...(inv.due_date ? { due_date: inv.due_date } : {}),
      created_at:  inv.created_at.toISOString(),
      ...(inv.esf && typeof inv.esf === 'object' ? inv.esf : {}),
      items:       itemsById[inv.id] ?? [],
    })));
  } catch (err) {
    console.error('GET /invoices error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// Ключи ЭСФ-реквизитов, складываемые в колонку esf (JSONB) как есть.
const ESF_KEYS = [
  'turnover_date', 'contract_num', 'contract_date',
  'delivery_doc_num', 'delivery_doc_date',
  'consignor_same_as_seller', 'consignor_name', 'consignor_address', 'consignor_tin',
  'consignee_same_as_customer', 'consignee_name', 'consignee_address', 'consignee_tin',
];

// POST /api/invoices — gated by active subscription / trial
// Принимаем и snake_case (актуальная модель Flutter), и camelCase (старые клиенты).
router.post('/', requireSubscription, async (req, res) => {
  try {
    const b = req.body ?? {};
    const id          = b.id;
    const number      = b.number;
    const clientName  = b.client_name  ?? b.clientName;
    const clientId    = b.client_id    ?? b.clientId;
    const buyerIin    = b.buyer_iin    ?? b.buyerIin;
    const paymentLink = b.payment_link ?? b.paymentLink;
    const status      = b.status ?? 'draft';
    const notes       = b.notes;
    const dueDate     = b.due_date ?? b.dueDate;
    const items       = b.items ?? [];

    const esf = {};
    for (const key of ESF_KEYS) {
      if (b[key] !== undefined && b[key] !== null) esf[key] = b[key];
    }

    // BUG 1: input validation
    if (!id || !number || !clientName) {
      return res.status(400).json({
        error: 'Обязательные поля: id, number, client_name',
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
        `INSERT INTO invoices (id, user_id, number, client_name, client_id,
                               buyer_iin, payment_link, esf, status, notes, due_date)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
         ON CONFLICT (id) DO NOTHING`,
        [id, req.userId, number, clientName, clientId,
         buyerIin, paymentLink, Object.keys(esf).length ? esf : null,
         status, notes, dueDate],
      );

      for (const item of items) {
        // invoice_items.id is a NOT NULL PRIMARY KEY; clients should send an id,
        // but generate one when missing so a malformed item can't 500 the request.
        const itemId = item.id || crypto.randomUUID();
        await client.query(
          `INSERT INTO invoice_items (id, invoice_id, description, quantity, unit_price,
                                      unit_code, unit_name, esf_unit_code, catalog_tru_id, tru_origin_code)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
           ON CONFLICT (id) DO NOTHING`,
          [itemId, id, item.description, item.quantity,
           item.unit_price ?? item.unitPrice,
           item.unit_code ?? item.unitCode ?? null,
           item.unit_name ?? item.unitName ?? null,
           item.esf_unit_code ?? item.esfUnitCode ?? null,
           item.catalog_tru_id ?? item.catalogTruId ?? null,
           item.tru_origin_code ?? item.truOriginCode ?? null],
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
    const b = req.body ?? {};
    const status      = b.status;
    const notes       = b.notes;
    const dueDate     = b.due_date ?? b.dueDate;
    const paymentLink = b.payment_link ?? b.paymentLink;
    const result = await db.query(
      `UPDATE invoices
       SET status = COALESCE($1, status),
           notes  = COALESCE($2, notes),
           due_date = COALESCE($3, due_date),
           payment_link = COALESCE($4, payment_link)
       WHERE id = $5 AND user_id = $6`,
      [status, notes, dueDate, paymentLink, req.params.id, req.userId],
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
