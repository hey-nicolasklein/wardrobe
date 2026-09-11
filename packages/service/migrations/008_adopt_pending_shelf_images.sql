ALTER TABLE generation_attempts
  ALTER COLUMN auto_keep SET DEFAULT true;

WITH candidates AS MATERIALIZED (
  SELECT id, account_id, wardrobe_item_id, keyed_asset_id, transparent_asset_id,
    quality, output_size, prompt_version, finished_at
  FROM generation_attempts
  WHERE state = 'needs-review'
    AND keyed_asset_id IS NOT NULL
    AND transparent_asset_id IS NOT NULL
),
inserted AS (
  INSERT INTO shelf_image_versions (
    id, account_id, wardrobe_item_id, generation_attempt_id, keyed_asset_id,
    transparent_asset_id, quality, output_size, prompt_version, kept_at
  )
  SELECT gen_random_uuid(), account_id, wardrobe_item_id, id, keyed_asset_id,
    transparent_asset_id, quality, output_size, prompt_version, COALESCE(finished_at, now())
  FROM candidates
  ON CONFLICT (generation_attempt_id) DO NOTHING
  RETURNING id, wardrobe_item_id, generation_attempt_id, kept_at
),
marked AS (
  UPDATE generation_attempts attempts
  SET state = 'kept'
  FROM inserted
  WHERE attempts.id = inserted.generation_attempt_id
  RETURNING attempts.id
),
latest AS (
  SELECT DISTINCT ON (wardrobe_item_id) wardrobe_item_id, id
  FROM inserted
  ORDER BY wardrobe_item_id, kept_at DESC, id DESC
)
UPDATE wardrobe_items items
SET current_shelf_image_version_id = latest.id,
  status = 'ready',
  record_version = record_version + 1,
  updated_at = now()
FROM latest
WHERE items.id = latest.wardrobe_item_id;
