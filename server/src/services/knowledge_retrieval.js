// ── Hybrid retrieval ─────────────────────────────────────────────────────────
// Поиск по базе знаний:
//   1. BM25 по русской тематической tsvector
//   2. Cosine similarity по embeddings
//   3. Reciprocal Rank Fusion (RRF) для слияния
//   4. Boost по trust_weight источника
//   5. Фильтр по audience (ip_solo / too / accountant / all)
//   6. Опциональный «only official» — только trust_weight ≥ 0.9

const db = require('../db');
const { embed, toPgVector } = require('./embeddings');

const RRF_K = 60;

/**
 * @param {Object} opts
 * @param {string} opts.query              — текст вопроса
 * @param {string} [opts.audience]         — 'ip_solo' | 'ip_emp' | 'too' | 'accountant' | 'all'
 * @param {boolean} [opts.officialOnly]    — оставить только официальные источники
 * @param {string[]} [opts.sourceTypes]    — фильтр по типам источника
 * @param {number} [opts.topK]             — сколько вернуть после слияния (default 8)
 * @param {number} [opts.candidateK]       — сколько брать из каждого ретривера (default 25)
 */
async function retrieve(opts) {
  const {
    query,
    audience = 'all',
    officialOnly = false,
    sourceTypes = null,
    topK = 8,
    candidateK = 25,
  } = opts;

  if (!query || !query.trim()) return [];

  // ── Параметры фильтрации ───────────────────────────────────────────────────
  const whereParts = ['ks.is_active = TRUE'];
  const params = [];
  let p = 0;

  // audience: показываем чанки соответствующие сегменту + те что 'all'
  if (audience && audience !== 'all') {
    params.push(audience);
    p++;
    whereParts.push(`(kc.audience_hint = $${p} OR kc.audience_hint = 'all')`);
  }

  if (officialOnly) {
    whereParts.push(`ks.trust_weight >= 0.9`);
  }

  if (sourceTypes && sourceTypes.length) {
    params.push(sourceTypes);
    p++;
    whereParts.push(`ks.source_type = ANY($${p}::text[])`);
  }

  const whereSql = whereParts.join(' AND ');

  // ── 1) BM25 ────────────────────────────────────────────────────────────────
  params.push(query); p++;
  const queryParam = p;
  params.push(candidateK); p++;
  const bm25Limit = p;

  const bm25Sql = `
    SELECT kc.id,
           ts_rank_cd(kc.bm25_tsv, plainto_tsquery('russian', $${queryParam})) AS score
      FROM knowledge_chunk kc
      JOIN knowledge_source ks ON ks.id = kc.source_id
     WHERE ${whereSql}
       AND kc.bm25_tsv @@ plainto_tsquery('russian', $${queryParam})
     ORDER BY score DESC
     LIMIT $${bm25Limit}
  `;
  const bm25Res = await db.query(bm25Sql, params);

  // ── 2) Vector ─────────────────────────────────────────────────────────────
  const [qVec] = await embed(query);
  const vecParams = params.slice(0, p - 2); // те же фильтры, но без $queryParam и $bm25Limit
  vecParams.push(toPgVector(qVec));
  vecParams.push(candidateK);
  const vecQueryParam = vecParams.length - 1;
  const vecLimit      = vecParams.length;

  const vecSql = `
    SELECT kc.id,
           1 - (kc.embedding <=> $${vecQueryParam}::vector) AS score
      FROM knowledge_chunk kc
      JOIN knowledge_source ks ON ks.id = kc.source_id
     WHERE ${whereSql}
       AND kc.embedding IS NOT NULL
     ORDER BY kc.embedding <=> $${vecQueryParam}::vector
     LIMIT $${vecLimit}
  `;
  const vecRes = await db.query(vecSql, vecParams);

  // ── 3) RRF слияние ─────────────────────────────────────────────────────────
  const fused = new Map(); // chunk_id -> {rrf, bm25, vec}
  bm25Res.rows.forEach((row, idx) => {
    const id = row.id;
    fused.set(id, {
      id,
      rrf: 1 / (RRF_K + idx + 1),
      bm25: parseFloat(row.score),
      vec: 0,
    });
  });
  vecRes.rows.forEach((row, idx) => {
    const id = row.id;
    const entry = fused.get(id) || { id, rrf: 0, bm25: 0, vec: 0 };
    entry.rrf += 1 / (RRF_K + idx + 1);
    entry.vec = parseFloat(row.score);
    fused.set(id, entry);
  });

  if (fused.size === 0) return [];

  // ── 4) Получим тексты, метаданные, boost по trust_weight ───────────────────
  const ids = Array.from(fused.keys());
  const detail = await db.query(
    `SELECT kc.id, kc.text, kc.anchor, kc.audience_hint, kc.complexity,
            ks.id  AS source_id,
            ks.url, ks.title, ks.source_type,
            ks.trust_weight, ks.published_at, ks.metadata
       FROM knowledge_chunk kc
       JOIN knowledge_source ks ON ks.id = kc.source_id
      WHERE kc.id = ANY($1::uuid[])`,
    [ids]
  );

  const enriched = detail.rows.map(r => {
    const f = fused.get(r.id);
    const trust = parseFloat(r.trust_weight);
    // Финальный score: RRF * (0.6 + 0.4 * trust)
    const finalScore = f.rrf * (0.6 + 0.4 * trust);
    return {
      chunkId: r.id,
      sourceId: r.source_id,
      text: r.text,
      anchor: r.anchor,
      audienceHint: r.audience_hint,
      complexity: r.complexity,
      url: r.url,
      title: r.title,
      sourceType: r.source_type,
      trustWeight: trust,
      publishedAt: r.published_at,
      metadata: r.metadata || {},
      bm25Score: f.bm25,
      vectorScore: f.vec,
      rrfScore: f.rrf,
      score: finalScore,
    };
  });

  enriched.sort((a, b) => b.score - a.score);
  return enriched.slice(0, topK);
}

module.exports = { retrieve };
