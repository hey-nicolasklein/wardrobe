ALTER TABLE wardrobe_items
  ADD COLUMN detection_proposal_id uuid REFERENCES detection_proposals(id) ON DELETE RESTRICT;

CREATE INDEX wardrobe_items_detection_proposal_id_idx
  ON wardrobe_items (detection_proposal_id)
  WHERE detection_proposal_id IS NOT NULL;

CREATE FUNCTION enforce_wardrobe_item_provenance() RETURNS trigger AS $$
DECLARE
  source_account_id uuid;
  proposal_account_id uuid;
  proposal_source_photo_id uuid;
BEGIN
  SELECT account_id INTO source_account_id
    FROM source_photos WHERE id = NEW.source_photo_id;
  SELECT account_id, source_photo_id INTO proposal_account_id, proposal_source_photo_id
    FROM detection_proposals WHERE id = NEW.detection_proposal_id;

  IF source_account_id IS DISTINCT FROM NEW.account_id
    OR (NEW.detection_proposal_id IS NOT NULL AND (
      proposal_account_id IS DISTINCT FROM NEW.account_id
      OR proposal_source_photo_id IS DISTINCT FROM NEW.source_photo_id
    ))
  THEN
    RAISE EXCEPTION 'cross-account relationship rejected';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER wardrobe_items_source_owner ON wardrobe_items;
CREATE TRIGGER wardrobe_items_provenance_owner
  BEFORE INSERT OR UPDATE ON wardrobe_items
  FOR EACH ROW EXECUTE FUNCTION enforce_wardrobe_item_provenance();

CREATE FUNCTION keep_detection_proposals_immutable() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'detection proposals are immutable';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER detection_proposals_immutable
  BEFORE UPDATE ON detection_proposals
  FOR EACH ROW EXECUTE FUNCTION keep_detection_proposals_immutable();

CREATE FUNCTION keep_generation_inputs_immutable() RETURNS trigger AS $$
BEGIN
  IF NEW.account_id IS DISTINCT FROM OLD.account_id
    OR NEW.wardrobe_item_id IS DISTINCT FROM OLD.wardrobe_item_id
    OR NEW.source_photo_id IS DISTINCT FROM OLD.source_photo_id
    OR NEW.detection_proposal_id IS DISTINCT FROM OLD.detection_proposal_id
    OR NEW.reviewed_metadata IS DISTINCT FROM OLD.reviewed_metadata
    OR NEW.model IS DISTINCT FROM OLD.model
    OR NEW.quality IS DISTINCT FROM OLD.quality
    OR NEW.output_size IS DISTINCT FROM OLD.output_size
    OR NEW.prompt_version IS DISTINCT FROM OLD.prompt_version
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'generation attempt inputs are immutable';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER generation_attempt_inputs_immutable
  BEFORE UPDATE ON generation_attempts
  FOR EACH ROW EXECUTE FUNCTION keep_generation_inputs_immutable();

CREATE FUNCTION keep_shelf_image_versions_immutable() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'shelf image versions are immutable';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER shelf_image_versions_immutable
  BEFORE UPDATE ON shelf_image_versions
  FOR EACH ROW EXECUTE FUNCTION keep_shelf_image_versions_immutable();
