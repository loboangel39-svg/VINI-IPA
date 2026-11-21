# Resultados de pruebas

## Ejecutadas

- `node --check vini-v2-cloudflare/worker/index.js`: PASS.
- `git diff --check`: PASS.
- `node worker/tests/access-state-policy.test.mjs`: PASS (tras ejecutar desde la raíz).
- Migración `0004` en D1 local efímera sobre esquema compatible: PASS en la validación histórica reportada.
- Workflow `44862497459`: PASS; compiló Swift.
- Workflow final `44862814537`: PASS; compiló Swift y generó un `.ipa` con `Payload/VINI.app`.
- Workflow de esta corrección `44863588797`: PASS; compiló Swift desde `b159bf6`.
- Worker/D1 local normalizado: PASS para login V2, pausa individual, mantenimiento global, mantenimiento por proveedor y transiciones autenticadas.
- Solicitud administrativa sin Bearer: PASS, respondió HTTP 401.

## No ejecutadas / bloqueadas

- IPA binaria original: bloqueada por HTTP 401 del artefacto GitHub.
- iPhone físico, staging Worker/D1, carga concurrente y regresión IPA antigua: PENDIENTES.
- Producción: deliberadamente no ejecutada.
- Artefacto final: https://api.github.com/repos/loboangel39-svg/VINI-IPA/actions/artifacts/14690003948/zip
- Artefacto de esta corrección: https://api.github.com/repos/loboangel39-svg/VINI-IPA/actions/artifacts/14691131356/zip

## Evidencia de integración local

Con `integration-user`, plan V2 habilitado y `provider-a`:

- Login inicial: `access.status = active`.
- Pausa individual: `license_paused`, `licensePause = true`, `frozenSeconds = 277186`.
- Mantenimiento global simultáneo: `maintenance`, conservó `frozenSeconds = 277186`.
- Desactivación global parcial: volvió a `license_paused`, no a `active`.
- Reactivación individual completa: volvió a `active` y recalculó desde el tiempo congelado.
- Mantenimiento por proveedor: `maintenance`, `providerMaintenance = true`.
- Desactivación por proveedor: volvió a `active`.

La validación visual en iPhone/simulador no se ejecutó; la transición de pantallas se verificó mediante contrato HTTP y navegación estática.
