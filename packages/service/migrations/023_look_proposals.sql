-- Planned outfits the user picks from before anything is rendered. A proposal
-- stops at `proposed`; rendering clears the flag and it joins the feed.
ALTER TABLE looks
  ADD COLUMN proposal boolean NOT NULL DEFAULT false,
  DROP CONSTRAINT looks_state_check,
  ADD CONSTRAINT looks_state_check CHECK (state IN ('queued', 'planning', 'proposed', 'generating', 'ready', 'failed'));

ALTER TABLE remote_image_jobs
  DROP CONSTRAINT remote_image_jobs_kind_check,
  ADD CONSTRAINT remote_image_jobs_kind_check CHECK (kind IN (
    'detect-source-photo', 'generate-shelf-image', 'generate-character-sheet', 'generate-look', 'plan-look'
  ));
