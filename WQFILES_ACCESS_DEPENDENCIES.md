# Dependencias completas del sistema de acceso WQFiles

## Grafo de ejecución relevante

```text
wq_health_run
 ├─ wq_app_group
 │   ├─ SecTaskCreateFromSelf / SecTaskCopyValueForEntitlement
 │   ├─ containerURLForSecurityApplicationGroupIdentifier
 │   └─ WQRecoverCacheSwapAtPath
 ├─ wq_enumerate
 │   ├─ wq_stat / statfs
 │   ├─ wq_shared_children
 │   │   ├─ wq_volume_max_inode
 │   │   ├─ fsgetpath
 │   │   ├─ persistent scan cache
 │   │   └─ cancellation/progress/full-scan gate
 │   └─ optional gContainerListProvider
 ├─ wq_grant + wq_list
 │   ├─ wq_query
 │   │   ├─ libsystem_containermanager.dylib
 │   │   ├─ container_query_* symbols
 │   │   ├─ container_copy_sandbox_token
 │   │   ├─ sandbox_extension_consume/release
 │   │   └─ WQCacheSwapBegin/Recover
 │   └─ effective open test + alternate flags
 ├─ wq_load_display_names / wq_find_ls_store
 │   ├─ wq_list / wq_read / wq_stat
 │   ├─ wq_enumerate(InternalDaemon)
 │   └─ wq_parse_ls_store
 └─ wq_container_label
     ├─ getxattr + wq_grant retry
     ├─ LaunchServices API cache
     ├─ ContainerManager classes
     ├─ gContainerLabelResolver
     └─ metadata plist via wq_read
```

## Dependencias de autorización

| Dependencia | WQFiles | 3105 | Resultado de auditoría |
|---|---|---|---|
| App Group firmado y utilizable | `wq_app_group` | `WQAuthorizedAppGroup` + entitlements experimentales | Disponible solo en build instalada con firma válida; IPA CI no lo prueba |
| ContainerManager | carga dinámica de `libsystem_containermanager.dylib` | `mcm_bridge.m` y `worse_query.m` | Presente, con subconjunto distinto de símbolos/flags |
| Sandbox extension | `container_copy_sandbox_token` + consume/release | `bad_query`/`worse_query_adapter` | Dependiente del sistema; no equivalente completo |
| Cache swap | `WQAccessSafety.h` + marker/lock/recovery | solo lógica interna de `worse_query` | Recuperación WQFiles ausente |
| Effective open | `wq_grant_opens` | `verifyEffectiveAccess` | Parcial; el precheck puede impedir llegar al proveedor |
| Inode discovery | `fsgetpath` dinámico y cacheado | `bad_query_list` con límite fijo | Parcial y potencialmente incompleto |
| LS API | `LSApplicationWorkspace` | no usado en identificación | Omitido |
| MCM labels | clases múltiples y cache inode-bound | consultas MCM de paths/identifiers | Parcial |

## Archivos transitivos descubiertos

`WQAccess.m` importa `WQCore.h`, `WQAccessSafety.h`, `WQLocalization.h`,
`dlfcn`, `dirent`, `xpc`, `fsgetpath`, `sys/mount` y xattrs. `WQHealth.m`
añade `WQAppsSupport.h` y `WQLaunchServices.h`. `WQApps.m` además depende de
`WQDir`, `WQUI`, `WQSharing`, `WQArchive`, `WQAccess`, `WQLaunchServices`,
`WQHealth` y `WQCore`; esos módulos explican el flujo de Apps, pero backup,
restore y UI no son necesarios para publicar una identidad.

La auditoría también encontró `WQCacheSafety.h`, usado por la implementación
de Cache Cleaner junto con `WQAccessSafety.h`. Aporta validación de roots,
locks y operaciones seguras de limpieza; no se debe confundir con el parser de
LaunchServices.

## Ciclo de vida de recursos

WQFiles mantiene handles en un LRU de 192 entradas y libera el más antiguo;
libera query objects, XPC objects, tokens, descriptors, locks y leases en cada
ruta de error. El scan compartido tiene owner, TTL, cancelación y generación.

3105 libera handles `bad_query`/`worse_query` en `ContainerAccessSession.deinit`
y libera objetos en `mcm_bridge`, pero no tiene LRU de grants, no mantiene una
sesión de acceso para la enumeración de LaunchServices y no tiene generación
compartida para scans de inode. `MCMRetainedLease` queda retenido globalmente
por clase/identificador; su activación se intenta, pero el resultado booleano no
se propaga al path caller.

## Dependencias no autorizadas o no verificadas

WQFiles depende de APIs privadas y de una técnica de sandbox extension. Su
arquitectura se documenta aquí para explicar la divergencia; esta rama no copia
ni amplía esa técnica. La disponibilidad de símbolos en un binario no demuestra
autorización del daemon ni apertura efectiva.

La referencia usa el App Group `group.cz.kolbi.wqfiles`; 3105 usa
`group.pigtjing.top` en la configuración experimental. No son intercambiables.
La identidad `com.apple.mobile.MobileHouseArrest` se conserva como Bundle ID
del host para el puente MCM.
