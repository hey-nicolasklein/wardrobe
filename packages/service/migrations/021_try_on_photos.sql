-- Photos of the user for try-ons, kept so they can be picked again or deleted
-- from Settings. Earlier try-on looks bring their photos along.
CREATE TABLE try_on_photos (
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  asset_id uuid NOT NULL REFERENCES private_assets(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, asset_id)
);

INSERT INTO try_on_photos (account_id, asset_id, created_at)
SELECT l.account_id, l.base_asset_id, min(l.created_at)
FROM looks l
JOIN private_assets a ON a.id = l.base_asset_id AND a.deleted_at IS NULL
WHERE l.base_asset_id IS NOT NULL
GROUP BY l.account_id, l.base_asset_id;
