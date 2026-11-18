# Files: auditoría comparativa WQFiles + 3105

Fecha: 2026-11-18  
Base: PR #2, `790ec664a36b2c6e95719f383f293c8c942ead44`  
Fuente: `3105-WQFiles-source-bda9185.zip`, SHA-256
`9507F758C22E027B2D1EE225C3233FDA99478AF555E257396A5A56C7C707332E`

## Resultado del diagnóstico

PR #2 ya contiene Files funcional a nivel de arquitectura: MCM/bad_query para
identificadores y acceso, enumeración por inodo como fallback, lectura mediante
Foundation y operaciones de escritura en `FileManagerService`. WQFiles aporta
una enumeración incremental con invalidación, identidad por `device/inode`,
revalidación y APIs de acceso/lectura/escritura más estrictas.

Sin embargo, `WQAccess` no es una dependencia aislada: enlaza su propia ruta de
`worse_query`, el App Group firmado y utilidades de seguridad. Sustituir el
proveedor de PR #2 o copiar esa ruta requeriría modificar superficies protegidas
(`worse_query`, sandbox, entitlements/App Groups). Eso queda detenido hasta una
autorización explícita; no se simula una autorización que no esté demostrada.

## Tabla origen / destino

| Función | Origen 3105/WQFiles | Destino PR #2 | Dependencias | Problema | Evidencia | Riesgo | Prueba |
|---|---|---|---|---|---|---|---|
| Enumerar contenedores | `WQAccess.h/.m`: `wq_enumerate`, caché incremental y límite dinámico | `ContainerStore.enumerateDirectories`, `bad_query_list`, `containersFromFilesystem` | `worse_query`/bad_query existente; WQAccess además requiere WQCore y seguridad | PR #2 usa rango fijo y no invalida un inventario incremental | WQAccess documenta `wq_enumerate_invalidate`; PR #2 usa `maxInode=2_000_000` | Cambiarlo toca proveedor/escape y puede duplicar mecanismos | Simular contenedor A/B y refresh; después dispositivo |
| UUID vigente | `wq_item_identity` + revalidación `device/inode` y ruta | UUID del último componente en `isApplicationContainerPath`; no persiste identidad física | `stat` y validación de ruta | Una ruta recordada puede quedar obsoleta tras reinstalación | La evidencia del usuario observa UUID nuevo; PR #2 no compara identidad física | Asociar UUID antiguo con app nueva | Test A→B rechazando A; reinstalación real pendiente |
| Bundle ID → contenedor | `wq_container_label`, mapa LaunchServices y `wq_bundle_id_for_container` | `MCMActivateContainerPath`, metadata plist, candidatos de Saved State/Preferences | MCM existente; WQFiles requiere LaunchServices parser/provider | `worse_query` por sí solo no resuelve Bundle ID | `IOS2721_WQFILES_COMPARISON.md` lo confirma | Heurísticas pueden producir identidad incorrecta | Bundle ID confirmado por metadata + path UUID |
| Validar instalación | `wq_scan_verify`, `device/inode`, path y generación | `ContainerDiscoveryMerger` normaliza paths; no hay validación física equivalente | WQAccess/WQApps/WQScanTask | Caché puede conservar asociación vieja | Código WQFiles elimina rutas movidas/desaparecidas | Mostrar app desinstalada o cruzada | Ruta inexistente, inode cambiado, conflicto |
| Invalidar / refrescar | `wq_enumerate_invalidate`; generación en tareas asíncronas | `AppDataBrowserView.reload`; nueva enumeración, sin caché incremental WQFiles | UI existente | Refresh no fuerza el mismo ciclo de identidad WQFiles | WQAccess define invalidación manual | Resultados asíncronos antiguos | Refresh dos veces con UUID A→B |
| Abrir directorio | `wq_list`, `wq_stat`, descriptor sin symlinks | `FileManager.contentsOfDirectory` en `listFiles` | Proveedor de acceso actual | Errores se reducen a lista vacía | WQAccess distingue EACCES/EPERM y rutas peligrosas | Ocultar acceso denegado como vacío | Permiso denegado vs directorio inexistente |
| Leer archivo | `wq_read`, `wq_read_range`, `wq_open_for_reading` | `Data(contentsOf:)` en `readTextFile` | Acceso concedido previamente | No distingue lectura denegada, inexistente y binario en el contrato | WQAccess devuelve error explícito | Diagnóstico incorrecto | Texto, binario, inexistente, denegado |
| Escribir archivo | `wq_write_if_unchanged`, `wq_create_file`, backups y descriptor seguro | `FileManagerService` y operaciones existentes de Files | Backup/restore propios de VINI-IPA | WQFiles tiene controles de identidad; no debe duplicarse ni reemplazar transacciones | `WQAccess.h` exige versión/identidad para mutaciones | Tocar backup/journal/Protected Components | Solo temporal controlado; primero revisar contrato |
| Errores / permisos | `wq_permission_hint`, estados y `wq_log` | `FileManagerOperationError`, logs de `ContainerStore` | Localización y UI existentes | PR #2 no conserva todos los estados de descubrimiento | Auditoría 3105 separa `access_denied`, `read_failed`, `source_not_found` | Confundir inaccesible con desinstalada | Matriz de estados y proveedor ausente |

## Subconjunto candidato, pendiente de autorización

La única integración potencialmente mínima sería adaptar **identidad y
revalidación** al flujo de Files sin copiar `Vendor/WQFiles` completo: modelo de
identidad física, validación de UUID/path y estados explícitos. Aun así, cualquier
uso de `wq_grant`/`wq_enumerate` requiere revisar la dependencia protegida de
`worse_query`, App Group y entitlements.

No se autoriza todavía copiar `WQAccess.m`, `WQAccessSafety.h`, `WQCore`,
`WQCache`, `WQApps` ni el parser LaunchServices: sus dependencias y superficie de
acceso no están justificadas como reproducibles dentro de PR #2.

## Estado de validación

- HEAD PR #2: **confirmado**.
- Worktree nuevo desde ese HEAD: **confirmado**.
- ZIP y procedencia/hash: **confirmados**.
- Auditoría de funciones: **completada a nivel fuente**.
- Cambios funcionales: **no iniciados**.
- Compilación: **pendiente**.
- Pruebas simuladas: **pendiente de implementar**.
- iOS 27.2.1 físico, incluida reinstalación de `com.dts.freefireth`: **PENDIENTE**.

## Superficies protegidas no modificadas

No se modificaron Patches, `PatchTransaction`, journal, backup/restore/rollback,
`.3105`, `bad_query`, MHA-C2/MCM, `worse_query`, sandbox escape, identidad/rutas,
permisos, firma, entitlements, App Groups, login, JWT, Keychain, licencias ni
Cloudflare.
