# Matriz de paridad WQFiles / 3105

| Función WQFiles | Archivo | Dependencias | Equivalente 3105 | Estado | Evidencia |
|---|---|---|---|---|---|
| `wq_app_group` | `WQAccess.m` | SecTask, App Group URL, cache recovery | `WQAuthorizedAppGroup`, `containerURL` | Implementación parcialmente equivalente | `worse_query_adapter.m`, logs App Group |
| `wq_query_token` | `WQAccess.m` | MCM class 7, Caches swap, two flag sets | `worse_query` class 7, one flag set | Sustituida | `worse_query.m` lines 31–70 |
| `wq_grant` | `WQAccess.m` | LRU, lstat, effective open, retry | no public equivalent; coordinator providers | Implementación parcialmente equivalente | `ContainerAccessCoordinator.acquire` |
| `wq_reset_access_cache` | `WQAccess.m` | marker, lock, rename/recovery | ninguna | Omitida | no symbol/call in 3105 |
| `wq_list` / `wq_read` | `WQAccess.m` | grant retry, errno classification | FileManager/Data | Sustituida | `ContainerStore`, resolver |
| `wq_open_for_reading` / `wq_stat` | `WQAccess.m` | safe open, grant retry | `attributesOfItem`, `fileExists` | Implementación parcialmente equivalente | resolver/coordinator |
| `wq_enumerate` | `WQAccess.m` | fsgetpath, dynamic inode bound, scan cache | `bad_query_list`, MCM/API enumeration | Implementación parcialmente equivalente | `ContainerStore.enumerateDirectories` |
| `wq_system_areas_reachable` | `WQAccess.m` | OS capability decision | ninguna | Omitida | no equivalent call |
| `wq_enumerate_invalidate` | `WQAccess.m` | shared scan and LS miss reset | refreshes local lists only | Sustituida | no shared scan generation |
| `wq_container_label` | `WQAccess.m` | xattr, LS API, MCM classes, resolver, metadata | MCM path + metadata + candidate resolver | Implementación parcialmente equivalente | `ContainerStore.readContainerMetadata` |
| `wq_set_container_list_provider` | `WQAccess.m` | callback before enumeration | direct `ContainerStore` calls | Sustituida | no callback registration |
| `wq_set_container_label_resolver` | `WQAccess.m` | callback chain | direct parser/coordinator | Sustituida | no WQAccess label chain |
| `wq_find_ls_store` | `WQLaunchServices.m` | WQAccess list/stat/read, daemon scan | `wq_phase1_find_ls_store` | Implementación parcialmente equivalente | MCM class 10 + listable roots; no daemon scan |
| `wq_ls_read_stable` | `WQLaunchServices.m` | wq_read, stat before/after | `wq_phase1_ls_read_stable` | Implementación equivalente verificada | fixtures stable-read |
| `wq_parse_ls_store` | `WQLaunchServices.m` | bounded string/layout parser | `WQLaunchServicesPhase1` | Implementación equivalente verificada en fixtures | `Tests/WQLaunchServicesPhase1Tests.m` |
| `wq_display_name` | `WQLaunchServices.m` | loaded snapshot, fallback table/parent | `wq_phase1_display_name` | Implementación parcialmente equivalente | parser fixtures; device source unavailable |
| `wq_ls_container_paths` | `WQLaunchServices.m` | coherent snapshot, all paths | `wq_phase1_ls_container_paths` | Implementación parcialmente equivalente | no privileged source discovery |
| `wq_ls_bundle_containers` | `WQLaunchServices.m` | bundle path map | `wq_phase1_ls_bundle_containers` | Implementación equivalente en fixtures | no device evidence |
| `wq_health_run` | `WQHealth.m` | all preceding WQAccess/LS stages | `WQIdentityHealth` | Implementación parcialmente equivalente | stage logs; no WQAccess recovery |
| `wq_health_access_state` | `WQHealth.m` | sample counts | coordinator counts | Sustituida | no shared WQHealth enum |
| `wq_health_names_state` | `WQHealth.m` | names and labels | summary counters | Sustituida | `WQBundleIdentityCoordinator` |
| `WQApps.scan` | `WQApps.m` | enumerate, label, display name, cancellation | `AppDataBrowserView.reload` | Implementación parcialmente equivalente | different initialization/order |
| `wq_app_install_state` | `WQApps.m` | MCM install/offload metadata | none | Omitida | out of identity scope |
| `WQAppsSupportBundleIDValid` | `WQAppsSupport.h` | validation helper | `ContainerBundleCandidateResolver` | Sustituida | different helper and filters |
| `WQCache` measurement/purge | `WQCache.m`, `WQAccess.m` | wq_measure/purge, safe fd operations | no identity equivalent | Omitida | intentionally outside phase |
| `WQEditState`, `WQParseHex` | `WQCore.m` | editor/patch | none | Omitida | unrelated to identity |
| `bad_query` | 3105 `bad_query.c` | MCM class 13, fsgetpath, token consume | same source | Integrado sin prueba completa en dispositivo | prior 1/38 MHA candidates; access remains denied |
| `worse_query` | 3105 `worse_query.m` | MCM class 7, App Group Caches swap | same source | Integrado sin prueba completa en dispositivo | handle results not sufficient; effective open required |
| `MCMActivateContainerPath` | 3105 `mcm_bridge.m` | dynamic MCM symbols, activation, safe open | same source | Implementación parcialmente equivalente | activation result not propagated |
| `ContainerAccessCoordinator.acquire` | 3105 Swift | MHA, bad_query, worse_query, FileManager probe | no WQFiles direct equivalent | Dependiente de permisos efectivos | precheck and nil-bundle probe limit coverage |
| `WQFilesIdentityResolver.loadSnapshot` | 3105 Swift | direct roots, MCM path, parser | same role | Sustituida/parcial | no provider retry during source inventory |
| `WQBundleIdentityCoordinator` | 3105 Swift | phase1 report, existing resolver, health | no WQFiles single function | Integrado sin prueba completa en dispositivo | conflicts/additions logged |
| `WQIdentityHealth` | 3105 Swift | existing providers | WQHealth subset | Integrado sin prueba completa en dispositivo | controlled samples only |

