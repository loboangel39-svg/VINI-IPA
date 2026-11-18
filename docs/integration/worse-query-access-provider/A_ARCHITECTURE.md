# A. Informe de arquitectura

Base auditada: `main` = `df99bf2fbb32b86966990077864a9d355271197b`.
Rama de trabajo: `feature/worse-query-access-provider`.

## 1. Flujo de producción (sin cambios de contrato)

```
App.swift
  AppState.detectSupport()
    -> ExploitSupportPolicy.isSupported(...)
    -> KernelExploit.run()
         -> kexploit_opa334()
         -> sandbox_escape(proc_self())

Files
  AppDataBrowserView
    -> ContainerStore.installedAppsFromAPI()
    -> ContainerStore.dynamicAppIdentifiers() / installedAppsFromMCM()
    -> ContainerStore.containersFromFilesystem()
    -> ContainerStore.launchServicesStoreIdentifiers()
    -> ContainerStore.installedAppsFromMHACandidates()
    -> ContainerStore.inferUnidentifiedApps()
    -> ContainerStore.listFiles(at:)

FileBrowserView.load()
  -> MCMActivateContainer(2, bundleID, ...)
  -> fallback ContainerStore.grantContainerAccess(path)
  -> ContainerStore.listFiles(at: path)

Patches
  PatchProjectsView.apply()
    -> DevicePatchService.apply(project:)
      -> withResolvedContainers(bundleIDs:)
        -> ContainerStore.resolveAppContainerPath(bundleID:)
          -> MCMActivateContainerPath(2, bundleID, false, ...)   // MHA-C2
          -> fallback resolveAppContainerPathByMetadataScan()
        -> PatchTransaction.apply(project:backupRoot:containerResolver:)
```

## 2. Matriz de funciones y dependencias reales

| Función / símbolo | Archivo | Qué hace | Contrato que se conserva |
|---|---|---|---|
| `AppState.detectSupport()` | `App.swift` | Aplica `ExploitSupportPolicy`, consulta `KernelExploit.hasSandboxAccess()`, lanza el exploit. | Sin cambios. |
| `KernelExploit.run()` | `helpers/KernelExploit.swift` | `kexploit_opa334` + `sandbox_escape`; no participa en la selección de proveedor. | Sin cambios. |
| `MCMActivateContainerPath(cls:identifier:group:error:)` | `exploit/mcm_bridge.m` | Consulta MCM (MHA-C2), activa un lease, abre la raíz con `O_NOFOLLOW` y devuelve la ruta. | Sin cambios. Es la resolución autoritativa Bundle ID -> contenedor. |
| `MCMActivateContainer(...)` | `exploit/mcm_bridge.m` | Variante que devuelve un handle lógico; usada por `FileBrowserView.load()`. | Sin cambios. |
| `bad_query(...)` / `bad_query_list(...)` | `exploit/bad_query.c` | Concesión sandbox por `part_domain` y enumeración por inodos. | Sin cambios. |
| `ContainerStore.resolveAppContainerPath(bundleID:)` | `helpers/ContainerStore.swift` | Valida el Bundle ID, intenta MHA-C2 y cae al escaneo de metadatos. | Firma y orden intactos. |
| `ContainerStore.resolveAppContainerPathByMetadataScan(bundleID:)` | `helpers/ContainerStore.swift` | Enumera `/var/mobile/Containers/Data/Application`, lee metadata MCM y confirma el Bundle ID. | Sigue siendo el mismo escáner; sólo se añadió acceso por contenedor cuando la lectura directa falla. |
| `ContainerStore.grantContainerAccess(_:)` | `helpers/ContainerStore.swift` | Concedía acceso con `bad_query`. | Ahora intenta los proveedores en orden secuencial. Sigue devolviendo un handle `Int64` y no resuelve identidades. |
| `FileBrowserView.load()` | `views/FileBrowserView.swift` | Intenta MCM y, si falla, `ContainerStore.grantContainerAccess(path)`. | Sin cambios; hereda el proveedor adicional. |
| `DevicePatchService.apply(project:)` | `helpers/DevicePatchService.swift` | Resuelve raíces y llama a `PatchTransaction.apply`. | Orden y motor intactos. |
| `DevicePatchService.withResolvedContainers` | `helpers/DevicePatchService.swift` | Resolvía rutas y las canonicalizaba. | Añade verificación de acceso de escritura y coincidencia de metadata; no resuelve UUIDs. |
| `PatchTransaction.apply/restore/inspectRestore` | `helpers/PatchTransaction.swift` | Backups, journal, fingerprints, rollback, recibos. | Sin cambios. |
| `ContainerIdentityResolver` | `helpers/ContainerIdentityResolver.swift` | Fallback de identidad por metadata. | Sin cambios. |
| `ContainerBrowserLogic` | `helpers/ContainerBrowserLogic.swift` | Mergers, política de grants, candidatos y LaunchServices. | Sin cambios. |

