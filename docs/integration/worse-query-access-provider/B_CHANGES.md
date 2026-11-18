# B. Informe de cambios

Todo el trabajo está en `feature/worse-query-access-provider`, creada desde
`main` (`df99bf2`). `main` no recibió commits ni force-push.

## 1. Archivos añadidos

| Archivo | Contenido | Justificación |
|---|---|---|
| `ThirdParty/worse_query/worse_query.h` | Cabecera upstream sin modificar | Interfaz pública original. |
| `ThirdParty/worse_query/worse_query.m` | Implementación upstream sin modificar | Proveedor adicional real, no una reimplementación. |
| `ThirdParty/worse_query/LICENSE` | GPL-3.0 upstream | Cumplimiento de atribución; ver bloqueo de licencia en el informe F. |
| `ThirdParty/worse_query/README.md` | README upstream | Alcance declarado por el autor. |
| `ThreeOneOSFive/helpers/WorseQueryProviderPolicy.swift` | Mapa de prioridad y puertas de compatibilidad | Selección explícita y testeable, sin tocar el resolvedor. |
| `ThreeOneOSFive/helpers/WorseQueryAccessProvider.swift` | Adaptador, verificación de acceso, serialización y liberación | Encapsula la llamada C y comprueba que la concesión sirve para la operación. |
| `ThreeOneOSFive/helpers/WQEntitlements.h` | Declaración de `WQAuthorizedAppGroup` | Lectura de sólo lectura del entitlement efectivo. |
| `ThreeOneOSFive/helpers/WQEntitlements.m` | Implementación con `SecTaskCopyValueForEntitlement` | Usa el App Group realmente firmado; no inventa ni añade uno. |
| `Tests/WorseQueryProviderPolicyTests.swift` | Pruebas sintéticas de selección | Verifica el mapa, los límites y los casos no confirmados. |
| `.github/workflows/worse-query-access-provider.yml` | CI de integridad, pruebas y build | Verificación reproducible en macOS. |
| `docs/integration/worse-query-access-provider/*` | Informes y manifiestos | Evidencia de auditoría, integridad y firma. |

## 2. Archivos modificados

### `ThreeOneOSFive/helpers/ContainerStore.swift`

| Zona | Cambio | Motivo |
|---|---|---|
| `resolveAppContainerPathByMetadataScan(bundleID:)` | Sólo si el escape de sandbox del kernel no está activo, adquiere una concesión de la raíz; si la metadata no se puede leer, concede acceso al contenedor individual antes de reintentar. Sigue leyendo la metadata MCM y comparando el Bundle ID. | Permite que el proveedor adicional desbloquee el escaneo existente sin crear un catálogo ni un segundo motor. |
| `accessProviderDecision` | Calcula una vez el orden de proveedores con `WorseQueryProviderPolicy`. | Mantener la política en un único punto testeable. |
| `worseQueryAvailable` | Registra si hay App Group autorizado y versión compatible. | Diagnóstico honesto: si no hay App Group, el proveedor no se intenta. |
| `grantContainerAccess(_:requiringWrite:)` | Antes llamaba sólo a `bad_query`; ahora recorre `attemptOrder` en secuencia. Sigue devolviendo `Int64`. | Punto de conexión mínimo; todas las llamadas existentes conservan su firma. |
| `hasAccess(to:requiringWrite:)` | Comprueba `access(2)` con `R_OK|X_OK` y, si aplica, `W_OK`. | No tratar una ruta existente como prueba suficiente de acceso. |
| `releaseContainerAccess(_:)` | Libera el handle; ambos proveedores usan `sandbox_extension_release`. | Ciclo de vida explícito. |

No se cambió `resolveAppContainerPath(bundleID:)` salvo su llamada interna al
mismo escaneo; la prioridad MHA-C2 y la validación de ruta siguen intactas.

### `ThreeOneOSFive/helpers/DevicePatchService.swift`

`withResolvedContainers` ahora:

1. Resuelve la ruta con el mismo `ContainerStore.resolveAppContainerPath`.
2. Si la raíz no es escribible, pide una concesión adicional y la retiene hasta terminar la transacción.
3. Exige `R_OK|W_OK|X_OK` antes de llamar a `PatchTransaction`.
4. Si la metadata MCM es legible y no coincide con el Bundle ID solicitado, aborta con `targetAppUnavailable`.
5. Entrega a `PatchTransaction` exactamente la misma URL canónica que antes.

No se modificó `PatchTransaction`, ni sus recibos, fingerprints, journals,
backups, restore o rollback.

### `ThreeOneOSFive/ThreeOneOSFive-Bridging-Header.h`

Añade dos imports: `helpers/WQEntitlements.h` y
`../ThirdParty/worse_query/worse_query.h`. No elimina ni reordena los imports
existentes.

### `ThreeOneOSFive.xcodeproj/project.pbxproj`

Añade referencias y fases de compilación para los cuatro archivos nuevos
(`worse_query.m`, `WQEntitlements.m`, `WorseQueryAccessProvider.swift`,
`WorseQueryProviderPolicy.swift`). No cambia Bundle ID, deployment target,
entitlements, firma ni configuración de build.

## 3. Archivos deliberadamente intactos

- `App.swift`, `KernelExploit.swift`, `SBX.swift`, `SupportPolicy.swift`.
- `exploit/bad_query.c`, `exploit/bad_query.h`.
- `exploit/mcm_bridge.m`, `exploit/mcm_bridge.h` (MHA-C2).
- `kexploit/*` completo (`kexploit_opa334`, `sandbox_escape`, offsets, krw, vnode).
- `helpers/PatchTransaction.swift`, `PatchProjectModels.swift`.
- `helpers/ContainerBrowserLogic.swift`, `ContainerIdentityResolver.swift`.
- `helpers/FileManagerService.swift`.
- `views/*` completo, incluido `FileBrowserView.swift`, `AppDataBrowserView.swift`, `PatchProjectsView.swift`.
- `Info.plist`, `Assets.xcassets`, localizaciones.
- `.github/workflows/main.yml` y `.github/workflows/fix-login-files.yml`.
- `vini-v2-cloudflare/*`, login, JWT, Keychain, licencias.

## 4. Diferencia funcional en una frase

La única diferencia es que, cuando el acceso original no concede una ruta ya
resuelta, VINI intenta secuencialmente el proveedor adicional y exige una
verificación real de acceso antes de continuar; si el proveedor no está
disponible, se conserva el error original.
