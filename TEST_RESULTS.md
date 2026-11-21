# Resultados de pruebas

## Ejecutadas

- `node --check vini-v2-cloudflare/worker/index.js`: PASS.
- `git diff --check`: PASS.
- `node worker/tests/access-state-policy.test.mjs`: PASS (tras ejecutar desde la raíz).
- Migración `0004` en D1 local efímera sobre esquema compatible: PASS en la validación histórica reportada.
- Workflow `44862497459`: PASS; compiló Swift.
- Workflow final `44862814537`: PASS; compiló Swift y generó un `.ipa` con `Payload/VINI.app`.

## No ejecutadas / bloqueadas

- IPA binaria original: bloqueada por HTTP 401 del artefacto GitHub.
- iPhone físico, staging Worker/D1, carga concurrente y regresión IPA antigua: PENDIENTES.
- Producción: deliberadamente no ejecutada.
- Artefacto final: https://api.github.com/repos/loboangel39-svg/VINI-IPA/actions/artifacts/14690003948/zip
