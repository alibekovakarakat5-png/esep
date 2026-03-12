const router   = require('express').Router();
const db        = require('../db');
const { adminAuth } = require('./admin');
const tg        = require('../bot/telegram');

// ── GET /api/articles — public list ──────────────────────────────────────────
router.get('/', async (req, res) => {
  const { audience } = req.query; // 'ip' | 'accountant' | undefined = all
  const { rows } = await db.query(
    `SELECT id, slug, title, summary, audience, tags, published_at, updated_at
     FROM articles
     WHERE status = 'published'
       AND ($1::text IS NULL OR audience = $1 OR audience = 'all')
     ORDER BY published_at DESC`,
    [audience ?? null],
  );
  res.json(rows);
});

// ── GET /api/articles/:slug — public single ───────────────────────────────────
router.get('/:slug', async (req, res) => {
  const { rows } = await db.query(
    `SELECT * FROM articles WHERE slug = $1 AND status = 'published'`,
    [req.params.slug],
  );
  if (!rows.length) return res.status(404).json({ error: 'Not found' });
  res.json(rows[0]);
});

// ── GET /api/articles/admin/all — admin full list ─────────────────────────────
router.get('/admin/all', adminAuth, async (_req, res) => {
  const { rows } = await db.query(
    `SELECT id, slug, title, audience, status, tags, published_at, created_at
     FROM articles ORDER BY created_at DESC`,
  );
  res.json(rows);
});

// ── POST /api/articles — create draft (admin) ─────────────────────────────────
router.post('/', adminAuth, async (req, res) => {
  const { slug, title, summary, body, audience = 'ip', tags = [], status = 'draft' } = req.body;
  if (!slug || !title) return res.status(400).json({ error: 'slug and title required' });

  const { rows: [art] } = await db.query(
    `INSERT INTO articles (slug, title, summary, body, audience, tags, status,
                           published_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7, CASE WHEN $7='published' THEN NOW() ELSE NULL END)
     RETURNING id`,
    [slug, title, summary, body, audience, JSON.stringify(tags), status],
  );

  // Notify via Telegram if draft needs review
  if (status === 'draft') {
    const adminUrl = process.env.ADMIN_URL ?? `https://esep-production.up.railway.app`;
    tg.notifyArticleDraft({ title, id: art.id, adminUrl });
  }

  res.status(201).json({ ok: true, id: art.id });
});

// ── PUT /api/articles/:id — update (admin) ────────────────────────────────────
router.put('/:id', adminAuth, async (req, res) => {
  const { slug, title, summary, body, audience, tags, status } = req.body;
  await db.query(
    `UPDATE articles
     SET slug        = COALESCE($1, slug),
         title       = COALESCE($2, title),
         summary     = COALESCE($3, summary),
         body        = COALESCE($4, body),
         audience    = COALESCE($5, audience),
         tags        = COALESCE($6::jsonb, tags),
         status      = COALESCE($7, status),
         published_at = CASE
           WHEN $7 = 'published' AND published_at IS NULL THEN NOW()
           ELSE published_at
         END,
         updated_at  = NOW()
     WHERE id = $8`,
    [slug, title, summary, body, audience,
     tags ? JSON.stringify(tags) : null, status, req.params.id],
  );
  res.json({ ok: true });
});

// ── DELETE /api/articles/:id — admin only ─────────────────────────────────────
router.delete('/:id', adminAuth, async (req, res) => {
  await db.query('DELETE FROM articles WHERE id = $1', [req.params.id]);
  res.json({ ok: true });
});

module.exports = router;
