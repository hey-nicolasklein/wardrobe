ALTER TABLE generation_attempts
  ADD COLUMN parent_shelf_image_version_id uuid
    REFERENCES shelf_image_versions(id) ON DELETE SET NULL,
  ADD COLUMN refinement_instruction text
    CHECK (refinement_instruction IS NULL OR char_length(refinement_instruction) BETWEEN 1 AND 1000);

CREATE OR REPLACE FUNCTION enforce_generation_attempt_ownership() RETURNS trigger AS $$
DECLARE
  item_account_id uuid;
  item_source_photo_id uuid;
  source_account_id uuid;
  proposal_account_id uuid;
  reference_account_id uuid;
  keyed_account_id uuid;
  transparent_account_id uuid;
  parent_account_id uuid;
  parent_item_id uuid;
BEGIN
  SELECT account_id, source_photo_id INTO item_account_id, item_source_photo_id FROM wardrobe_items WHERE id = NEW.wardrobe_item_id;
  SELECT account_id INTO source_account_id FROM source_photos WHERE id = NEW.source_photo_id;
  SELECT account_id INTO proposal_account_id FROM detection_proposals WHERE id = NEW.detection_proposal_id;
  SELECT account_id INTO reference_account_id FROM private_assets WHERE id = NEW.reference_asset_id;
  SELECT account_id INTO keyed_account_id FROM private_assets WHERE id = NEW.keyed_asset_id;
  SELECT account_id INTO transparent_account_id FROM private_assets WHERE id = NEW.transparent_asset_id;
  SELECT account_id, wardrobe_item_id INTO parent_account_id, parent_item_id FROM shelf_image_versions WHERE id = NEW.parent_shelf_image_version_id;

  IF item_account_id IS DISTINCT FROM NEW.account_id
    OR source_account_id IS DISTINCT FROM NEW.account_id
    OR item_source_photo_id IS DISTINCT FROM NEW.source_photo_id
    OR (NEW.detection_proposal_id IS NOT NULL AND proposal_account_id IS DISTINCT FROM NEW.account_id)
    OR (NEW.reference_asset_id IS NOT NULL AND reference_account_id IS DISTINCT FROM NEW.account_id)
    OR (NEW.keyed_asset_id IS NOT NULL AND keyed_account_id IS DISTINCT FROM NEW.account_id)
    OR (NEW.transparent_asset_id IS NOT NULL AND transparent_account_id IS DISTINCT FROM NEW.account_id)
    OR (NEW.parent_shelf_image_version_id IS NOT NULL AND parent_account_id IS DISTINCT FROM NEW.account_id)
    OR (NEW.parent_shelf_image_version_id IS NOT NULL AND parent_item_id IS DISTINCT FROM NEW.wardrobe_item_id)
  THEN
    RAISE EXCEPTION 'cross-account relationship rejected';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
