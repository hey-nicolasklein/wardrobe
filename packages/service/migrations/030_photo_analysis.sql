-- What a detection learned about the photo as a whole: whether it shows the
-- user or someone else, and a rough box around the outfit for clean crops.
-- Null for attempts made before this, and for wardrobe intake that ignores it.
ALTER TABLE detection_attempts
  ADD COLUMN photo_source text CHECK (photo_source IN ('personal', 'reference')),
  ADD COLUMN outfit_box jsonb;
