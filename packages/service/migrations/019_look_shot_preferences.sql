-- Shot types a user asked to see less of. The look planner leaves them out.
CREATE TABLE look_shot_preferences (
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  shot text NOT NULL CHECK (char_length(shot) <= 40),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, shot)
);
