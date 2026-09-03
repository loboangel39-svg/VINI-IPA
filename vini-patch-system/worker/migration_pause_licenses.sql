-- Migración: Agregar columna 'paused' a la tabla licenses
-- Ejecutar en D1: wrangler d1 execute vini-patch-db --file=migration_pause_licenses.sql

-- Columna para pausar licencias individualmente
ALTER TABLE licenses ADD COLUMN paused INTEGER DEFAULT 0;

-- Índice para consultas rápidas de licencias pausadas
CREATE INDEX IF NOT EXISTS idx_licenses_paused ON licenses(paused);
