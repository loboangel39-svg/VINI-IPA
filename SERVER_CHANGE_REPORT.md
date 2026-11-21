# Informe de cambios del servidor

- Archivos Worker modificados: `vini-v2-cloudflare/worker/index.js`.
- Endpoints afectados: únicamente `/api/app/session` y `/api/app/validate-license` para clientes que declaran `access-state-v1`.
- Migraciones D1 modificadas: ninguna.
- Panel administrativo modificado: ninguno.
- Despliegue realizado: ninguno.
- Licencias reales modificadas: ninguna.

El cambio mínimo conserva la validación de firma, expiración, `session_version`, HWID, `is_active` e `is_blocked`. Solo permite que una cuenta pausada permanezca autenticada para que V2 reciba `access.status = license_paused`; los clientes legacy siguen recibiendo el rechazo histórico. No se desplegó a producción.
