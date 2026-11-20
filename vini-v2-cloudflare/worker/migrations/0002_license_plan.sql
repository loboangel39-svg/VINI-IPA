-- Prepare the server-managed license plan without changing access behavior.
-- Apply only after verifying the target D1 schema does not already contain
-- users.license_plan. This migration does not alter user_patches.
ALTER TABLE users ADD COLUMN license_plan TEXT NOT NULL DEFAULT 'Basic';

-- Preserve the existing two-state premium classification for current users.
UPDATE users SET license_plan = 'Premium' WHERE is_premium = 1;
