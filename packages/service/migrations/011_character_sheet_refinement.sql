-- A refinement is a new Character Sheet whose first reference is its parent's rendered sheet,
-- so identity iterates past the four references a single generation accepts.
ALTER TABLE character_sheets
  ADD COLUMN parent_character_sheet_id uuid REFERENCES character_sheets(id) ON DELETE SET NULL,
  ADD COLUMN refinement_instruction text CHECK (char_length(refinement_instruction) <= 1000),
  -- One-directional on purpose: pruning a parent nulls the link on its children, and the
  -- orphan keeps rendering as a refinement because the parent image stays in its references.
  ADD CONSTRAINT character_sheets_refinement_intent CHECK (
    parent_character_sheet_id IS NULL OR refinement_instruction IS NOT NULL
  );

CREATE INDEX character_sheets_parent_idx
  ON character_sheets (parent_character_sheet_id)
  WHERE parent_character_sheet_id IS NOT NULL;

CREATE OR REPLACE FUNCTION enforce_character_sheet_asset_owners() RETURNS trigger AS $$
DECLARE owned integer;
BEGIN
  SELECT count(*) INTO owned FROM private_assets
  WHERE account_id = NEW.account_id AND id = ANY(NEW.reference_asset_ids);
  IF owned <> cardinality(NEW.reference_asset_ids) OR
     (NEW.asset_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM private_assets WHERE id = NEW.asset_id AND account_id = NEW.account_id
     )) OR
     (NEW.parent_character_sheet_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM character_sheets WHERE id = NEW.parent_character_sheet_id AND account_id = NEW.account_id
     )) THEN RAISE EXCEPTION 'cross-account relationship rejected'; END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