No se encontró evidencia suficiente para afirmar que una función WQFiles de
edición/backup haya sido necesaria para Bundle ID recognition.

## Inventario público restante de `WQAccess.h`

Para evitar que “no relacionado con Bundle ID” oculte una operación de acceso,
se enumeran explícitamente las APIs restantes:

| Símbolos | Clasificación en 3105 | Razón |
|---|---|---|
| `wq_log`, `wq_log_text` | Omitida | 3105 usa su logger; no cambia autorización |
| `wq_file_version`, `wq_write*`, `wq_backup_local_copy`, `wq_create_file_from`, `wq_copy_to_local` | Omitida | mutación/backup, no identificación |
| `wq_permission_hint` | Omitida | explicación de permisos POSIX para edición |
| `wq_read_range` | Omitida | visor/editor de bytes |
| `wq_patch*` | Omitida | Patches de WQFiles; 3105 conserva su motor |
| `wq_create_file`, `wq_create_dir` | Omitida | operaciones de escritura |
| `wq_item_identity`, `wq_identity_for_stat` | Parcial | 3105 usa `stat`/metadata, no el contrato fd-relative de WQFiles |
| `wq_delete*`, `wq_is_protected_folder`, `wq_tree_count` | Omitida | delete/Recently Deleted |
| `wq_backup_unit_deletable`, `wq_delete_backup`, `wq_backup_root`, `wq_app_backup_root`, `wq_backup_original_path`, `wq_is_backup_storage_path` | Omitida | almacenamiento de backup |
| `wq_rename*`, `wq_move*` | Omitida | mutación de Files |
| `wq_measure_tree` | Omitida | Cache Cleaner/tamaño, depende de grants |
| `wq_purge_contents*` | Omitida | limpieza, depende de safe fd operations |
| `wq_copy_contents`, `wq_copy_tree_new` | Omitida | copia/restore, depende de grants |

El inventario confirma que estas funciones existen en WQFiles, pero ninguna se
ejecuta en el camino de reconocimiento de Bundle IDs de 3105. Su ausencia no se
presenta como compatibilidad parcial del parser; se clasifica como exclusión
funcional deliberada.

## Helpers privados de acceso inventariados

También se revisaron `wq_query`, `wq_release_handle`, `wq_grant_opens`,
`wq_open`, `wq_open_directory_flags`, `wq_volume_max_inode`,
`wq_scan_children`, `wq_scan_cache_load/save`, `wq_scan_verify`,
`wq_shared_scan_setup`, `wq_full_scan_acquire/end`,
`wq_label_identity/matches`, `wq_container_identifier_lookup` y las funciones
de recuperación `WQCacheSwapBegin/Recover/Reset`. No existe equivalente completo
en 3105; los equivalentes parciales están señalados en la matriz principal.
