ALTER TABLE generation_attempts
  ADD COLUMN auto_keep boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION keep_generation_inputs_immutable() RETURNS trigger AS $$
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
    OR NEW.auto_keep IS DISTINCT FROM OLD.auto_keep
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'generation attempt inputs are immutable';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
