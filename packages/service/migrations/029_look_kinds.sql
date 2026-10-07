-- A look is a combination of pieces first. Images are optional: a real photo
-- the user wore it in, a try-on on their photo, or an AI inspiration. Only
-- inspirations need a character sheet.
ALTER TABLE looks
  ADD COLUMN kind text NOT NULL DEFAULT 'inspiration'
    CHECK (kind IN ('combination', 'photo', 'inspiration', 'try-on')),
  -- The photo a `photo` look was uploaded as. Its detected pieces are listed on the look.
  ADD COLUMN source_photo_id uuid REFERENCES source_photos(id) ON DELETE SET NULL,
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
    OR (NEW.source_photo_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM source_photos WHERE id = NEW.source_photo_id AND account_id = NEW.account_id))
  THEN RAISE EXCEPTION 'cross-account relationship rejected'; END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
