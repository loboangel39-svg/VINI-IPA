# Reset HWID / expiración — auditoría previa

Fecha: 2026-11-21

## Producción observada

`wrangler deployments status --name vini-v2-api` reporta producción al 100 % en:

`27fa60ce-4431-4135-abef-d2a6047a4866`

La versión no coincide con el `index.js` actual del repositorio; por tanto, no se puede atribuir automáticamente al código local el comportamiento observado en producción.

## D1 productiva (solo lectura)

Se ejecutó `PRAGMA table_info(users)` y una consulta de `sqlite_master` con `--remote`; ambas tuvieron `changes: 0` y `rows_written: 0`.

La tabla productiva `users` contiene `license_expires_at` y `session_version`, además de `hwid`, `is_active`, `is_paused` e `is_blocked`. Sin embargo, la base productiva no contiene las tablas del migration `0004_access_state.sql` (`access_controls`, `license_access_state`, `provider_maintenance`, `access_state_events`).

Esto es incompatible con desplegar sin más el `index.js` actual: las rutas con `access-state-v1` pueden intentar consultar tablas ausentes.

## Reset HWID local

El handler actual usa:

```sql
UPDATE users
SET hwid = '', session_version = COALESCE(session_version, 1) + 1
WHERE id = ?
```

La combinación `hwid` vacío + incremento de `session_version` sí invalida JWT anteriores del usuario seleccionado, sin cambiar licencias ni fechas. El endpoint está protegido por la autenticación administrativa global del router. Debe verificarse que `27fa60ce` contenga la misma lógica antes de atribuirle este comportamiento.

## Expiración

El código actual usa `license_expires_at` y la hora del Worker, pero compara con `<` en varios puntos. El instante exacto de vencimiento debe tratarse como expirado (`<=`) y las rutas app deben devolver el estado/HTTP consistente.

La IPA realiza comprobación al inicio, foreground y cada 60 segundos. Ante error de red conserva la sesión; ante `.revoked` cierra sesión. La ruta actual de `verifyStoredSession` permite que un cliente `access-state-v1` consulte el estado expirado, pero producción no tiene las tablas necesarias para materializar ese contrato.

## Bloqueo de seguridad

No se modificó D1, usuarios, licencias, sesiones, secretos ni tráfico. No existe en el repositorio una cuenta sintética productiva autorizada para probar escritura. No es seguro crearla ni ejecutar Reset/Renew sobre un usuario real.

Antes de implementar y desplegar se necesita una de estas autorizaciones: (a) un usuario sintético productivo explícitamente aprobado, o (b) autorización para una migración aditiva de las tablas de access-state y un procedimiento de validación productivo aprobado. La validación local no demuestra compatibilidad con la versión `27fa60ce`.
