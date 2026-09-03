-- Migración: Sistema de Tiers (Normal/Premium) con Permisos Separados
-- Ejecutar: wrangler d1 execute vini-patch-db --file=migration_tiers.sql --remote

-- Agregar tier a patches (default: normal)
ALTER TABLE patches ADD COLUMN tier TEXT DEFAULT 'normal';

-- Agregar tier a licenses (default: normal)
ALTER TABLE licenses ADD COLUMN tier TEXT DEFAULT 'normal';

-- Tabla de accesos premium (quién puede acceder a qué patch premium)
CREATE TABLE IF NOT EXISTS user_patch_access (
    hwid TEXT NOT NULL,
    patch_id TEXT NOT NULL,
    granted_at TEXT NOT NULL,
    granted_by TEXT DEFAULT 'admin',
    PRIMARY KEY (hwid, patch_id)
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_patches_tier ON patches(tier);
CREATE INDEX IF NOT EXISTS idx_licenses_tier ON licenses(tier);
CREATE INDEX IF NOT EXISTS idx_user_patch_access_hwid ON user_patch_access(hwid);
CREATE INDEX IF NOT EXISTS idx_user_patch_access_patch ON user_patch_access(patch_id);

-- Actualizar datos existentes
UPDATE patches SET tier = 'normal' WHERE tier IS NULL;
UPDATE licenses SET tier = 'normal' WHERE tier IS NULL;
