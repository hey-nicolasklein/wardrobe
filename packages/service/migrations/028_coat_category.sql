-- Coats leave the jacket category so long outerwear keeps its length in looks.
ALTER TABLE wardrobe_items DROP CONSTRAINT wardrobe_items_category_check;
ALTER TABLE wardrobe_items ADD CONSTRAINT wardrobe_items_category_check CHECK (category IN (
  'top', 'jacket', 'coat', 'pants', 'skirt', 'dress', 'shoes', 'bag', 'hat', 'scarf', 'accessory'
));

ALTER TABLE detection_proposals DROP CONSTRAINT detection_proposals_category_check;
ALTER TABLE detection_proposals ADD CONSTRAINT detection_proposals_category_check CHECK (category IN (
  'top', 'jacket', 'coat', 'pants', 'skirt', 'dress', 'shoes', 'bag', 'hat', 'scarf', 'accessory', 'unsupported'
));
