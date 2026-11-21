# Auditoría D1

- `0004_access_state.sql` es aditiva y crea controles, proveedores, mantenimiento, estado congelado, eventos e índices.
- `user_patches` no se modifica.
- `provider_id` no permite asignación silenciosa: por defecto es `NULL` y solo una acción administrativa puede asignarlo.
- Mantenimiento global afecta a usuarios sin proveedor; mantenimiento de proveedor solo consulta asociaciones válidas.

## Bloqueo de migración

`0001_session_version.sql` intenta añadir una columna que ya aparece en el `schema.sql` actual. No se ejecutó la cadena histórica en producción ni se declara lista para producción. El preflight requerido debe consultar `PRAGMA table_info(users)`, la tabla de migraciones y la existencia de las tablas de `0004`; solo después debe ejecutar los cambios faltantes en staging.

## Tiempo

El cálculo usa `Date`/UTC del Worker y segundos truncados hacia abajo. El estado congelado se escribe una sola vez por intervalo lógico mediante `frozen_seconds IS NULL`. La concurrencia entre solicitudes de lectura/escritura independientes sigue siendo una limitación no resuelta y está documentada como BLOQUEADA.
