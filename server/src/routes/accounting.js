const router = require('express').Router();
const db     = require('../db');

// ── Клиенты бухгалтера ───────────────────────────────────────────────────────
// Владелец строки — сам бухгалтер (user_id). Сотрудники и чеклист документов
// живут в JSONB рядом с клиентом: они маленькие, всегда нужны целиком и
// отдельных запросов по ним нет.
//
// Контракт — snake_case, как читает Dart-модель (урок фикса transactions:
// camelCase на выходе ломал парсинг, и данные «пропадали»). На входе
// принимаем оба стиля.

const ENTITY_TYPES = ['ip', 'too'];
const REGIMES      = ['esp', 'patent', 'simplified910', 'our'];

const asArray = (v) => (Array.isArray(v) ? v : []);

function normalizeEmployee(e = {}) {
  return {
    id: String(e.id ?? ''),
    name: String(e.name ?? ''),
    salary: Number(e.salary ?? 0) || 0,
  };
}

function normalizeChecklistItem(d = {}) {
  return {
    id: String(d.id ?? ''),
    label: String(d.label ?? ''),
    received: Boolean(d.received ?? false),
  };
}

function serializeClient(r) {
  return {
    id:                      r.id,
    name:                    r.name,
    bin_or_iin:              r.bin_or_iin,
    entity_type:             r.entity_type,
    regime:                  r.regime,
    monthly_fee:             parseFloat(r.monthly_fee ?? 0) || 0,
    fee_received_this_month: r.fee_received_this_month,
    notes:                   r.notes,
    is_active:               r.is_active,
    employees:               asArray(r.employees).map(normalizeEmployee),
    checklist:               asArray(r.checklist).map(normalizeChecklistItem),
  };
}

function normalizeClient(b = {}) {
  return {
    id:         b.id,
    name:       b.name,
    binOrIin:   b.bin_or_iin ?? b.binOrIin ?? '',
    entityType: b.entity_type ?? b.entityType,
    regime:     b.regime,
    monthlyFee: Number(b.monthly_fee ?? b.monthlyFee ?? 0) || 0,
    feeReceivedThisMonth:
      Boolean(b.fee_received_this_month ?? b.feeReceivedThisMonth ?? false),
    notes:      b.notes ?? null,
    isActive:   Boolean(b.is_active ?? b.isActive ?? true),
    employees:  asArray(b.employees).map(normalizeEmployee),
    checklist:  asArray(b.checklist).map(normalizeChecklistItem),
  };
}

function validate(c) {
  if (!c.id || !c.name) return 'Обязательные поля: id, name';
  if (!ENTITY_TYPES.includes(c.entityType)) {
    return `entity_type должен быть одним из: ${ENTITY_TYPES.join(', ')}`;
  }
  if (!REGIMES.includes(c.regime)) {
    return `regime должен быть одним из: ${REGIMES.join(', ')}`;
  }
  return null;
}

// GET /api/accounting/clients
router.get('/clients', async (req, res) => {
  try {
    const { rows } = await db.query(
      `SELECT id, name, bin_or_iin, entity_type, regime, monthly_fee,
              fee_received_this_month, notes, is_active, employees, checklist
       FROM accounting_clients
       WHERE user_id = $1
       ORDER BY created_at`,
      [req.userId],
    );
    res.json(rows.map(serializeClient));
  } catch (err) {
    console.error('GET /accounting/clients error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// POST /api/accounting/clients — один клиент или массив (первичная синхронизация)
router.post('/clients', async (req, res) => {
  try {
    const items = (Array.isArray(req.body) ? req.body : [req.body]).map(normalizeClient);
    for (const c of items) {
      const err = validate(c);
      if (err) return res.status(400).json({ error: err });
    }

    const client = await db.connect();
    try {
      await client.query('BEGIN');

      // Чужой id: upsert ниже ограничен user_id и просто ничего не сделает —
      // без этой проверки клиент получил бы «сохранено» на пустом месте.
      const { rows: foreign } = await client.query(
        `SELECT id FROM accounting_clients
         WHERE id = ANY($1::text[]) AND user_id <> $2`,
        [items.map((c) => c.id), req.userId],
      );
      if (foreign.length) {
        await client.query('ROLLBACK');
        return res.status(409).json({
          error: 'Клиент с таким id принадлежит другому пользователю',
          ids: foreign.map((r) => r.id),
        });
      }

      for (const c of items) {
        await client.query(
          `INSERT INTO accounting_clients
             (id, user_id, name, bin_or_iin, entity_type, regime, monthly_fee,
              fee_received_this_month, notes, is_active, employees, checklist)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb,$12::jsonb)
           ON CONFLICT (id) DO UPDATE SET
             name = EXCLUDED.name,
             bin_or_iin = EXCLUDED.bin_or_iin,
             entity_type = EXCLUDED.entity_type,
             regime = EXCLUDED.regime,
             monthly_fee = EXCLUDED.monthly_fee,
             fee_received_this_month = EXCLUDED.fee_received_this_month,
             notes = EXCLUDED.notes,
             is_active = EXCLUDED.is_active,
             employees = EXCLUDED.employees,
             checklist = EXCLUDED.checklist,
             updated_at = NOW()
           WHERE accounting_clients.user_id = $2`,
          [
            c.id, req.userId, c.name, c.binOrIin, c.entityType, c.regime,
            c.monthlyFee, c.feeReceivedThisMonth, c.notes, c.isActive,
            JSON.stringify(c.employees), JSON.stringify(c.checklist),
          ],
        );
      }
      await client.query('COMMIT');
    } catch (txErr) {
      await client.query('ROLLBACK');
      throw txErr;
    } finally {
      client.release();
    }

    res.status(201).json({ ok: true, count: items.length });
  } catch (err) {
    console.error('POST /accounting/clients error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// PUT /api/accounting/clients/:id
router.put('/clients/:id', async (req, res) => {
  try {
    const c = normalizeClient({ ...req.body, id: req.params.id });
    const err = validate(c);
    if (err) return res.status(400).json({ error: err });

    const result = await db.query(
      `UPDATE accounting_clients
       SET name=$1, bin_or_iin=$2, entity_type=$3, regime=$4, monthly_fee=$5,
           fee_received_this_month=$6, notes=$7, is_active=$8,
           employees=$9::jsonb, checklist=$10::jsonb, updated_at=NOW()
       WHERE id=$11 AND user_id=$12`,
      [
        c.name, c.binOrIin, c.entityType, c.regime, c.monthlyFee,
        c.feeReceivedThisMonth, c.notes, c.isActive,
        JSON.stringify(c.employees), JSON.stringify(c.checklist),
        req.params.id, req.userId,
      ],
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Клиент не найден' });
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('PUT /accounting/clients/:id error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

// DELETE /api/accounting/clients/:id
router.delete('/clients/:id', async (req, res) => {
  try {
    const result = await db.query(
      'DELETE FROM accounting_clients WHERE id=$1 AND user_id=$2',
      [req.params.id, req.userId],
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Клиент не найден' });
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('DELETE /accounting/clients/:id error:', err);
    res.status(500).json({ error: 'Внутренняя ошибка сервера' });
  }
});

module.exports = router;
// Чистые функции контракта — для юнит-тестов
module.exports.serializeClient = serializeClient;
module.exports.normalizeClient = normalizeClient;
