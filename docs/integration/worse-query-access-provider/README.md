# Integración de `worse_query` como proveedor de acceso adicional

Rama: `feature/worse-query-access-provider`
Base: `main` @ `df99bf2fbb32b86966990077864a9d355271197b`
PR: **pendiente de crear** (se enlazará al publicar la rama)

## 1. Qué hace esta integración

Añade `worse_query` como **proveedor adicional de acceso sandbox por ruta**,
sin sustituir ni reimplementar nada del motor 3105 existente:

- `bad_query`, `kexploit_opa334`, MHA-C2/MCM, el formato `.3105`, el
  import/export, `PatchTransaction` y el journal/backup/rollback no se tocan.
- La resolución Bundle ID → UUID y el descubrimiento de Files siguen siendo
  los originales. `worse_query` sólo consume rutas ya resueltas y validadas.
- El orden de proveedores se decide una sola vez con una política pura y
  testeable. Los intentos son estrictamente secuenciales; nunca simultáneos.
- Antes de dar una concesión por buena se comprueba con `access(2)` que la
  operación prevista (`R_OK|X_OK`, y `W_OK` para escritura) es realmente
  posible.
- `DevicePatchService` exige acceso de escritura verificable y, si la metadata
  MCM es legible, comprueba que el Bundle ID coincide antes de iniciar
  `PatchTransaction`.

Detalle completo en [B_CHANGES.md](B_CHANGES.md).

## 2. Mapa de proveedores solicitado y estado real

| Rango | Proveedor solicitado | Estado |
|---|---|---|
| iOS 26.0 – 26.6.1 | `bad_query` | Verificado por VINI; se mantiene primero, con `worse_query` como fallback permitido |
| iOS 26.6.2 – 26.7.2 | `worse_query` | Dentro del rango declarado por upstream; **no verificado en dispositivo** |
| iOS 27.0 beta 1 – beta 4 | `bad_query` | Builds identificados por VINI; se mantiene primero |
| iOS 27.0 beta 5 – 27.3 beta 1 | `worse_query` | 27.0b5+ no es identificable con la tabla actual; 27.3b1 queda fuera del techo 27.2 de upstream. En ambos casos se conserva `bad_query` y se registra el motivo |

El techo documentado por upstream es iOS 26.0–26.7.2 e iOS 27.0–27.2. La
política no inventa soporte para builds desconocidos ni para 27.3 beta 1.

## 3. Informes

| Informe | Contenido |
|---|---|
| [A_ARCHITECTURE.md](A_ARCHITECTURE.md) | Flujo de acceso, punto de conexión y límites de responsabilidad |
| [B_CHANGES.md](B_CHANGES.md) | Archivos añadidos/modificados y motivo de cada cambio |
| [C_INTEGRITY.md](C_INTEGRITY.md) | SHA-256 del upstream, de los componentes protegidos y de la integración |
| [D_SIGNING.md](D_SIGNING.md) | Bundle ID, App Group, entitlements y estado de firma |
| [E_TESTS.md](E_TESTS.md) | Pruebas sintéticas, CI, build y pruebas en dispositivo `PENDIENTE` |
| [F_FUNCTIONAL_COMPARISON.md](F_FUNCTIONAL_COMPARISON.md) | Comparación funcional antes/después y regresiones esperadas |
| [UPSTREAM_AUDIT.md](UPSTREAM_AUDIT.md) | Auditoría del código upstream vendorizado |

Manifiestos:

- `PROTECTED_COMPONENTS.sha256`: 102 componentes que no pueden cambiar.
- `UPSTREAM_SHA256.sha256`: los 4 archivos vendorizados.
- `BASELINE_SHA256.tsv`: inventario completo del baseline.

## 4. Estado de verificación

- Integridad local: **102 componentes comprobados, 0 diferencias**.
- Upstream vendorizado: **4 archivos, 0 diferencias**.
- Pruebas sintéticas de política e identidad: se ejecutan en el workflow
  `WorseQuery access provider validation`.
- Build iOS arm64 sin firma: se ejecuta en el mismo workflow.
- Run de CI, artefactos y commit exacto: **PENDIENTE DE REGISTRAR** hasta
  publicar la rama.

Ningún resultado sintético se presenta como prueba en dispositivo.

## 5. Bloqueos declarados

1. **App Group / firma:** el repositorio no contiene `.entitlements`, no tiene
   `CODE_SIGN_ENTITLEMENTS` configurado ni un provisioning profile autorizado
   con App Group. `worse_query` no puede funcionar en tiempo de ejecución
   hasta que exista una firma autorizada. La aplicación descubre el App Group
   desde el entitlement efectivo del proceso firmado; no lo inventa ni lo
   añade. Ver [D_SIGNING.md](D_SIGNING.md).
2. **Licencia:** el upstream es GPL-3.0 y VINI-IPA no tiene archivo `LICENSE`.
   No debe publicarse ni distribuirse una IPA comercial que incorpore este
   código hasta resolver la compatibilidad. Ver
   [F_FUNCTIONAL_COMPARISON.md](F_FUNCTIONAL_COMPARISON.md).
3. **Pruebas en dispositivo:** sin iPhone real ni firma autorizada, todas las
   pruebas de acceso, Files, patch, restore y reinstalación quedan
   `PENDIENTE`. Ver [E_TESTS.md](E_TESTS.md).

## 6. Reproducir la validación

```sh
git checkout feature/worse-query-access-provider
shasum -a 256 -c docs/integration/worse-query-access-provider/UPSTREAM_SHA256.sha256
shasum -a 256 -c docs/integration/worse-query-access-provider/PROTECTED_COMPONENTS.sha256

swiftc -parse-as-library -O -o /tmp/wq-policy-tests \
  Tests/WorseQueryProviderPolicyTests.swift \
  ThreeOneOSFive/helpers/WorseQueryProviderPolicy.swift \
  ThreeOneOSFive/helpers/SupportPolicy.swift
/tmp/wq-policy-tests

swiftc -parse-as-library -O -o /tmp/wq-identity-tests \
  Tests/ContainerIdentityContractTests.swift \
  ThreeOneOSFive/helpers/ContainerBrowserLogic.swift \
  ThreeOneOSFive/helpers/ContainerIdentityResolver.swift
/tmp/wq-identity-tests
```

La compilación iOS sin firma se ejecuta en
`.github/workflows/worse-query-access-provider.yml` con el mismo esquema
(`3105`), configuración `Release` y `CODE_SIGNING_ALLOWED=NO` que el workflow
original, sin modificar `main.yml` ni `fix-login-files.yml`.
