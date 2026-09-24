-- Glasses, jewelry, watches and belts share one general accessory category.
ALTER TABLE wardrobe_items DROP CONSTRAINT wardrobe_items_category_check;
ALTER TABLE wardrobe_items ADD CONSTRAINT wardrobe_items_category_check CHECK (category IN (
  'top', 'jacket', 'pants', 'skirt', 'dress', 'shoes', 'bag', 'hat', 'scarf', 'accessory'
));

ALTER TABLE detection_proposals DROP CONSTRAINT detection_proposals_category_check;
ALTER TABLE detection_proposals ADD CONSTRAINT detection_proposals_category_check CHECK (category IN (
  'top', 'jacket', 'pants', 'skirt', 'dress', 'shoes', 'bag', 'hat', 'scarf', 'accessory', 'unsupported'
));
