-- Third-party sign-in. An account can hold several identities (Apple, Google,
-- dev), so password_hash becomes optional.
ALTER TABLE accounts ALTER COLUMN password_hash DROP NOT NULL;

-- Metered accounts pay for generation jobs with credits. Existing accounts
-- (the private deployment) stay unmetered.
ALTER TABLE accounts ADD COLUMN metered boolean NOT NULL DEFAULT false;

CREATE TABLE account_identities (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  provider text NOT NULL CHECK (provider IN ('apple', 'google', 'dev')),
  subject text NOT NULL,
  email text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, subject)
);

CREATE INDEX account_identities_account_id_idx ON account_identities (account_id);

-- Append-only credit ledger. The balance is SUM(delta); rows are never updated.
CREATE TABLE credit_ledger (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  delta integer NOT NULL CHECK (delta <> 0),
  reason text NOT NULL CHECK (reason IN ('signup', 'grant', 'job', 'refund')),
  job_id uuid,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX credit_ledger_account_id_idx ON credit_ledger (account_id);
-- One charge and at most one refund per job.
CREATE UNIQUE INDEX credit_ledger_job_reason_unique ON credit_ledger (job_id, reason)
  WHERE job_id IS NOT NULL;
