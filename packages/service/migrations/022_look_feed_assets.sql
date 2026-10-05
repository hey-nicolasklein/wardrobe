-- A smaller WebP copy of each finished look for the feed. The original stays
-- for sharing, detail views and quality upgrades.
ALTER TABLE looks ADD COLUMN feed_asset_id uuid REFERENCES private_assets(id) ON DELETE SET NULL;
