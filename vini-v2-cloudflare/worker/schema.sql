-- VINI V2 - Database Schema

-- Users table
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  hwid TEXT DEFAULT '',
  license_key TEXT DEFAULT '',
  is_premium INTEGER DEFAULT 0,
  is_active INTEGER DEFAULT 1,
  is_paused INTEGER DEFAULT 0,
  is_blocked INTEGER DEFAULT 0,
  permissions TEXT DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Patches table
CREATE TABLE IF NOT EXISTS patches (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  version TEXT DEFAULT '1.0.0',
  type TEXT DEFAULT 'free',
  file_key TEXT DEFAULT '',
  content_key TEXT DEFAULT '',
  active INTEGER DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- User-Patch access table
CREATE TABLE IF NOT EXISTS user_patches (
  user_id TEXT NOT NULL,
  patch_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, patch_id),
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (patch_id) REFERENCES patches(id)
);

-- Messages table
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  type TEXT DEFAULT 'info',
  target_hwid TEXT,
  active INTEGER DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Downloads table
CREATE TABLE IF NOT EXISTS downloads (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  patch_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (patch_id) REFERENCES patches(id)
);

-- Activity log table
CREATE TABLE IF NOT EXISTS activity_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  action TEXT NOT NULL,
  details TEXT DEFAULT '',
  created_at TEXT NOT NULL
);

-- Config table
CREATE TABLE IF NOT EXISTS config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Insert default config
INSERT OR IGNORE INTO config (key, value, updated_at) VALUES ('app_name', 'VINI V2', datetime('now'));
INSERT OR IGNORE INTO config (key, value, updated_at) VALUES ('maintenance_mode', '0', datetime('now'));
INSERT OR IGNORE INTO config (key, value, updated_at) VALUES ('max_downloads_per_day', '100', datetime('now'));
