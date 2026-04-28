// ── Knowledge indexer ────────────────────────────────────────────────────────
// Утилиты для:
//   • upsert-а источника
//   • разбиения текста на чанки
//   • embed + insert в knowledge_chunk
//   • проверки изменений по хешу

const crypto = require('crypto');
const db = require('../db');
const { embed, toPgVector } = require('./embeddings');

const CHUNK_TARGET_SIZE = 600;   // ~примерно символов
const CHUNK_OVERLAP     = 100;

function hashContent(s) {
  return crypto.createHash('sha256').update(s).digest('hex');
}

/**
 * Простой чанкер: разбивает текст на куски близкие к CHUNK_TARGET_SIZE,
 * стараясь резать по абзацам / предложениям.
 */
function chunkText(text, target = CHUNK_TARGET_SIZE, overlap = CHUNK_OVERLAP) {
  const clean = (text || '').replace(/\r\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
  if (clean.length <= target) return [clean].filter(Boolean);

  // Разбиваем по абзацам, потом склеиваем
  const paragraphs = clean.split(/\n\n+/);
  const chunks = [];
  let buf = '';
  for (const p of paragraphs) {
    if ((buf + '\n\n' + p).length > target && buf.length > 0) {
      chunks.push(buf.trim());
      // overlap: оставляем хвост предыдущего
      const tail = buf.slice(Math.max(0, buf.length - overlap));
      buf = tail + '\n\n' + p;
    } else {
      buf = buf ? buf + '\n\n' + p : p;
    }
  }
  if (buf.trim()) chunks.push(buf.trim());
  return chunks;
}

/**
 * Upsert документа-источника.
 * Возвращает {id, isNew, contentChanged}.
 */
async function upsertSource({
  url,
  title,
  sourceType,
  trustWeight = 0.5,
  publishedAt = null,
  rawContent,
  language = 'ru',
  metadata = {},
}) {
  const contentHash = hashContent(rawContent || '');

  const existing = await db.query(
    `SELECT id, content_hash FROM knowledge_source WHERE url = $1`,
    [url]
  );

  if (existing.rows.length === 0) {
    const ins = await db.query(
      `INSERT INTO knowledge_source
         (url, title, source_type, trust_weight, published_at,
          raw_content, content_hash, language, metadata)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb)
       RETURNING id`,
      [url, title, sourceType, trustWeight, publishedAt,
       rawContent, contentHash, language, JSON.stringify(metadata)]
    );
    return { id: ins.rows[0].id, isNew: true, contentChanged: true };
  }

  const row = existing.rows[0];
  const changed = row.content_hash !== contentHash;
  if (changed) {
    await db.query(
      `UPDATE knowledge_source
          SET title = $1, source_type = $2, trust_weight = $3, published_at = $4,
              raw_content = $5, content_hash = $6, language = $7,
              metadata = $8::jsonb, fetched_at = NOW(), is_active = TRUE
        WHERE id = $9`,
      [title, sourceType, trustWeight, publishedAt,
       rawContent, contentHash, language, JSON.stringify(metadata), row.id]
    );
    // Удалим старые чанки — заменим новыми
    await db.query(`DELETE FROM knowledge_chunk WHERE source_id = $1`, [row.id]);
  }
  return { id: row.id, isNew: false, contentChanged: changed };
}

/**
 * Разбить текст на чанки и записать с embeddings.
 * chunks: [{text, anchor?, audienceHint?, complexity?}]
 * Если передан только rawText — чанкуем сами.
 */
async function indexChunks(sourceId, chunks) {
  if (!chunks.length) return 0;

  const texts = chunks.map(c => c.text);
  const vectors = await embed(texts);

  for (let i = 0; i < chunks.length; i++) {
    const c = chunks[i];
    const v = vectors[i];
    await db.query(
      `INSERT INTO knowledge_chunk
         (source_id, chunk_index, text, embedding, bm25_tsv,
          anchor, audience_hint, complexity)
       VALUES ($1, $2, $3, $4::vector,
               to_tsvector('russian', $3),
               $5, $6, $7)
       ON CONFLICT (source_id, chunk_index) DO UPDATE
         SET text          = EXCLUDED.text,
             embedding     = EXCLUDED.embedding,
             bm25_tsv      = EXCLUDED.bm25_tsv,
             anchor        = EXCLUDED.anchor,
             audience_hint = EXCLUDED.audience_hint,
             complexity    = EXCLUDED.complexity`,
      [sourceId, i, c.text, toPgVector(v),
       c.anchor || null, c.audienceHint || 'all', c.complexity || 'medium']
    );
  }
  return chunks.length;
}

/**
 * Высокоуровневая функция: upsert источник + переиндексировать чанки если контент менялся.
 * Если chunks не передан — разобьём rawContent сами.
 */
async function indexSource(opts) {
  const upserted = await upsertSource(opts);
  if (!upserted.contentChanged) return { ...upserted, chunksIndexed: 0 };

  const chunks = opts.chunks ||
    chunkText(opts.rawContent).map(t => ({
      text: t,
      audienceHint: opts.audienceHint || 'all',
      complexity:   opts.complexity || 'medium',
    }));

  const n = await indexChunks(upserted.id, chunks);
  return { ...upserted, chunksIndexed: n };
}

module.exports = {
  hashContent,
  chunkText,
  upsertSource,
  indexChunks,
  indexSource,
};
