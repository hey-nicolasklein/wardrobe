-- A try-on look edits one of the user's own photos instead of generating a new
-- scene. Looks sharing a base photo stay comparable with each other.
ALTER TABLE looks ADD COLUMN base_asset_id uuid REFERENCES private_assets(id) ON DELETE RESTRICT;
