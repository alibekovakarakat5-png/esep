// ── Налоговый профиль компании ───────────────────────────────────────────────
// Хранит: entity_type, regime, size_category, has_employees, is_vat_payer.
// Используется KBK-рекомендатором, AI-Консультантом, дашбордом.

const db = require('../db');

async function migrateTaxProfile() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS company_tax_profile (
      user_id         UUID         PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      entity_type     TEXT         NOT NULL DEFAULT 'ip',
        -- 'ip' | 'too' | 'individual'
      regime          TEXT,
        -- 'esp' | 'self_employed' | '910' | 'oyr' | 'retail' | NULL
      size_category   TEXT,
        -- 'small' | 'medium' | 'large' | NULL (для ИП обычно 'small' автоматом)
      has_employees   BOOLEAN      NOT NULL DEFAULT FALSE,
      is_vat_payer    BOOLEAN      NOT NULL DEFAULT FALSE,
      annual_revenue  NUMERIC(18,2),                    -- для авто-определения size_category
      employees_count INT          NOT NULL DEFAULT 0,
      updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
    );
  `);
  console.log('✅  Tax profile migrated');
}

module.exports = { migrateTaxProfile };
