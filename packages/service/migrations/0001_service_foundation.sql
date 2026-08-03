CREATE TABLE accounts (
  id uuid PRIMARY KEY,
  email text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT accounts_email_normalized CHECK (email = lower(email)),
  CONSTRAINT accounts_email_unique UNIQUE (email)
);

CREATE TABLE private_assets (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  object_key text NOT NULL UNIQUE,
  purpose text NOT NULL CHECK (purpose IN (
    'source-photo',
    'generation-reference',
    'shelf-image-keyed',
    'shelf-image-transparent',
    'fixture'
  )),
  content_type text NOT NULL,
  declared_byte_size bigint NOT NULL CHECK (declared_byte_size > 0),
  stored_byte_size bigint,
  pixel_width integer CHECK (pixel_width > 0),
  pixel_height integer CHECK (pixel_height > 0),
  state text NOT NULL DEFAULT 'pending-upload' CHECK (state IN ('pending-upload', 'available')),
  created_at timestamptz NOT NULL DEFAULT now(),
  available_at timestamptz,
  CONSTRAINT private_assets_account_id_id_unique UNIQUE (account_id, id),
  CONSTRAINT private_assets_available_shape CHECK (
    (state = 'pending-upload' AND available_at IS NULL AND stored_byte_size IS NULL)
    OR
    (state = 'available' AND available_at IS NOT NULL AND stored_byte_size IS NOT NULL)
  )
);

CREATE INDEX private_assets_account_created_idx
  ON private_assets (account_id, created_at DESC);

CREATE TABLE remote_image_jobs (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('detect-source-photo', 'generate-shelf-image')),
  payload jsonb NOT NULL,
  state text NOT NULL DEFAULT 'queued' CHECK (state IN ('queued', 'processing', 'succeeded', 'failed')),
  idempotency_key text NOT NULL,
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  max_attempts integer NOT NULL DEFAULT 2 CHECK (max_attempts BETWEEN 1 AND 2),
  available_at timestamptz NOT NULL DEFAULT now(),
  lease_owner text,
  lease_expires_at timestamptz,
  last_error_category text,
  last_error_message text,
  result jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  CONSTRAINT remote_image_jobs_idempotency_unique UNIQUE (account_id, idempotency_key),
  CONSTRAINT remote_image_jobs_lease_shape CHECK (
    (state = 'processing' AND lease_owner IS NOT NULL AND lease_expires_at IS NOT NULL)
    OR
    (state <> 'processing' AND lease_owner IS NULL AND lease_expires_at IS NULL)
  )
);

CREATE INDEX remote_image_jobs_claim_idx
  ON remote_image_jobs (available_at, created_at)
  WHERE state = 'queued';

CREATE INDEX remote_image_jobs_active_account_idx
  ON remote_image_jobs (account_id, lease_expires_at)
  WHERE state = 'processing';

CREATE TABLE fixture_scenarios (
  account_id uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  scenario text NOT NULL,
  reset_at timestamptz NOT NULL DEFAULT now()
);
