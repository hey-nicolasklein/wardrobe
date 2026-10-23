-- A look is a combination of pieces first. AI images are optional on top: a
-- try-on on the user's photo, or an inspiration. Only inspirations need a
-- character sheet.
ALTER TABLE looks
  ADD COLUMN kind text NOT NULL DEFAULT 'inspiration'
    CHECK (kind IN ('combination', 'inspiration', 'try-on')),
  -- The occasion a combination was filed under. Generated looks keep theirs in the job payload.
  ADD COLUMN occasion text CHECK (occasion IN ('night-out', 'party', 'business', 'casual')),
  ALTER COLUMN character_sheet_id DROP NOT NULL;

UPDATE looks SET kind = 'try-on' WHERE base_asset_id IS NOT NULL;

CREATE OR REPLACE FUNCTION enforce_look_owners() RETURNS trigger AS $$
BEGIN
  IF (NEW.character_sheet_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM character_sheets WHERE id = NEW.character_sheet_id AND account_id = NEW.account_id))
    OR (NEW.parent_look_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM looks WHERE id = NEW.parent_look_id AND account_id = NEW.account_id))
    OR (NEW.asset_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM private_assets WHERE id = NEW.asset_id AND account_id = NEW.account_id))
  THEN RAISE EXCEPTION 'cross-account relationship rejected'; END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
