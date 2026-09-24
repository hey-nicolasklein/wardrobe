ALTER TABLE detection_attempts
  ADD COLUMN input_tokens integer CHECK (input_tokens >= 0),
  ADD COLUMN cached_input_tokens integer CHECK (cached_input_tokens >= 0),
  ADD COLUMN cache_write_input_tokens integer CHECK (cache_write_input_tokens >= 0),
  ADD COLUMN output_tokens integer CHECK (output_tokens >= 0),
  ADD COLUMN reasoning_tokens integer CHECK (reasoning_tokens >= 0),
  ADD COLUMN service_tier text,
  ADD COLUMN pricing_effective_date date,
  ADD COLUMN captured_rates jsonb,
  ADD COLUMN provider_usage jsonb,
  ADD COLUMN input_cost_microunits bigint CHECK (input_cost_microunits >= 0),
  ADD COLUMN cached_input_cost_microunits bigint CHECK (cached_input_cost_microunits >= 0),
  ADD COLUMN cache_write_input_cost_microunits bigint CHECK (cache_write_input_cost_microunits >= 0),
  ADD COLUMN output_cost_microunits bigint CHECK (output_cost_microunits >= 0),
  ADD COLUMN cost_microunits bigint CHECK (cost_microunits >= 0);

CREATE FUNCTION keep_detection_usage_ledger_once_written() RETURNS trigger AS $$
BEGIN
  IF OLD.provider_request_id IS NOT NULL AND (
    NEW.provider_request_id IS DISTINCT FROM OLD.provider_request_id
    OR NEW.input_tokens IS DISTINCT FROM OLD.input_tokens
    OR NEW.cached_input_tokens IS DISTINCT FROM OLD.cached_input_tokens
    OR NEW.cache_write_input_tokens IS DISTINCT FROM OLD.cache_write_input_tokens
    OR NEW.output_tokens IS DISTINCT FROM OLD.output_tokens
    OR NEW.reasoning_tokens IS DISTINCT FROM OLD.reasoning_tokens
    OR NEW.service_tier IS DISTINCT FROM OLD.service_tier
    OR NEW.pricing_effective_date IS DISTINCT FROM OLD.pricing_effective_date
    OR NEW.captured_rates IS DISTINCT FROM OLD.captured_rates
    OR NEW.provider_usage IS DISTINCT FROM OLD.provider_usage
    OR NEW.input_cost_microunits IS DISTINCT FROM OLD.input_cost_microunits
    OR NEW.cached_input_cost_microunits IS DISTINCT FROM OLD.cached_input_cost_microunits
    OR NEW.cache_write_input_cost_microunits IS DISTINCT FROM OLD.cache_write_input_cost_microunits
    OR NEW.output_cost_microunits IS DISTINCT FROM OLD.output_cost_microunits
    OR NEW.cost_microunits IS DISTINCT FROM OLD.cost_microunits
  ) THEN
    RAISE EXCEPTION 'detection usage ledger is immutable';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER detection_usage_ledger_immutable
  BEFORE UPDATE ON detection_attempts
  FOR EACH ROW EXECUTE FUNCTION keep_detection_usage_ledger_once_written();
