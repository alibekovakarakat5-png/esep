// ── Embeddings provider ──────────────────────────────────────────────────────
// Поддерживаем OpenAI text-embedding-3-small (1536 dim, дёшево, отличное качество для RU).
// Если ключа нет — fallback на детерминированный hash-embedding (не для прод-RAG, только чтоб не падать).
//
// Env:
//   OPENAI_API_KEY        — ключ OpenAI (опционально)
//   EMBEDDING_PROVIDER    — 'openai' | 'hash' (default: auto)
//   EMBEDDING_MODEL       — default: 'text-embedding-3-small'
//   EMBEDDING_DIM         — default: 1536

const crypto = require('crypto');

const PROVIDER = process.env.EMBEDDING_PROVIDER ||
  (process.env.OPENAI_API_KEY ? 'openai' : 'hash');
const MODEL    = process.env.EMBEDDING_MODEL || 'text-embedding-3-small';
const DIM      = parseInt(process.env.EMBEDDING_DIM || '1536', 10);

console.log(`[embeddings] provider=${PROVIDER} model=${MODEL} dim=${DIM}`);

// ── OpenAI provider ──────────────────────────────────────────────────────────

async function embedOpenAI(texts) {
  const res = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      input: texts,
      dimensions: DIM,
    }),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`OpenAI embeddings ${res.status}: ${err}`);
  }
  const data = await res.json();
  return data.data.map(d => d.embedding);
}

// ── Hash fallback (НЕ для прода) ─────────────────────────────────────────────
// Детерминированный embedding на основе SHA-256 — позволяет коду работать
// без внешних API. Качество retrieval будет плохим, но поиск по BM25 продолжит работать.

function embedHash(texts) {
  return texts.map(t => {
    const h = crypto.createHash('sha256').update(t).digest();
    const out = new Array(DIM);
    for (let i = 0; i < DIM; i++) {
      // 4 байта на float, нормируем в [-1,1]
      const b = h.readUInt32BE((i * 4) % (h.length - 4));
      out[i] = (b / 0xffffffff) * 2 - 1;
    }
    // нормализация по L2
    const norm = Math.sqrt(out.reduce((s, v) => s + v * v, 0)) || 1;
    return out.map(v => v / norm);
  });
}

// ── Public API ───────────────────────────────────────────────────────────────

/**
 * Получить embedding(и) для одного или массива текстов.
 * Возвращает массив векторов (Float[]).
 */
async function embed(textOrTexts) {
  const texts = Array.isArray(textOrTexts) ? textOrTexts : [textOrTexts];
  const trimmed = texts.map(t => (t || '').slice(0, 8000)); // OpenAI limit

  if (PROVIDER === 'openai') {
    try {
      return await embedOpenAI(trimmed);
    } catch (err) {
      console.error('[embeddings] OpenAI failed, fallback to hash:', err.message);
      return embedHash(trimmed);
    }
  }
  return embedHash(trimmed);
}

/**
 * Преобразовать массив чисел в строку pgvector '[1,2,3]'
 */
function toPgVector(arr) {
  return '[' + arr.join(',') + ']';
}

module.exports = { embed, toPgVector, DIM, PROVIDER, MODEL };
