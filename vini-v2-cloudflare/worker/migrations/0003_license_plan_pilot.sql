-- Opt-in capability gate for the VINI-IPA 2.0 license-plan contract.
-- Existing users remain on the legacy contract until explicitly enabled.
ALTER TABLE users ADD COLUMN license_plan_enabled INTEGER NOT NULL DEFAULT 0;
