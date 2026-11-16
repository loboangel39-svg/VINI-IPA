-- Presentation-only category metadata. No license, access, package or key data
-- is changed. NULL means intentionally unclassified.
CREATE TABLE IF NOT EXISTS patch_categories (
  patch_id TEXT PRIMARY KEY REFERENCES patches(id) ON DELETE CASCADE,
  category_id INTEGER NULL CHECK (category_id IS NULL OR category_id IN (1, 2, 3)),
  updated_at TEXT NOT NULL
);
