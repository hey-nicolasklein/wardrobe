-- A broad box around the person or main subject of a detected photo, so
-- clients can frame the photo on it. Null when the photo shows no clear subject.
ALTER TABLE detection_attempts ADD COLUMN subject_box jsonb;
