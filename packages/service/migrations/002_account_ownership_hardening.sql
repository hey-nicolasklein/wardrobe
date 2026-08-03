DROP TRIGGER generation_attempts_item_owner ON generation_attempts;
DROP TRIGGER shelf_image_versions_item_owner ON shelf_image_versions;
DROP TRIGGER remote_image_jobs_item_owner ON remote_image_jobs;

CREATE FUNCTION enforce_generation_attempt_ownership() RETURNS trigger AS $$
DECLARE
  item_account_id uuid;
  item_source_photo_id uuid;
  source_account_id uuid;
  proposal_account_id uuid;
  reference_account_id uuid;
  keyed_account_id uuid;
  transparent_account_id uuid;
BEGIN
  SELECT account_id, source_photo_id INTO item_account_id, item_source_photo_id
    FROM wardrobe_items WHERE id = NEW.wardrobe_item_id;
  SELECT account_id INTO source_account_id
    FROM source_photos WHERE id = NEW.source_photo_id;
  SELECT account_id INTO proposal_account_id
    FROM detection_proposals WHERE id = NEW.detection_proposal_id;
  SELECT account_id INTO reference_account_id
    FROM private_assets WHERE id = NEW.reference_asset_id;
  SELECT account_id INTO keyed_account_id
    FROM private_assets WHERE id = NEW.keyed_asset_id;
  SELECT account_id INTO transparent_account_id
    FROM private_assets WHERE id = NEW.transparent_asset_id;

  IF item_account_id IS DISTINCT FROM NEW.account_id
    OR source_account_id IS DISTINCT FROM NEW.account_id
    OR item_source_photo_id IS DISTINCT FROM NEW.source_photo_id
    OR (NEW.detection_proposal_id IS NOT NULL AND proposal_account_id IS DISTINCT FROM NEW.account_id)
    OR (NEW.reference_asset_id IS NOT NULL AND reference_account_id IS DISTINCT FROM NEW.account_id)
    OR (NEW.keyed_asset_id IS NOT NULL AND keyed_account_id IS DISTINCT FROM NEW.account_id)
    OR (NEW.transparent_asset_id IS NOT NULL AND transparent_account_id IS DISTINCT FROM NEW.account_id)
  THEN
    RAISE EXCEPTION 'cross-account relationship rejected';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION enforce_shelf_version_ownership() RETURNS trigger AS $$
DECLARE
  item_account_id uuid;
  attempt_account_id uuid;
  attempt_item_id uuid;
  keyed_account_id uuid;
  transparent_account_id uuid;
BEGIN
  SELECT account_id INTO item_account_id
    FROM wardrobe_items WHERE id = NEW.wardrobe_item_id;
  SELECT account_id, wardrobe_item_id INTO attempt_account_id, attempt_item_id
    FROM generation_attempts WHERE id = NEW.generation_attempt_id;
  SELECT account_id INTO keyed_account_id
    FROM private_assets WHERE id = NEW.keyed_asset_id;
  SELECT account_id INTO transparent_account_id
    FROM private_assets WHERE id = NEW.transparent_asset_id;

  IF item_account_id IS DISTINCT FROM NEW.account_id
    OR attempt_account_id IS DISTINCT FROM NEW.account_id
    OR attempt_item_id IS DISTINCT FROM NEW.wardrobe_item_id
    OR keyed_account_id IS DISTINCT FROM NEW.account_id
    OR transparent_account_id IS DISTINCT FROM NEW.account_id
  THEN
    RAISE EXCEPTION 'cross-account relationship rejected';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION enforce_current_version_ownership() RETURNS trigger AS $$
DECLARE
  version_account_id uuid;
  version_item_id uuid;
BEGIN
  IF NEW.current_shelf_image_version_id IS NULL THEN RETURN NEW; END IF;
  SELECT account_id, wardrobe_item_id INTO version_account_id, version_item_id
    FROM shelf_image_versions WHERE id = NEW.current_shelf_image_version_id;
  IF version_account_id IS DISTINCT FROM NEW.account_id
    OR version_item_id IS DISTINCT FROM NEW.id
  THEN
    RAISE EXCEPTION 'cross-account relationship rejected';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION enforce_job_ownership() RETURNS trigger AS $$
DECLARE
  item_account_id uuid;
  attempt_account_id uuid;
  attempt_item_id uuid;
BEGIN
  SELECT account_id INTO item_account_id
    FROM wardrobe_items WHERE id = NEW.wardrobe_item_id;
  SELECT account_id, wardrobe_item_id INTO attempt_account_id, attempt_item_id
    FROM generation_attempts WHERE id = NEW.generation_attempt_id;
  IF (NEW.wardrobe_item_id IS NOT NULL AND item_account_id IS DISTINCT FROM NEW.account_id)
    OR (NEW.generation_attempt_id IS NOT NULL AND attempt_account_id IS DISTINCT FROM NEW.account_id)
    OR (NEW.wardrobe_item_id IS NOT NULL AND NEW.generation_attempt_id IS NOT NULL
      AND attempt_item_id IS DISTINCT FROM NEW.wardrobe_item_id)
  THEN
    RAISE EXCEPTION 'cross-account relationship rejected';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER generation_attempts_owner
  BEFORE INSERT OR UPDATE ON generation_attempts
  FOR EACH ROW EXECUTE FUNCTION enforce_generation_attempt_ownership();
CREATE TRIGGER shelf_image_versions_owner
  BEFORE INSERT OR UPDATE ON shelf_image_versions
  FOR EACH ROW EXECUTE FUNCTION enforce_shelf_version_ownership();
CREATE TRIGGER wardrobe_items_current_version_owner
  BEFORE INSERT OR UPDATE ON wardrobe_items
  FOR EACH ROW EXECUTE FUNCTION enforce_current_version_ownership();
CREATE TRIGGER remote_image_jobs_owner
  BEFORE INSERT OR UPDATE ON remote_image_jobs
  FOR EACH ROW EXECUTE FUNCTION enforce_job_ownership();