## 3. Punto exacto de conexión

Se añadió una única capa de acceso:

```
ContainerStore.grantContainerAccess(path, requiringWrite:)
  -> WorseQueryProviderPolicy.decision(...)
  -> intenta bad_query y/o worse_query, en secuencia
  -> devuelve un handle o -1
```

y una comprobación en la capa de servicio de patches:

```
DevicePatchService.withResolvedContainers
  -> si la ruta resuelta no es escribible: grantContainerAccess(path, requiringWrite: true)
  -> verifica access(R_OK|W_OK|X_OK)
  -> verifica metadata MCM si es legible
  -> entrega la misma raíz a PatchTransaction
```

No se creó un segundo motor de Files, un segundo motor de Patches, un catálogo alternativo ni una tabla Bundle ID -> UUID.

## 4. Qué es y qué no es `worse_query`

`worse_query(path, group, alt_flags, create_dir)`:

1. Exige una ruta destino existente (salvo `create_dir`).
2. Exige un App Group que la firma autorice y cuyo contenedor sea alcanzable.
3. Sustituye `Library/Caches` del App Group por un symlink al destino.
4. Consulta containermanager (clase 7, part 3) y consume la extensión sandbox devuelta.
5. Restaura `Library/Caches` y devuelve un handle de extensión.

Por tanto:

| Mecanismo | Qué autentica / concede | Lo usa esta integración |
|---|---|---|
| JWT de VINI | Sesión de usuario y licencia | No se toca. |
| Extensión sandbox (`worse_query`, `bad_query`, MCM) | Acceso a una ruta concreta | Sí, sólo en la capa de acceso. |
| Acceso kernel (`kexploit_opa334` + `sandbox_escape`) | Capacidad global de lectura/escritura fuera del sandbox | No se toca ni se sustituye. |

`worse_query` no genera el mismo token que MCM ni que `bad_query`, y no produce identificadores de contenedor. Sólo se consume después de que el resolvedor original haya producido una ruta.

## 5. Contratos reutilizados sin modificar

- Ruta de contenedor: `/private/var/mobile/Containers/Data/Application/<UUID>`.
- Bundle ID canónico: `PatchPathValidator.canonicalBundleIdentifier`.
- Raíz canónica: `PatchPathValidator.canonicalFileURL`.
- Validación de destino: `PatchPathValidator.resolveTargetURL` / `resolveContainedTargetURL`.
- Identidad: metadata MCM (`MCMMetadataIdentifier`) y fingerprint de `PatchTransaction`.
- Proveedor existente: `bad_query` sigue siendo el primero en las versiones verificadas por VINI.

## 6. Limitaciones conocidas del punto de conexión

- La extensión se verifica sobre la raíz resuelta (`R_OK|X_OK`, y `W_OK` para patches). No se crea un archivo de prueba dentro del contenedor.
- En iOS 26, `worse_query` alcanza contenedores individuales; no se asume que alcance los directorios padre de sistema. El escaneo conserva la enumeración por inodos y concede acceso por contenedor cuando hace falta.
- La disponibilidad real depende de un App Group autorizado por la firma. En este repositorio no existe ninguno (ver informe D).
