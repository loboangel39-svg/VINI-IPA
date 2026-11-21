# Auditoría de despliegue del Worker

Fecha de auditoría: 2026-11-21

## Worker y versión activa

- Worker: `vini-v2-api`
- URL usada por la IPA: `https://vini-v2-api.loboangel39.workers.dev`
- Cuenta Cloudflare: cuenta autenticada mediante Wrangler; el identificador no se incluye en este informe.
- Versión activa: `27fa60ce-4431-4135-abef-d2a6047a4866`
- Creación de la versión activa: `2026-11-19T04:52:38Z`
- Tráfico: 100% hacia esa versión.
- Bindings declarados por la versión: D1 `vini-v2-db`, R2 `vini-patches`.

## Comparación con la corrección

`a27176b` fue creado el `2026-11-21T11:01:55-05:00`, después de la versión activa del Worker. Por tanto, la corrección de `verifyAppAuth`, `handleAppValidateLicense` y `getAccessState` no puede formar parte de la versión activa identificada.

La comprobación anónima de `/api/app/session` devuelve 401, pero no se usó como prueba de versión. La versión se identificó mediante `wrangler deployments status` y `wrangler versions view`.

## Staging

Se creó y validó un entorno aislado documentado en `STAGING_VALIDATION_REPORT.md`, usando Worker, D1 y R2 separados. No se copiaron datos personales ni secretos de producción.

## Procedimiento seguro propuesto

1. Crear una base D1 y un bucket R2 de staging separados.
2. Crear un `wrangler.staging.toml` con esos bindings y un nombre de Worker staging.
3. Inicializar únicamente el esquema de staging y crear una licencia de prueba.
4. Subir `a27176b` como versión etiquetada, sin desplegar producción.
5. Ejecutar pruebas V1/V2 activo, V2 pausado, mantenimiento, JWT revocado, HWID incorrecto y reactivación.
6. Promover la versión solo después de aprobación explícita.

## Rollback

El rollback de producción sería volver a desplegar la versión conocida `27fa60ce-4431-4135-abef-d2a6047a4866` mediante `wrangler versions deploy`, pero no se ejecutó.

No se modificaron D1, R2, licencias, `user_patches` ni producción durante esta auditoría.
