-- Hearts move from the phone to the server, so they can weight the shot types
-- the planner picks.
ALTER TABLE looks ADD COLUMN liked_at timestamptz;
