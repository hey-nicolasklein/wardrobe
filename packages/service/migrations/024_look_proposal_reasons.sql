-- Why a proposal was suggested, see LookReason in packages/contracts.
ALTER TABLE looks ADD COLUMN proposal_reasons jsonb;
