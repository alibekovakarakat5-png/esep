// Additive migration. Do not infer a company/payment month for legacy records.
const SAFETY_SCHEMA = `
CREATE TABLE IF NOT EXISTS accounting_fee_payments (
 client_id TEXT NOT NULL REFERENCES accounting_clients(id) ON DELETE CASCADE,
 month TEXT NOT NULL CHECK (month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
 amount NUMERIC(18,2) NOT NULL CHECK (amount >= 0),
 received BOOLEAN NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
 PRIMARY KEY(client_id,month)
);
ALTER TABLE esf_recon_session ADD COLUMN IF NOT EXISTS accounting_client_id TEXT REFERENCES accounting_clients(id);
ALTER TABLE esf_recon_session ADD COLUMN IF NOT EXISTS client_bin TEXT;
CREATE INDEX IF NOT EXISTS esf_recon_org_idx ON esf_recon_session(user_id,accounting_client_id,created_at);
CREATE TABLE IF NOT EXISTS esf_recon_registry_row (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 session_id UUID NOT NULL REFERENCES esf_recon_session(id) ON DELETE CASCADE,
 registration_no TEXT, invoice_no TEXT NOT NULL, invoice_date DATE NOT NULL,
 status TEXT NOT NULL, seller_iin TEXT, seller_name TEXT, buyer_iin TEXT NOT NULL,
 amount_net NUMERIC(18,2), amount_vat NUMERIC(18,2), amount_total NUMERIC(18,2),raw_row JSONB,
 UNIQUE(session_id,registration_no)
);
CREATE TABLE IF NOT EXISTS esf_recon_result (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 session_id UUID NOT NULL REFERENCES esf_recon_session(id) ON DELETE CASCADE,
 esf_id UUID REFERENCES esf_recon_registry_row(id) ON DELETE CASCADE,
 notice_row_id UUID REFERENCES esf_notice_row(id) ON DELETE CASCADE,
 match_type TEXT NOT NULL,confidence NUMERIC(3,2) NOT NULL,diff JSONB NOT NULL
);
CREATE INDEX IF NOT EXISTS esf_recon_result_session_idx ON esf_recon_result(session_id);
CREATE UNIQUE INDEX IF NOT EXISTS accounting_client_owner_key ON accounting_clients(id,user_id);
CREATE UNIQUE INDEX IF NOT EXISTS esf_registry_session_key ON esf_recon_registry_row(id,session_id);
CREATE UNIQUE INDEX IF NOT EXISTS esf_notice_session_key ON esf_notice_row(id,session_id);
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='esf_session_company_owner_fk') THEN
  ALTER TABLE esf_recon_session ADD CONSTRAINT esf_session_company_owner_fk
   FOREIGN KEY(accounting_client_id,user_id) REFERENCES accounting_clients(id,user_id);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='esf_result_registry_scope_fk') THEN
  ALTER TABLE esf_recon_result ADD CONSTRAINT esf_result_registry_scope_fk
   FOREIGN KEY(esf_id,session_id) REFERENCES esf_recon_registry_row(id,session_id) ON DELETE CASCADE;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='esf_result_notice_scope_fk') THEN
  ALTER TABLE esf_recon_result ADD CONSTRAINT esf_result_notice_scope_fk
   FOREIGN KEY(notice_row_id,session_id) REFERENCES esf_notice_row(id,session_id) ON DELETE CASCADE;
 END IF;
END $$;
`;
module.exports = { SAFETY_SCHEMA };
