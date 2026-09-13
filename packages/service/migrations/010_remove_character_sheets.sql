ALTER TABLE character_sheets
  ADD COLUMN deleted_at timestamptz;

CREATE INDEX character_sheets_visible_idx
  ON character_sheets (account_id, created_at DESC)
  WHERE deleted_at IS NULL;
