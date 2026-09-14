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

-- VINI Rewards System

-- Add rewards columns to users table
ALTER TABLE users ADD COLUMN points INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN referral_code TEXT DEFAULT '';
ALTER TABLE users ADD COLUMN referred_by TEXT DEFAULT '';

-- Daily status reports (trust system)
CREATE TABLE IF NOT EXISTS daily_status (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  patch_id TEXT NOT NULL,
  status TEXT NOT NULL,
  report_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id),
  FOREIGN KEY (patch_id) REFERENCES patches(id),
  UNIQUE(user_id, patch_id, report_date)
);

-- Referrals tracking
CREATE TABLE IF NOT EXISTS referrals (
  id TEXT PRIMARY KEY,
  referrer_id TEXT NOT NULL,
  referred_id TEXT NOT NULL,
  confirmed INTEGER DEFAULT 0,
  reward_granted INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  confirmed_at TEXT,
  FOREIGN KEY (referrer_id) REFERENCES users(id),
  FOREIGN KEY (referred_id) REFERENCES users(id),
  UNIQUE(referred_id)
);

-- Rewards transactions history
CREATE TABLE IF NOT EXISTS rewards_transactions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  type TEXT NOT NULL,
  points INTEGER DEFAULT 0,
  days_added INTEGER DEFAULT 0,
  description TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Permanence rewards tracking (3 months milestone)
CREATE TABLE IF NOT EXISTS permanence_rewards (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  milestone_months INTEGER NOT NULL,
  reward_granted INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id),
  UNIQUE(user_id, milestone_months)
);
