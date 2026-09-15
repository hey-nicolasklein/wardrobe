ALTER TABLE looks DROP CONSTRAINT looks_quality_check;
ALTER TABLE looks ADD CONSTRAINT looks_quality_check CHECK (quality IN ('low', 'medium', 'high'));
