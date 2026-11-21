# Revisión previa a producción — `vini-v2-api`

Estado: **desplegado con autorización expresa**

## Versión activa

- Versión: `27fa60ce-4431-4135-abef-d2a6047a4866`
- Tráfico: 100%
- Compatibilidad: `2024-01-01`
- D1: `vini-v2-db`, ID `3f0d818b-0648-43f9-9dbe-3ffca38d2035`
- R2: `vini-patches`
- Variable: `ADMIN_USERNAME=admin`
- Secretos existentes: `ADMIN_PASSWORD`, `AUTH_JWT_SECRET`, `JWT_SECRET`, `LEASE_SIGNING_KEY`

No se han leído ni sustituido valores secretos.

## Código propuesto

La publicación propuesta es exactamente `a27176b` para `vini-v2-cloudflare/worker/index.js`. Frente a la base del Worker anterior (`40c76da`) son únicamente 7 líneas añadidas y 3 eliminadas:

1. `verifyAppAuth` conserva la autenticación V2 para una cuenta pausada cuando el cliente declara `access-state-v1`.
2. `handleAppValidateLicense` permite emitir una sesión V2 pausada para que el cliente reciba el estado bloqueante.
3. `getAccessState` incluye `users.is_paused` junto a `individual_pause` como causa `licensePause`.

Se mantienen firma JWT, expiración, HWID, `session_version`, `is_active`, `is_blocked`, contratos V1, D1, R2, `user_patches`, secretos y configuración productiva. No contiene cambios de AppIcon, SwiftUI, parches ni migraciones.

La comparación byte a byte con el bundle histórico de Cloudflare no está disponible mediante la salida pública de Wrangler; la versión activa y sus bindings sí fueron verificados con `deployments status` y `versions view`. El diff reproducible del código fuente está en `git diff 40c76da..a27176b -- vini-v2-cloudflare/worker/index.js`.

## Validación de publicación

`wrangler deploy --dry-run --config wrangler.toml` completó correctamente y mostró los bindings de producción. Después se publicó la versión `c5cb49ea-b669-4903-bc76-08608d26dc7e` y se asignó el 100% del tráfico.

La versión desplegada conserva D1 `vini-v2-db`, R2 `vini-patches`, `ADMIN_USERNAME=admin` y los cuatro nombres de secretos existentes. Una solicitud anónima a `/api/app/session` continúa siendo rechazada con `valid:false`; no se relajó la autenticación.

No se ejecutaron migraciones D1 ni operaciones R2.

## Procedimiento utilizado

```powershell
cd vini-v2-cloudflare/worker
npx wrangler versions upload --config wrangler.toml --message "fix: preserve paused V2 sessions (a27176b)"
npx wrangler versions deploy c5cb49ea-b669-4903-bc76-08608d26dc7e --name vini-v2-api
```

No ejecutar migraciones D1 ni comandos R2.

## Rollback

```powershell
npx wrangler versions deploy 27fa60ce-4431-4135-abef-d2a6047a4866 --name vini-v2-api
```

Este rollback solo cambia el tráfico al bundle anterior; no revierte datos D1 ni modifica R2. Debe verificarse después con `npx wrangler deployments status --name vini-v2-api`.
