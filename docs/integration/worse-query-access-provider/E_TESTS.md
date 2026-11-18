# E. Informe de pruebas

## 1. Baseline de compilación

| Elemento | Resultado |
|---|---|
| Repositorio | `loboangel39-svg/VINI-IPA` |
| Commit `main` | `df99bf2fbb32b86966990077864a9d355271197b` |
| Workflow | `Build VINI` (`main.yml`) |
| Run | [42700087678](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/42700087678) |
| Resultado | **success** |
| Artefacto | `.app` / `VINI-iOS` del workflow original |

Se conservó el estado original de compilación. También se lanzó un build de
comprobación del mismo `main` (run `44235909258`, `workflow_dispatch`).

## 2. CI de la rama experimental

Workflow nuevo: `WorseQuery access provider validation`
(`.github/workflows/worse-query-access-provider.yml`).

Comprueba, en un runner macOS:

1. Integridad byte a byte del upstream vendorizado.
2. Integridad de 102 componentes protegidos.
3. Intersección entre archivos cambiados y lista protegida.
4. Bundle ID y ausencia de App Group añadido.
5. Pruebas sintéticas de selección de proveedor.
6. Pruebas sintéticas de identidad, UUID y reinstalación.
7. Guardarraíles de arquitectura (una sola resolución, un solo motor).
8. Compilación iOS arm64 sin firma.
9. Inspección del producto (Bundle ID, versión, librerías, entitlements).
10. Empaquetado de IPA sin firmar + SHA-256.

### Resultado registrado

| Elemento | Resultado |
|---|---|
| Commit validado | `df9008d47e0a3611296eb735c177c87edd09790f` |
| Run | [44236967928](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44236967928) |
| Resultado | **success** |
| Runner | macOS, Xcode 26.6 (`17F113`) |
| Producto | `VINI.app`, iOS arm64 Release, sin firma |
| Bundle ID construido | `com.apple.mobile.MobileHouseArrest` |
| Pruebas de política | **PASS** |
| Pruebas de identidad/reinstalación | **PASS** |
| Componentes protegidos | 102 comprobados, 0 diferencias |
| Artefacto de informes | [`worse-query-access-provider-reports`](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44236967928/artifacts/14398280896) |
| Artefacto IPA | [`VINI-WorseQuery-AccessProvider-Unsigned`](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44236967928/artifacts/14397234249) |
| SHA-256 IPA | `ed2d104dc7d33d63a255691864870de34ea22006053de346e5ddf8b4ce62d839` |

La IPA es exclusivamente experimental y **no está firmada**. El artefacto no
demuestra funcionamiento del proveedor en un dispositivo real.

## 3. Pruebas sintéticas de selección

Archivo: `Tests/WorseQueryProviderPolicyTests.swift`.

| Caso | Esperado |
|---|---|
| iOS 26.0 / 26.6.1 | `bad_query` primero; `worse_query` como fallback permitido |
| iOS 26.6.2 / 26.7.2 | `worse_query` primero; `bad_query` como fallback |
| iOS 26.7.3 | sólo `bad_query` (fuera del techo upstream) |
| iOS 27.0 beta 1 / beta 4 | `bad_query` primero (build verificado) |
| iOS 27.0 build desconocido | `bad_query`; no se adivina beta 5+; nota registrada |
| iOS 27.1 / 27.2 | `worse_query` primero |
| iOS 27.3 | `bad_query`; conflicto con el techo 27.2 registrado |
| iOS 28 / iOS 25 | sólo `bad_query`; nunca se inventa soporte |
| Orden de proveedores | máximo dos, sin duplicados, estrictamente secuencial |

## 4. Pruebas sintéticas de identidad y reinstalación

Archivo: `Tests/ContainerIdentityContractTests.swift`.

| Caso | Esperado |
|---|---|
| `grantAccess` devuelve `-3` | `.accessFailed(-3)`; no se lee metadata; nunca se convierte en éxito |
| Metadata ausente | `.metadataUnavailable` |
| `systemgroup.*` | `.unsupportedIdentifier`; no se presenta como app |
| Metadata coincidente | `.resolved` |
| Reinstalación simulada | el mismo Bundle ID resuelve primero el UUID A y luego el UUID B; no hay caché persistente |
| Liberación | cada handle concedido se libera |
| Ruta `/var/...` | se canonicaliza a `/private/var/...` |
| Merge | se conserva el orden y gana la entrada identificada |
| UUID como Bundle ID | no se muestra como app ni como nombre |

Estas pruebas usan datos sintéticos. **No** demuestran que una concesión
sandbox real funcione en un iPhone.

## 5. Pruebas de fallo y recuperación

- Si `worse_query` no está disponible, `grantContainerAccess` devuelve `-1` y
  el código original conserva su error.
- Si la concesión no permite `R_OK|X_OK` (o `W_OK` para patches), el handle se
  libera y no se devuelve como éxito.
- Si el acceso de escritura no puede confirmarse, `DevicePatchService` lanza
  `targetAppUnavailable` antes de llamar a `PatchTransaction`.
- Si la metadata legible no coincide con el Bundle ID, se aborta antes de la
  transacción.
- `PatchTransaction` conserva todas sus comprobaciones de fingerprint,
  recibos, journal, backup, restore y rollback.

## 6. Pruebas en dispositivo — PENDIENTE / BLOQUEADO

No se dispone de un iPhone real, una firma autorizada con App Group ni un
provisioning profile en este entorno. No se declara ninguna de estas pruebas
como aprobada:

| Prueba | Estado |
|---|---|
| Instalar compilación experimental firmada | **PENDIENTE** |
| App Group real identificado y autorizado | **BLOQUEADO** (no hay perfil con App Group) |
| Estado real del proveedor seleccionado | **PENDIENTE** |
| Descubrimiento de Files sin regresiones | **PENDIENTE** |
| Resolución Bundle ID -> UUID actual | **PENDIENTE** |
| Acceso a contenedores de prueba autorizados | **PENDIENTE** |
| Aplicación de un patch de prueba | **PENDIENTE** |
| Restauración y comprobación de fingerprints | **PENDIENTE** |
| Reinstalación y nueva resolución | **PENDIENTE** |
| Funcionamiento original sin `worse_query` | **PENDIENTE** en dispositivo; cubierto parcialmente por el build y por el fallback |

El simulador no se considera equivalente a un iPhone para exploits,
concesiones sandbox ni App Groups.

## 7. Criterio de honestidad

Cualquier ejecución que no se haya producido se marca `PENDIENTE`. Ningún
error de acceso se convierte en resultado positivo. La integración no se
declara funcional en dispositivo hasta disponer de evidencia real.
