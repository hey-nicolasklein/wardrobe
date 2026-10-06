-- Filter tags read from a piece's shelf image by the worker shortly after intake.
-- Derived like item_warmth, which it replaces: the user never reviews them.
CREATE TABLE item_traits (
  wardrobe_item_id uuid PRIMARY KEY REFERENCES wardrobe_items(id) ON DELETE CASCADE,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  warmth text NOT NULL CHECK (warmth IN ('light', 'mid', 'warm')),
  kind text NOT NULL CHECK (char_length(kind) BETWEEN 1 AND 40),
  brand text CHECK (char_length(brand) BETWEEN 1 AND 40),
  formality text NOT NULL CHECK (formality IN ('casual', 'smart-casual', 'business', 'formal')),
  created_at timestamptz NOT NULL DEFAULT now()
);
