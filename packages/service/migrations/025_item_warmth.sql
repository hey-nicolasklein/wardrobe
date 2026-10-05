-- How warm a piece wears, tagged the first time it is planned into an outfit.
-- Kept apart from item metadata: it is derived, and the user never reviews it.
CREATE TABLE item_warmth (
  wardrobe_item_id uuid PRIMARY KEY REFERENCES wardrobe_items(id) ON DELETE CASCADE,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  warmth text NOT NULL CHECK (warmth IN ('light', 'mid', 'warm')),
  created_at timestamptz NOT NULL DEFAULT now()
);
