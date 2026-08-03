ALTER TABLE generation_attempts
  ADD COLUMN text_input_cost_microunits bigint CHECK (text_input_cost_microunits >= 0),
  ADD COLUMN image_input_cost_microunits bigint CHECK (image_input_cost_microunits >= 0),
  ADD COLUMN image_output_cost_microunits bigint CHECK (image_output_cost_microunits >= 0);

CREATE FUNCTION keep_generation_cost_components_once_written() RETURNS trigger AS $$
BEGIN
  IF OLD.provider_request_id IS NOT NULL AND (
    NEW.text_input_cost_microunits IS DISTINCT FROM OLD.text_input_cost_microunits
    OR NEW.image_input_cost_microunits IS DISTINCT FROM OLD.image_input_cost_microunits
    OR NEW.image_output_cost_microunits IS DISTINCT FROM OLD.image_output_cost_microunits
  ) THEN
    RAISE EXCEPTION 'generation cost components are immutable';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER generation_cost_components_immutable
  BEFORE UPDATE ON generation_attempts
  FOR EACH ROW EXECUTE FUNCTION keep_generation_cost_components_once_written();
