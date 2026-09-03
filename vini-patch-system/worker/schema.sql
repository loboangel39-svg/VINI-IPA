-- VINI Patch Manager - Database Schema
-- Ejecutar: wrangler d1 execute vini-patch-db --file=schema.sql

-- Patches catalog
CREATE TABLE IF NOT EXISTS patches (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    bundle_id TEXT NOT NULL,
    version TEXT NOT NULL,
    description TEXT DEFAULT '',
    password TEXT DEFAULT '',
    created_at TEXT NOT NULL,
    updated_at TEXT DEFAULT NULL,
    downloads INTEGER DEFAULT 0
);

-- Users (registered automatically on first license use)
CREATE TABLE IF NOT EXISTS users (
    hwid TEXT PRIMARY KEY,
    license_key TEXT,
    device_model TEXT DEFAULT '',
    ios_version TEXT DEFAULT '',
    patches TEXT DEFAULT '[]',
    active INTEGER DEFAULT 1,
    created_at TEXT NOT NULL,
    last_seen_at TEXT DEFAULT NULL
);

-- License keys
CREATE TABLE IF NOT EXISTS licenses (
    key TEXT PRIMARY KEY,
    hwid TEXT DEFAULT NULL,
    device_model TEXT DEFAULT '',
    ios_version TEXT DEFAULT '',
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    bound_at TEXT DEFAULT NULL,
    last_login TEXT DEFAULT NULL,
    revoked INTEGER DEFAULT 0
);

-- Remote messages/broadcasts
CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    type TEXT DEFAULT 'info',
    target_hwid TEXT DEFAULT NULL,
    expires_at TEXT DEFAULT NULL,
    active INTEGER DEFAULT 1,
    created_at TEXT NOT NULL
);

-- Message acknowledgments
CREATE TABLE IF NOT EXISTS message_acks (
    message_id TEXT NOT NULL,
    hwid TEXT NOT NULL,
    acked_at TEXT NOT NULL,
    PRIMARY KEY (message_id, hwid)
);

-- Telemetry and analytics
CREATE TABLE IF NOT EXISTS telemetry (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    hwid TEXT NOT NULL,
    event_type TEXT NOT NULL,
    event_data TEXT DEFAULT '{}',
    created_at TEXT NOT NULL
);

-- Feature flags and remote config (cached in KV, but also in DB for history)
CREATE TABLE IF NOT EXISTS remote_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    updated_by TEXT DEFAULT 'admin'
);

-- App versions
CREATE TABLE IF NOT EXISTS versions (
    id TEXT PRIMARY KEY,
    version TEXT NOT NULL,
    min_ios TEXT NOT NULL,
    max_ios TEXT NOT NULL,
    changelog TEXT DEFAULT '',
    download_url TEXT DEFAULT '',
    force_update INTEGER DEFAULT 0,
    created_at TEXT NOT NULL
);

-- System logs
CREATE TABLE IF NOT EXISTS logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    level TEXT NOT NULL,
    message TEXT NOT NULL,
    source TEXT DEFAULT 'system',
    created_at TEXT NOT NULL
);

-- =====================================================
-- PATCH JOURNAL - Registra cada aplicación/restauración
-- Permite "Restore Original" sin errores
-- =====================================================
CREATE TABLE IF NOT EXISTS patch_journal (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    hwid TEXT NOT NULL,
    patch_id TEXT NOT NULL,
    action TEXT NOT NULL,              -- 'applied' | 'restored' | 'failed'
    target_file TEXT DEFAULT '',       -- nombre del archivo modificado
    original_hash TEXT DEFAULT '',     -- SHA-256 del archivo antes del patch
    patched_hash TEXT DEFAULT '',      -- SHA-256 del archivo después del patch
    backup_r2_key TEXT DEFAULT '',     -- clave R2 del backup (si se guardó)
    metadata TEXT DEFAULT '{}',        -- JSON con info extra (tamaño, fecha, etc.)
    created_at TEXT NOT NULL
);

-- =====================================================
-- INDEXES
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_patches_bundle ON patches(bundle_id);
CREATE INDEX IF NOT EXISTS idx_users_license ON users(license_key);
CREATE INDEX IF NOT EXISTS idx_users_last_seen ON users(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_licenses_hwid ON licenses(hwid);
CREATE INDEX IF NOT EXISTS idx_licenses_expires ON licenses(expires_at);
CREATE INDEX IF NOT EXISTS idx_messages_active ON messages(active, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_target ON messages(target_hwid);
CREATE INDEX IF NOT EXISTS idx_telemetry_hwid ON telemetry(hwid, created_at);
CREATE INDEX IF NOT EXISTS idx_telemetry_type ON telemetry(event_type, created_at);
CREATE INDEX IF NOT EXISTS idx_logs_created ON logs(created_at);
CREATE INDEX IF NOT EXISTS idx_logs_level ON logs(level);
CREATE INDEX IF NOT EXISTS idx_journal_hwid ON patch_journal(hwid, created_at);
CREATE INDEX IF NOT EXISTS idx_journal_patch ON patch_journal(patch_id);
CREATE INDEX IF NOT EXISTS idx_journal_action ON patch_journal(action);
