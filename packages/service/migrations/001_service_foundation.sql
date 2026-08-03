CREATE TABLE accounts (
  id uuid PRIMARY KEY,
  email text NOT NULL,
  password_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  disabled_at timestamptz,
  CONSTRAINT accounts_email_normalized CHECK (email = lower(trim(email)))
);

CREATE UNIQUE INDEX accounts_email_unique ON accounts (lower(email));

CREATE TABLE sessions (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX sessions_account_id_idx ON sessions (account_id);
CREATE INDEX sessions_expires_at_idx ON sessions (expires_at);

CREATE TABLE private_assets (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  purpose text NOT NULL CHECK (purpose IN (
    'source-photo',
    'generation-reference',
    'shelf-image-keyed',
    'shelf-image-transparent',
    'fixture'
  )),
  object_key text NOT NULL UNIQUE,
  content_type text NOT NULL,
  byte_size bigint NOT NULL CHECK (byte_size >= 0),
  pixel_width integer CHECK (pixel_width > 0),
  pixel_height integer CHECK (pixel_height > 0),
  state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending', 'ready', 'deleted')),
  created_at timestamptz NOT NULL DEFAULT now(),
  ready_at timestamptz,
  deleted_at timestamptz,
  CONSTRAINT private_assets_dimensions_together CHECK (
    (pixel_width IS NULL AND pixel_height IS NULL) OR
    (pixel_width IS NOT NULL AND pixel_height IS NOT NULL)
  )
);

CREATE INDEX private_assets_account_id_idx ON private_assets (account_id);

CREATE TABLE source_photos (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  asset_id uuid NOT NULL REFERENCES private_assets(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, asset_id)
);

CREATE INDEX source_photos_account_id_idx ON source_photos (account_id);

CREATE TABLE wardrobe_items (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  source_photo_id uuid NOT NULL REFERENCES source_photos(id) ON DELETE RESTRICT,
  state text NOT NULL CHECK (state IN ('wanting', 'owning', 'archived')),
  status text NOT NULL CHECK (status IN (
    'detecting',
    'reviewing-metadata',
    'queued',
    'generating',
    'needs-review',
    'ready',
    'failed'
  )),
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  category text NOT NULL CHECK (category IN (
    'top', 'jacket', 'pants', 'skirt', 'dress', 'shoes', 'bag', 'hat', 'scarf'
  )),
  colors text[] NOT NULL CHECK (cardinality(colors) BETWEEN 1 AND 6),
  notes text CHECK (char_length(notes) <= 2000),
  current_shelf_image_version_id uuid,
  record_version integer NOT NULL DEFAULT 0 CHECK (record_version >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE INDEX wardrobe_items_account_state_idx
  ON wardrobe_items (account_id, state, updated_at DESC)
  WHERE deleted_at IS NULL;
CREATE INDEX wardrobe_items_source_photo_id_idx ON wardrobe_items (source_photo_id);

CREATE TABLE detection_proposals (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  source_photo_id uuid NOT NULL REFERENCES source_photos(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
  category text NOT NULL CHECK (category IN (
    'top', 'jacket', 'pants', 'skirt', 'dress', 'shoes', 'bag', 'hat', 'scarf', 'unsupported'
  )),
  colors text[] NOT NULL CHECK (cardinality(colors) BETWEEN 1 AND 6),
  bounding_box jsonb NOT NULL,
  provider_payload jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX detection_proposals_source_photo_id_idx
  ON detection_proposals (account_id, source_photo_id);

CREATE TABLE generation_attempts (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  wardrobe_item_id uuid NOT NULL REFERENCES wardrobe_items(id) ON DELETE CASCADE,
  source_photo_id uuid NOT NULL REFERENCES source_photos(id) ON DELETE RESTRICT,
  detection_proposal_id uuid REFERENCES detection_proposals(id) ON DELETE SET NULL,
  reference_asset_id uuid REFERENCES private_assets(id) ON DELETE RESTRICT,
  keyed_asset_id uuid REFERENCES private_assets(id) ON DELETE RESTRICT,
  transparent_asset_id uuid REFERENCES private_assets(id) ON DELETE RESTRICT,
  state text NOT NULL CHECK (state IN ('queued', 'processing', 'needs-review', 'kept', 'rejected', 'failed')),
  reviewed_metadata jsonb NOT NULL,
  model text NOT NULL,
  quality text NOT NULL CHECK (quality IN ('low', 'medium', 'high')),
  output_size text NOT NULL CHECK (output_size = '816x816'),
  prompt_version text NOT NULL,
  resolved_chroma_key text,
  provider_request_id text,
  input_tokens integer CHECK (input_tokens >= 0),
  output_tokens integer CHECK (output_tokens >= 0),
  captured_rates jsonb,
  cost_microunits bigint CHECK (cost_microunits >= 0),
  failure_category text,
  failure_detail text,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  finished_at timestamptz
);

CREATE INDEX generation_attempts_item_idx
  ON generation_attempts (account_id, wardrobe_item_id, created_at DESC);

CREATE TABLE shelf_image_versions (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  wardrobe_item_id uuid NOT NULL REFERENCES wardrobe_items(id) ON DELETE CASCADE,
  generation_attempt_id uuid NOT NULL UNIQUE REFERENCES generation_attempts(id) ON DELETE RESTRICT,
  keyed_asset_id uuid NOT NULL REFERENCES private_assets(id) ON DELETE RESTRICT,
  transparent_asset_id uuid NOT NULL REFERENCES private_assets(id) ON DELETE RESTRICT,
  quality text NOT NULL CHECK (quality IN ('low', 'medium', 'high')),
  output_size text NOT NULL CHECK (output_size = '816x816'),
  prompt_version text NOT NULL,
  kept_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX shelf_image_versions_item_idx
  ON shelf_image_versions (account_id, wardrobe_item_id, kept_at DESC);

ALTER TABLE wardrobe_items
  ADD CONSTRAINT wardrobe_items_current_version_fk
  FOREIGN KEY (current_shelf_image_version_id)
  REFERENCES shelf_image_versions(id) ON DELETE SET NULL;

CREATE TABLE remote_image_jobs (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  wardrobe_item_id uuid REFERENCES wardrobe_items(id) ON DELETE CASCADE,
  generation_attempt_id uuid REFERENCES generation_attempts(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('detect-source-photo', 'generate-shelf-image')),
  payload jsonb NOT NULL,
  state text NOT NULL DEFAULT 'queued' CHECK (state IN ('queued', 'leased', 'succeeded', 'failed', 'cancelled')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  max_attempts integer NOT NULL DEFAULT 2 CHECK (max_attempts BETWEEN 1 AND 10),
  available_at timestamptz NOT NULL DEFAULT now(),
  lease_owner text,
  lease_expires_at timestamptz,
  last_error_category text,
  last_error_detail text,
  idempotency_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  UNIQUE (account_id, idempotency_key),
  CONSTRAINT remote_image_jobs_lease_consistent CHECK (
    (state = 'leased' AND lease_owner IS NOT NULL AND lease_expires_at IS NOT NULL) OR
    (state <> 'leased' AND lease_owner IS NULL AND lease_expires_at IS NULL)
  )
);

CREATE INDEX remote_image_jobs_claim_idx
  ON remote_image_jobs (available_at, created_at)
  WHERE state = 'queued';
CREATE INDEX remote_image_jobs_lease_idx
  ON remote_image_jobs (lease_expires_at)
  WHERE state = 'leased';
CREATE INDEX remote_image_jobs_account_active_idx
  ON remote_image_jobs (account_id, state);

CREATE TABLE idempotency_commands (
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  key text NOT NULL,
  command_kind text NOT NULL,
  request_hash text NOT NULL,
  response_status integer,
  response_body jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  PRIMARY KEY (account_id, key)
);

CREATE INDEX idempotency_commands_expires_at_idx ON idempotency_commands (expires_at);

CREATE FUNCTION enforce_account_ownership() RETURNS trigger AS $$
DECLARE
  related_account_id uuid;
BEGIN
  IF TG_ARGV[0] = 'asset' THEN
    SELECT account_id INTO related_account_id FROM private_assets WHERE id = NEW.asset_id;
  ELSIF TG_ARGV[0] = 'source' THEN
    SELECT account_id INTO related_account_id FROM source_photos WHERE id = NEW.source_photo_id;
  ELSIF TG_ARGV[0] = 'item' THEN
    SELECT account_id INTO related_account_id FROM wardrobe_items WHERE id = NEW.wardrobe_item_id;
  END IF;

  IF related_account_id IS DISTINCT FROM NEW.account_id THEN
    RAISE EXCEPTION 'cross-account relationship rejected';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER source_photos_asset_owner
  BEFORE INSERT OR UPDATE ON source_photos
  FOR EACH ROW EXECUTE FUNCTION enforce_account_ownership('asset');
CREATE TRIGGER wardrobe_items_source_owner
  BEFORE INSERT OR UPDATE ON wardrobe_items
  FOR EACH ROW EXECUTE FUNCTION enforce_account_ownership('source');
CREATE TRIGGER detection_proposals_source_owner
  BEFORE INSERT OR UPDATE ON detection_proposals
  FOR EACH ROW EXECUTE FUNCTION enforce_account_ownership('source');
CREATE TRIGGER generation_attempts_item_owner
  BEFORE INSERT OR UPDATE ON generation_attempts
  FOR EACH ROW EXECUTE FUNCTION enforce_account_ownership('item');
CREATE TRIGGER shelf_image_versions_item_owner
  BEFORE INSERT OR UPDATE ON shelf_image_versions
  FOR EACH ROW EXECUTE FUNCTION enforce_account_ownership('item');
CREATE TRIGGER remote_image_jobs_item_owner
  BEFORE INSERT OR UPDATE ON remote_image_jobs
  FOR EACH ROW WHEN (NEW.wardrobe_item_id IS NOT NULL)
  EXECUTE FUNCTION enforce_account_ownership('item');
