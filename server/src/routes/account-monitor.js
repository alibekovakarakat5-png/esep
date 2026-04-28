// ── Routes: /api/account ─────────────────────────────────────────────────────
// Монитор лицевого счёта в налоговой.
//
// Закрывает боль: "оплатил налог, а на лицевом счёте висит / разнеслось не туда".
// Пользователь фиксирует факт оплаты, через 5/14 дней мы напоминаем проверить
// разноску. Если не разнесено — флаг + AI-помощник подскажет шаги.
//
// POST   /payments              добавить платёж
// GET    /payments              список платежей пользователя
// PATCH  /payments/:id          обновить статус (posted / misposted / missing)
// DELETE /payments/:id          удалить
// GET    /alerts                просроченные проверки и расхождения

const router = require('express').Router();
const db     = require('../db');

const PENDING_REMIND_DAYS = 14;  // через сколько дней просим проверить
const PENDING_RED_DAYS    = 30;  // когда становится "точно проблема"

function requireUser(req, res) {
  const id = req.user?.id;
  if (!id) { res.status(401).json({ error: 'Требуется авторизация' }); return null; }
  return id;
}

// ── POST /payments ──────────────────────────────────────────────────────────

router.post('/payments', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  const {
    kbk, kbk_label, tax_period, paid_amount, paid_at, bank,
    payment_doc, expected_period_kbk, note, attachment_url,
  } = req.body;

  if (!kbk || !paid_amount || !paid_at) {
    return res.status(400).json({ error: 'kbk, paid_amount, paid_at обязательны' });
  }

  try {
    const r = await db.query(
      `INSERT INTO account_payment
         (user_id, kbk, kbk_label, tax_period, paid_amount, paid_at, bank,
          payment_doc, expected_period_kbk, note, attachment_url, actual_status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'pending_check')
       RETURNING *`,
      [userId, kbk, kbk_label || null, tax_period || null, paid_amount, paid_at,
       bank || null, payment_doc || null, expected_period_kbk || kbk,
       note || null, attachment_url || null]
    );
    res.json(r.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── GET /payments ───────────────────────────────────────────────────────────

router.get('/payments', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  try {
    const r = await db.query(
      `SELECT id, kbk, kbk_label, tax_period, paid_amount, paid_at, bank,
              payment_doc, expected_period_kbk, actual_status, mispost_kbk,
              checked_at, note, attachment_url, created_at,
              EXTRACT(DAY FROM (NOW() - paid_at))::int AS days_since_paid
         FROM account_payment
        WHERE user_id = $1
        ORDER BY paid_at DESC, created_at DESC
        LIMIT 200`,
      [userId]
    );
    res.json(r.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── PATCH /payments/:id ─────────────────────────────────────────────────────

router.patch('/payments/:id', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  const { actual_status, mispost_kbk, note } = req.body;

  if (actual_status && !['pending_check', 'posted', 'misposted', 'missing'].includes(actual_status)) {
    return res.status(400).json({ error: 'Невалидный actual_status' });
  }

  try {
    const r = await db.query(
      `UPDATE account_payment
          SET actual_status = COALESCE($1, actual_status),
              mispost_kbk   = COALESCE($2, mispost_kbk),
              note          = COALESCE($3, note),
              checked_at    = CASE WHEN $1 IN ('posted','misposted','missing') THEN NOW() ELSE checked_at END,
              updated_at    = NOW()
        WHERE id = $4 AND user_id = $5
        RETURNING *`,
      [actual_status || null, mispost_kbk || null, note || null, req.params.id, userId]
    );
    if (r.rows.length === 0) return res.status(404).json({ error: 'Платёж не найден' });
    res.json(r.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── DELETE /payments/:id ────────────────────────────────────────────────────

router.delete('/payments/:id', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  try {
    await db.query(
      `DELETE FROM account_payment WHERE id = $1 AND user_id = $2`,
      [req.params.id, userId]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── GET /alerts ─────────────────────────────────────────────────────────────

router.get('/alerts', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  try {
    // Алерты:
    //   1. pending_check + дата >= PENDING_REMIND_DAYS  → "пора проверить"
    //   2. pending_check + дата >= PENDING_RED_DAYS     → "точно проблема"
    //   3. misposted                                    → "разнеслось не туда, нужно письмо в КГД"
    //   4. missing                                      → "вообще не разнеслось"

    const r = await db.query(
      `SELECT id, kbk, kbk_label, tax_period, paid_amount, paid_at,
              actual_status, mispost_kbk, note,
              EXTRACT(DAY FROM (NOW() - paid_at))::int AS days_since_paid
         FROM account_payment
        WHERE user_id = $1
          AND (
                (actual_status = 'pending_check' AND paid_at <= NOW() - INTERVAL '${PENDING_REMIND_DAYS} days')
             OR actual_status IN ('misposted', 'missing')
              )
        ORDER BY paid_at ASC`,
      [userId]
    );

    const alerts = r.rows.map(p => {
      let level = 'info';
      let title = '';
      let action = '';
      if (p.actual_status === 'misposted') {
        level = 'red';
        title = `КПН ${formatAmount(p.paid_amount)} разнеслось не на тот код`;
        action = `Деньги ушли на ${p.mispost_kbk || 'другой КБК'} вместо ${p.kbk}. Напишите заявление в КГД о переносе через cabinet.salyk.kz → "Заявления и запросы".`;
      } else if (p.actual_status === 'missing') {
        level = 'red';
        title = `КПН ${formatAmount(p.paid_amount)} не разнеслось`;
        action = `Платёж от ${p.paid_at} не виден на лицевом счёте. Прикрепите платёжку и напишите в техподдержку cabinet.salyk.kz.`;
      } else if (p.days_since_paid >= PENDING_RED_DAYS) {
        level = 'red';
        title = `Платёж от ${p.paid_at} висит ${p.days_since_paid} дней`;
        action = 'Зайдите в кабинет налогоплательщика и проверьте состояние лицевого счёта по этому КБК.';
      } else {
        level = 'yellow';
        title = `Проверьте разноску платежа от ${p.paid_at}`;
        action = 'Прошло достаточно времени — пора зайти в кабинет налогоплательщика и удостовериться, что деньги учтены.';
      }
      return { ...p, level, alert_title: title, alert_action: action };
    });

    res.json(alerts);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

function formatAmount(n) {
  return Number(n).toLocaleString('ru-RU') + ' ₸';
}

module.exports = router;
