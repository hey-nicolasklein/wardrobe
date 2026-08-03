ALTER TABLE private_assets
  ADD COLUMN object_version_id text;

COMMENT ON COLUMN private_assets.object_version_id IS
  'Immutable S3 version validated before this asset became ready';
