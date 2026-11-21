# Auditoría panel administrativo

- Las acciones de pausa individual, pausa global, mantenimiento global y mantenimiento por proveedor llaman endpoints reales.
- Las acciones globales y de proveedor piden confirmación.
- El panel usa el token almacenado solo como Bearer; no contiene secretos de Worker.
- Se corrigió el helper `api` para rechazar HTTP 4xx/5xx y evitar falsos éxitos.

## Pendiente

La tabla principal todavía muestra principalmente `license_expires_at`; la visualización detallada de `frozenSeconds` e historial requiere una prueba UI/staging y no se declara completada solo por inspección estática.
