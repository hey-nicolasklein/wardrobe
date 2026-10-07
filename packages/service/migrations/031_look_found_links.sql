-- Which wardrobe piece a piece found on a photo look stands for. Set when the
-- user confirms a match or adds the piece, one per found piece and look, so a
-- confirmation can be taken back on its own and its box marks the piece on
-- the photo.
CREATE TABLE look_found_links (
  look_id uuid NOT NULL REFERENCES looks(id) ON DELETE CASCADE,
  detection_proposal_id uuid NOT NULL REFERENCES detection_proposals(id) ON DELETE CASCADE,
  wardrobe_item_id uuid NOT NULL REFERENCES wardrobe_items(id) ON DELETE CASCADE,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (look_id, detection_proposal_id)
);
CREATE INDEX look_found_links_item_idx ON look_found_links (wardrobe_item_id);

-- Pieces added from a look's own photo stand for the piece they came from.
INSERT INTO look_found_links (look_id, detection_proposal_id, wardrobe_item_id, account_id)
SELECT l.id, wi.detection_proposal_id, wi.id, l.account_id
FROM looks l
JOIN look_items li ON li.look_id = l.id
JOIN wardrobe_items wi ON wi.id = li.wardrobe_item_id AND wi.deleted_at IS NULL
JOIN detection_proposals dp ON dp.id = wi.detection_proposal_id AND dp.source_photo_id = l.source_photo_id
ON CONFLICT DO NOTHING;

-- Matches confirmed before links existed: a look piece pairs with the found
-- piece of its category when that pairing is unambiguous.
INSERT INTO look_found_links (look_id, detection_proposal_id, wardrobe_item_id, account_id)
SELECT pairs.look_id, pairs.detection_proposal_id, pairs.wardrobe_item_id, pairs.account_id
FROM (
  SELECT l.id AS look_id, dp.id AS detection_proposal_id, wi.id AS wardrobe_item_id, l.account_id,
    count(*) OVER (PARTITION BY l.id, wi.id) AS per_item,
    count(*) OVER (PARTITION BY l.id, dp.id) AS per_found
  FROM looks l
  JOIN look_items li ON li.look_id = l.id
  JOIN wardrobe_items wi ON wi.id = li.wardrobe_item_id AND wi.deleted_at IS NULL
  JOIN detection_proposals dp ON dp.source_photo_id = l.source_photo_id AND dp.category = wi.category
  WHERE l.source_photo_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM look_found_links f WHERE f.look_id = l.id AND f.wardrobe_item_id = wi.id)
    AND NOT EXISTS (SELECT 1 FROM look_found_links f WHERE f.look_id = l.id AND f.detection_proposal_id = dp.id)
) pairs
WHERE pairs.per_item = 1 AND pairs.per_found = 1
ON CONFLICT DO NOTHING;
