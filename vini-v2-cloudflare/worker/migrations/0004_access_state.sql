-- VINI-IPA 2.0 access-state controls. Additive; legacy clients are unaffected.
ALTER TABLE users ADD COLUMN provider_id TEXT DEFAULT NULL;

CREATE TABLE IF NOT EXISTS access_controls (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  global_license_pause INTEGER NOT NULL DEFAULT 0,
  global_maintenance INTEGER NOT NULL DEFAULT 0,
  maintenance_message TEXT NOT NULL DEFAULT '',
  changed_at TEXT NOT NULL,
  changed_by TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS providers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS provider_maintenance (
  provider_id TEXT PRIMARY KEY,
  enabled INTEGER NOT NULL DEFAULT 0,
  message TEXT NOT NULL DEFAULT '',
  changed_at TEXT NOT NULL,
  changed_by TEXT NOT NULL,
  FOREIGN KEY (provider_id) REFERENCES providers(id)
);

CREATE TABLE IF NOT EXISTS license_access_state (
  user_id TEXT PRIMARY KEY,
  individual_pause INTEGER NOT NULL DEFAULT 0,
  frozen_seconds INTEGER,
  frozen_at TEXT,
  updated_at TEXT NOT NULL,
  updated_by TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS access_state_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT,
  provider_id TEXT,
  scope TEXT NOT NULL,
  action TEXT NOT NULL,
  previous_state TEXT NOT NULL DEFAULT '',
  next_state TEXT NOT NULL DEFAULT '',
  frozen_seconds INTEGER,
  admin_user TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_users_provider_id ON users(provider_id);
CREATE INDEX IF NOT EXISTS idx_access_events_user ON access_state_events(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_access_events_provider ON access_state_events(provider_id, created_at DESC);

INSERT OR IGNORE INTO access_controls
  (id, changed_at, changed_by)
VALUES (1, datetime('now'), 'migration');
