ALTER TABLE private_assets DROP CONSTRAINT private_assets_purpose_check;
ALTER TABLE private_assets ADD CONSTRAINT private_assets_purpose_check CHECK (purpose IN (
  'source-photo', 'generation-reference', 'shelf-image-keyed',
  'shelf-image-transparent', 'fixture', 'character-sheet', 'look'
));

CREATE TABLE character_sheets (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  reference_asset_ids uuid[] NOT NULL CHECK (cardinality(reference_asset_ids) BETWEEN 1 AND 4),
  note text CHECK (char_length(note) <= 1000),
  state text NOT NULL CHECK (state IN ('queued', 'processing', 'ready', 'failed')),
  asset_id uuid REFERENCES private_assets(id) ON DELETE RESTRICT,
  active boolean NOT NULL DEFAULT false,
  model text NOT NULL,
  quality text NOT NULL CHECK (quality = 'high'),
  output_size text NOT NULL CHECK (output_size = '864x1536'),
  prompt_version text NOT NULL,
  provider_request_id text,
  provider_usage jsonb,
  cost_microunits bigint CHECK (cost_microunits >= 0),
  failure_category text,
  failure_detail text,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  finished_at timestamptz
);
CREATE UNIQUE INDEX character_sheets_one_active ON character_sheets(account_id) WHERE active;
CREATE INDEX character_sheets_account_idx ON character_sheets(account_id, created_at DESC);

CREATE TABLE looks (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  character_sheet_id uuid NOT NULL REFERENCES character_sheets(id) ON DELETE RESTRICT,
  parent_look_id uuid REFERENCES looks(id) ON DELETE SET NULL,
  state text NOT NULL CHECK (state IN ('queued', 'planning', 'generating', 'ready', 'failed')),
  asset_id uuid REFERENCES private_assets(id) ON DELETE RESTRICT,
  exact_item_ids uuid[] NOT NULL DEFAULT '{}',
  category_constraints text[] NOT NULL DEFAULT '{}',
  planned_concept jsonb,
  model text NOT NULL,
  quality text NOT NULL CHECK (quality = 'medium'),
  output_size text NOT NULL CHECK (output_size = '1024x1280'),
  prompt_version text NOT NULL,
  provider_request_id text,
  provider_usage jsonb,
  cost_microunits bigint CHECK (cost_microunits >= 0),
  failure_category text,
  failure_detail text,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  finished_at timestamptz,
  deleted_at timestamptz
);
CREATE INDEX looks_feed_idx ON looks(account_id, created_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE look_items (
  look_id uuid NOT NULL REFERENCES looks(id) ON DELETE CASCADE,
  wardrobe_item_id uuid NOT NULL REFERENCES wardrobe_items(id) ON DELETE CASCADE,
  ordinal integer NOT NULL CHECK (ordinal >= 0),
  PRIMARY KEY (look_id, wardrobe_item_id),
  UNIQUE (look_id, ordinal)
);

ALTER TABLE remote_image_jobs
  DROP CONSTRAINT remote_image_jobs_kind_check,
  ADD CONSTRAINT remote_image_jobs_kind_check CHECK (kind IN (
    'detect-source-photo', 'generate-shelf-image', 'generate-character-sheet', 'generate-look'
  )),
  ADD COLUMN character_sheet_id uuid REFERENCES character_sheets(id) ON DELETE CASCADE,
  ADD COLUMN look_id uuid REFERENCES looks(id) ON DELETE CASCADE;

CREATE FUNCTION enforce_character_sheet_asset_owners() RETURNS trigger AS $$
DECLARE owned integer;
BEGIN
  SELECT count(*) INTO owned FROM private_assets
  WHERE account_id = NEW.account_id AND id = ANY(NEW.reference_asset_ids);
  IF owned <> cardinality(NEW.reference_asset_ids) OR
     (NEW.asset_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM private_assets WHERE id = NEW.asset_id AND account_id = NEW.account_id
     )) THEN RAISE EXCEPTION 'cross-account relationship rejected'; END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER character_sheet_asset_owners BEFORE INSERT OR UPDATE ON character_sheets
  FOR EACH ROW EXECUTE FUNCTION enforce_character_sheet_asset_owners();

CREATE FUNCTION enforce_look_owners() RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM character_sheets WHERE id = NEW.character_sheet_id AND account_id = NEW.account_id)
    OR (NEW.parent_look_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM looks WHERE id = NEW.parent_look_id AND account_id = NEW.account_id))
    OR (NEW.asset_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM private_assets WHERE id = NEW.asset_id AND account_id = NEW.account_id))
  THEN RAISE EXCEPTION 'cross-account relationship rejected'; END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER look_owners BEFORE INSERT OR UPDATE ON looks FOR EACH ROW EXECUTE FUNCTION enforce_look_owners();

CREATE FUNCTION enforce_look_item_owner() RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM looks l JOIN wardrobe_items i ON i.account_id = l.account_id
    WHERE l.id = NEW.look_id AND i.id = NEW.wardrobe_item_id AND i.deleted_at IS NULL
  ) THEN RAISE EXCEPTION 'cross-account relationship rejected'; END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER look_item_owner BEFORE INSERT OR UPDATE ON look_items
  FOR EACH ROW EXECUTE FUNCTION enforce_look_item_owner();
