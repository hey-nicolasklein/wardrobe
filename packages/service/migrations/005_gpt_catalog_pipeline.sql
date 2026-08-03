CREATE TABLE detection_attempts (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  source_photo_id uuid NOT NULL REFERENCES source_photos(id) ON DELETE CASCADE,
  state text NOT NULL CHECK (state IN ('queued', 'processing', 'succeeded', 'failed')),
  model text NOT NULL,
  provider_request_id text,
  failure_category text,
  failure_detail text,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  finished_at timestamptz
);

CREATE INDEX detection_attempts_source_idx
  ON detection_attempts (account_id, source_photo_id, created_at DESC);

ALTER TABLE generation_attempts
  ADD COLUMN text_input_tokens integer CHECK (text_input_tokens >= 0),
  ADD COLUMN image_input_tokens integer CHECK (image_input_tokens >= 0),
  ADD COLUMN service_tier text,
  ADD COLUMN pricing_effective_date date,
  ADD COLUMN provider_usage jsonb;

CREATE FUNCTION enforce_detection_attempt_owner() RETURNS trigger AS $$
DECLARE
  source_account_id uuid;
BEGIN
  SELECT account_id INTO source_account_id
    FROM source_photos WHERE id = NEW.source_photo_id;
  IF source_account_id IS DISTINCT FROM NEW.account_id THEN
    RAISE EXCEPTION 'cross-account relationship rejected';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER detection_attempts_source_owner
  BEFORE INSERT OR UPDATE ON detection_attempts
  FOR EACH ROW EXECUTE FUNCTION enforce_detection_attempt_owner();

CREATE FUNCTION keep_detection_attempt_inputs_immutable() RETURNS trigger AS $$
BEGIN
  IF NEW.account_id IS DISTINCT FROM OLD.account_id
    OR NEW.source_photo_id IS DISTINCT FROM OLD.source_photo_id
    OR NEW.model IS DISTINCT FROM OLD.model
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'detection attempt inputs are immutable';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER detection_attempt_inputs_immutable
  BEFORE UPDATE ON detection_attempts
  FOR EACH ROW EXECUTE FUNCTION keep_detection_attempt_inputs_immutable();

CREATE FUNCTION keep_generation_ledger_once_written() RETURNS trigger AS $$
BEGIN
  IF OLD.provider_request_id IS NOT NULL AND (
    NEW.provider_request_id IS DISTINCT FROM OLD.provider_request_id
    OR NEW.input_tokens IS DISTINCT FROM OLD.input_tokens
    OR NEW.text_input_tokens IS DISTINCT FROM OLD.text_input_tokens
    OR NEW.image_input_tokens IS DISTINCT FROM OLD.image_input_tokens
    OR NEW.output_tokens IS DISTINCT FROM OLD.output_tokens
    OR NEW.captured_rates IS DISTINCT FROM OLD.captured_rates
    OR NEW.cost_microunits IS DISTINCT FROM OLD.cost_microunits
    OR NEW.service_tier IS DISTINCT FROM OLD.service_tier
    OR NEW.pricing_effective_date IS DISTINCT FROM OLD.pricing_effective_date
    OR NEW.provider_usage IS DISTINCT FROM OLD.provider_usage
  ) THEN
    RAISE EXCEPTION 'generation usage ledger is immutable';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER generation_usage_ledger_immutable
  BEFORE UPDATE ON generation_attempts
  FOR EACH ROW EXECUTE FUNCTION keep_generation_ledger_once_written();
