// ── Routes: /api/esf-recon ───────────────────────────────────────────────────
// Сверка входящих ЭСФ с зачётом по НДС (форма 300).
//
// POST /sessions                    создать сессию
// POST /sessions/:id/registry       загрузить XLSX реестр ЭСФ (multipart)
// POST /sessions/:id/notice         загрузить XLSX извещение ф.300 (multipart)
// POST /sessions/:id/match          запустить матчинг
// GET  /sessions                    список сессий пользователя
// GET  /sessions/:id                деталь + статистика
// GET  /sessions/:id/results?type=  расхождения (matched|amount_diff|...)
// DELETE /sessions/:id              удалить

const router  = require('express').Router();
const multer  = require('multer');
const db      = require('../db');

const { parseEsfRegistry, parseForm300Notice } = require('../services/esf_xlsx_parser');
const { match: runMatch, buildStats } = require('../services/esf_matcher');

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 30 * 1024 * 1024 }, // 30 MB
});

function requireUser(req, res) {
  const id = req.user?.id;
  if (!id) { res.status(401).json({ error: 'Требуется авторизация' }); return null; }
  return id;
}

// ── POST /sessions ──────────────────────────────────────────────────────────

router.post('/sessions', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  const { title, period_from, period_to } = req.body;
  if (!period_from || !period_to) {
    return res.status(400).json({ error: 'Укажите period_from и period_to' });
  }
  try {
    const r = await db.query(
      `INSERT INTO esf_recon_session (user_id, title, period_from, period_to)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [userId, title || `Сверка за ${period_from} – ${period_to}`, period_from, period_to]
    );
    res.json(r.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── GET /sessions ───────────────────────────────────────────────────────────

router.get('/sessions', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  try {
    const r = await db.query(
      `SELECT id, title, period_from, period_to, status,
              registry_filename, notice_filename, stats,
              created_at, updated_at
         FROM esf_recon_session
        WHERE user_id = $1
        ORDER BY created_at DESC
        LIMIT 50`,
      [userId]
    );
    res.json(r.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── GET /sessions/:id ───────────────────────────────────────────────────────

router.get('/sessions/:id', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  try {
    const r = await db.query(
      `SELECT * FROM esf_recon_session WHERE id = $1 AND user_id = $2`,
      [req.params.id, userId]
    );
    if (r.rows.length === 0) return res.status(404).json({ error: 'Сессия не найдена' });
    res.json(r.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── DELETE /sessions/:id ────────────────────────────────────────────────────

router.delete('/sessions/:id', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  try {
    await db.query(
      `DELETE FROM esf_recon_session WHERE id = $1 AND user_id = $2`,
      [req.params.id, userId]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── POST /sessions/:id/registry ─────────────────────────────────────────────

router.post('/sessions/:id/registry', upload.single('file'), async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  const sessionId = req.params.id;
  if (!req.file) return res.status(400).json({ error: 'Файл не передан (поле "file")' });

  try {
    // Проверка владельца
    const own = await db.query(
      `SELECT period_from, period_to FROM esf_recon_session WHERE id = $1 AND user_id = $2`,
      [sessionId, userId]
    );
    if (own.rows.length === 0) return res.status(404).json({ error: 'Сессия не найдена' });
    const { period_from, period_to } = own.rows[0];

    const rows = await parseEsfRegistry(req.file.buffer);
    if (rows.length === 0) {
      return res.status(400).json({
        error: 'Не удалось распознать ни одной строки. Проверьте, что файл — это реестр ЭСФ из esf.gov.kz в формате XLSX.',
      });
    }

    // Удалим старые ЭСФ за этот период от этого пользователя из этого источника
    await db.query(
      `DELETE FROM esf_invoice
        WHERE user_id = $1 AND source_file = $2`,
      [userId, req.file.originalname]
    );

    // Вставим новые
    let inserted = 0, skipped = 0;
    for (const row of rows) {
      // Фильтруем по периоду сессии
      if (row.invoice_date < period_from || row.invoice_date > period_to) {
        skipped++;
        continue;
      }
      try {
        await db.query(
          `INSERT INTO esf_invoice
             (user_id, registration_no, invoice_no, invoice_date, turnover_date,
              direction, status, seller_iin, seller_name, buyer_iin, buyer_name,
              amount_net, amount_vat, amount_total, vat_rate, currency,
              source, source_file, raw_row)
           VALUES ($1,$2,$3,$4,$5,'INCOMING',$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,
                   'xlsx_import', $16, $17::jsonb)
           ON CONFLICT (user_id, registration_no) DO UPDATE
             SET invoice_no   = EXCLUDED.invoice_no,
                 invoice_date = EXCLUDED.invoice_date,
                 status       = EXCLUDED.status,
                 amount_total = EXCLUDED.amount_total,
                 amount_vat   = EXCLUDED.amount_vat,
                 imported_at  = NOW()`,
          [
            userId, row.registration_no, row.invoice_no, row.invoice_date, row.turnover_date,
            row.status, row.seller_iin, row.seller_name, row.buyer_iin, row.buyer_name,
            row.amount_net, row.amount_vat, row.amount_total, row.vat_rate, row.currency,
            req.file.originalname, JSON.stringify(row.raw_row),
          ]
        );
        inserted++;
      } catch (e) {
        skipped++;
      }
    }

    await db.query(
      `UPDATE esf_recon_session
          SET registry_filename = $1, updated_at = NOW()
        WHERE id = $2`,
      [req.file.originalname, sessionId]
    );

    res.json({ inserted, skipped, total_rows: rows.length });
  } catch (err) {
    console.error('[esf-recon] registry upload failed:', err);
    res.status(400).json({ error: err.message });
  }
});

// ── POST /sessions/:id/notice ───────────────────────────────────────────────

router.post('/sessions/:id/notice', upload.single('file'), async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  const sessionId = req.params.id;
  if (!req.file) return res.status(400).json({ error: 'Файл не передан (поле "file")' });

  try {
    const own = await db.query(
      `SELECT id FROM esf_recon_session WHERE id = $1 AND user_id = $2`,
      [sessionId, userId]
    );
    if (own.rows.length === 0) return res.status(404).json({ error: 'Сессия не найдена' });

    const rows = await parseForm300Notice(req.file.buffer);
    if (rows.length === 0) {
      return res.status(400).json({
        error: 'Не удалось распознать строки извещения. Проверьте, что это XLSX извещения по форме 300.',
      });
    }

    // Перезаписываем все строки извещения в сессии
    await db.query(`DELETE FROM esf_notice_row WHERE session_id = $1`, [sessionId]);
    let i = 0;
    for (const row of rows) {
      i++;
      await db.query(
        `INSERT INTO esf_notice_row
           (session_id, row_index, seller_iin, seller_name, invoice_no, invoice_date,
            amount_net, amount_vat, amount_total, vat_rate, raw_row)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb)`,
        [
          sessionId, i, row.seller_iin, row.seller_name, row.invoice_no, row.invoice_date,
          row.amount_net, row.amount_vat, row.amount_total, row.vat_rate,
          JSON.stringify(row.raw_row),
        ]
      );
    }

    await db.query(
      `UPDATE esf_recon_session
          SET notice_filename = $1, updated_at = NOW()
        WHERE id = $2`,
      [req.file.originalname, sessionId]
    );

    res.json({ inserted: rows.length });
  } catch (err) {
    console.error('[esf-recon] notice upload failed:', err);
    res.status(400).json({ error: err.message });
  }
});

// ── POST /sessions/:id/match ────────────────────────────────────────────────

router.post('/sessions/:id/match', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  const sessionId = req.params.id;
  try {
    const own = await db.query(
      `SELECT period_from, period_to FROM esf_recon_session WHERE id = $1 AND user_id = $2`,
      [sessionId, userId]
    );
    if (own.rows.length === 0) return res.status(404).json({ error: 'Сессия не найдена' });
    const { period_from, period_to } = own.rows[0];

    const esfRes = await db.query(
      `SELECT id, registration_no, invoice_no, invoice_date, status,
              seller_iin, seller_name, amount_net, amount_vat, amount_total
         FROM esf_invoice
        WHERE user_id = $1
          AND direction = 'INCOMING'
          AND invoice_date BETWEEN $2 AND $3`,
      [userId, period_from, period_to]
    );

    const noticeRes = await db.query(
      `SELECT id, seller_iin, seller_name, invoice_no, invoice_date,
              amount_net, amount_vat, amount_total
         FROM esf_notice_row WHERE session_id = $1`,
      [sessionId]
    );

    if (esfRes.rows.length === 0 && noticeRes.rows.length === 0) {
      return res.status(400).json({ error: 'Загрузите хотя бы один из файлов: реестр ЭСФ или извещение ф.300' });
    }

    const matches = runMatch(esfRes.rows, noticeRes.rows);
    const stats   = buildStats(matches);

    // Чистим старые результаты
    await db.query(`DELETE FROM esf_recon_match WHERE session_id = $1`, [sessionId]);
    for (const m of matches) {
      await db.query(
        `INSERT INTO esf_recon_match
           (session_id, esf_id, notice_row_id, match_type, confidence, diff)
         VALUES ($1, $2, $3, $4, $5, $6::jsonb)`,
        [sessionId, m.esf_id || null, m.notice_row_id || null,
         m.match_type, m.confidence, JSON.stringify(m.diff)]
      );
    }

    await db.query(
      `UPDATE esf_recon_session
          SET status = 'matched', stats = $1::jsonb, updated_at = NOW()
        WHERE id = $2`,
      [JSON.stringify(stats), sessionId]
    );

    res.json({ ok: true, stats });
  } catch (err) {
    console.error('[esf-recon] match failed:', err);
    res.status(500).json({ error: err.message });
  }
});

// ── GET /sessions/:id/results?type=... ──────────────────────────────────────

router.get('/sessions/:id/results', async (req, res) => {
  const userId = requireUser(req, res);
  if (!userId) return;
  const sessionId = req.params.id;
  const type = req.query.type || null;

  try {
    const own = await db.query(
      `SELECT id FROM esf_recon_session WHERE id = $1 AND user_id = $2`,
      [sessionId, userId]
    );
    if (own.rows.length === 0) return res.status(404).json({ error: 'Сессия не найдена' });

    const params = [sessionId];
    let where = `m.session_id = $1`;
    if (type) { params.push(type); where += ` AND m.match_type = $${params.length}`; }

    const r = await db.query(
      `SELECT m.id, m.match_type, m.confidence, m.diff,
              e.registration_no, e.invoice_no AS esf_invoice_no, e.invoice_date AS esf_date,
              e.status AS esf_status, e.seller_iin AS esf_seller_iin,
              e.seller_name AS esf_seller_name,
              e.amount_total AS esf_total, e.amount_vat AS esf_vat,
              n.invoice_no AS notice_invoice_no, n.invoice_date AS notice_date,
              n.seller_iin AS notice_seller_iin, n.seller_name AS notice_seller_name,
              n.amount_total AS notice_total, n.amount_vat AS notice_vat
         FROM esf_recon_match m
         LEFT JOIN esf_invoice e ON e.id = m.esf_id
         LEFT JOIN esf_notice_row n ON n.id = m.notice_row_id
        WHERE ${where}
        ORDER BY
          CASE m.match_type
            WHEN 'status_red'  THEN 0
            WHEN 'only_notice' THEN 1
            WHEN 'amount_diff' THEN 2
            WHEN 'only_esf'    THEN 3
            WHEN 'matched'     THEN 4
            ELSE 5
          END,
          COALESCE(e.invoice_date, n.invoice_date) DESC`,
      params
    );

    res.json(r.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
