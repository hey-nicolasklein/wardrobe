-- Sammlungen: named groups the user files looks into, e.g. "Urlaub" or "Büro".
CREATE TABLE look_collections (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40),
  emoji text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX look_collections_account ON look_collections (account_id, created_at);

CREATE TABLE look_collection_entries (
  collection_id uuid NOT NULL REFERENCES look_collections(id) ON DELETE CASCADE,
  look_id uuid NOT NULL REFERENCES looks(id) ON DELETE CASCADE,
  added_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (collection_id, look_id)
);
