// ── База знаний Консультанта (RAG) ───────────────────────────────────────────
// Постгрес + pgvector. Таблицы: источники, чанки, лог ответов, профиль уровня.
// Запускается из index.js при старте сервера.

const db = require('../db');

const EMBEDDING_DIM = parseInt(process.env.EMBEDDING_DIM || '1536', 10);

async function migrateKnowledge() {
  // Включаем pgvector. Если расширения нет — падаем с понятной ошибкой.
  await db.query('CREATE EXTENSION IF NOT EXISTS vector');

  await db.query(`
    -- Источники документов (один документ = одна запись)
    CREATE TABLE IF NOT EXISTS knowledge_source (
      id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
      url             TEXT        UNIQUE NOT NULL,
      title           TEXT        NOT NULL,
      source_type     TEXT        NOT NULL,
        -- 'law' | 'kgd_letter' | 'mfin_order' | 'gov_decree'
        -- | 'blog' | 'forum' | 'telegram' | 'youtube'
        -- | 'esep_platform' | 'esep_glossary' | 'internal_faq'
      trust_weight    NUMERIC(3,2) NOT NULL DEFAULT 0.5,
      published_at    DATE,
      fetched_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      raw_content     TEXT,
      content_hash    TEXT        NOT NULL,
      language        TEXT        NOT NULL DEFAULT 'ru',
      is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
      metadata        JSONB       NOT NULL DEFAULT '{}'::jsonb
        -- произвольные поля: {law_code, article, paragraph, doc_number, ...}
    );

    CREATE INDEX IF NOT EXISTS idx_ks_type      ON knowledge_source(source_type);
    CREATE INDEX IF NOT EXISTS idx_ks_active    ON knowledge_source(is_active) WHERE is_active = TRUE;
    CREATE INDEX IF NOT EXISTS idx_ks_published ON knowledge_source(published_at DESC);

    -- Чанки документов
    CREATE TABLE IF NOT EXISTS knowledge_chunk (
      id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
      source_id       UUID        NOT NULL REFERENCES knowledge_source(id) ON DELETE CASCADE,
      chunk_index     INT         NOT NULL,
      text            TEXT        NOT NULL,
      embedding       vector(${EMBEDDING_DIM}),
      bm25_tsv        tsvector,
      anchor          TEXT,
        -- ссылка-якорь типа '#st-688-p-2' или '/dashboard?tab=910'
      audience_hint   TEXT        NOT NULL DEFAULT 'all',
        -- 'ip_solo' | 'ip_emp' | 'too' | 'accountant' | 'all'
      complexity      TEXT        NOT NULL DEFAULT 'medium',
        -- 'simple' | 'medium' | 'expert'
      created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (source_id, chunk_index)
    );

    -- HNSW индекс для cosine similarity
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename  = 'knowledge_chunk'
          AND indexname  = 'idx_kc_embedding'
      ) THEN
        EXECUTE 'CREATE INDEX idx_kc_embedding
                 ON knowledge_chunk
                 USING hnsw (embedding vector_cosine_ops)';
      END IF;
    END $$;

    CREATE INDEX IF NOT EXISTS idx_kc_bm25       ON knowledge_chunk USING gin(bm25_tsv);
    CREATE INDEX IF NOT EXISTS idx_kc_source     ON knowledge_chunk(source_id);
    CREATE INDEX IF NOT EXISTS idx_kc_audience   ON knowledge_chunk(audience_hint);
    CREATE INDEX IF NOT EXISTS idx_kc_complexity ON knowledge_chunk(complexity);

    -- Лог ответов Консультанта (для качества и обучения)
    CREATE TABLE IF NOT EXISTS consultant_answer_log (
      id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id         UUID        REFERENCES users(id) ON DELETE SET NULL,
      user_segment    TEXT        NOT NULL DEFAULT 'unknown',
        -- 'ip_solo' | 'ip_emp' | 'too' | 'accountant' | 'unknown'
      detected_level  TEXT        NOT NULL DEFAULT 'newbie',
        -- 'newbie' | 'intermediate' | 'expert'
      screen_context  JSONB       DEFAULT '{}'::jsonb,
      question        TEXT        NOT NULL,
      answer          TEXT        NOT NULL,
      citations       JSONB       NOT NULL DEFAULT '[]'::jsonb,
      retrieval_score NUMERIC(5,4),
      llm_model       TEXT        NOT NULL,
      latency_ms      INT,
      feedback        TEXT,
      feedback_note   TEXT,
      created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS idx_cal_user      ON consultant_answer_log(user_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_cal_feedback  ON consultant_answer_log(feedback);

    -- Профиль уровня пользователя (для адаптивного стиля)
    CREATE TABLE IF NOT EXISTS user_consultant_profile (
      user_id              UUID        PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      detected_level       TEXT        NOT NULL DEFAULT 'newbie',
      uses_terms           BOOLEAN     NOT NULL DEFAULT FALSE,
      asks_struggle        BOOLEAN     NOT NULL DEFAULT FALSE,
      message_count        INT         NOT NULL DEFAULT 0,
      last_message_at      TIMESTAMPTZ,
      preferred_tone       TEXT        DEFAULT 'auto',
        -- 'simple' | 'professional' | 'auto'
      onboarding_hints     JSONB       NOT NULL DEFAULT '[]'::jsonb,
        -- какие подсказки про платформу уже видел
      updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);

  console.log('✅  Knowledge DB migrated (pgvector ready, dim=' + EMBEDDING_DIM + ')');
}

module.exports = { migrateKnowledge, EMBEDDING_DIM };
