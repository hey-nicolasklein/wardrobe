ALTER TABLE looks ADD COLUMN item_bounding_boxes jsonb NOT NULL DEFAULT '[]'::jsonb;
