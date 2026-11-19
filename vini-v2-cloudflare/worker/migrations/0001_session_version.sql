-- Revokes all app JWTs when the administrator resets a user's HWID.
ALTER TABLE users ADD COLUMN session_version INTEGER NOT NULL DEFAULT 1;
