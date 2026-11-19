# Auditoría retrospectiva de omisiones de sandbox y acceso

Rama: `experiment/wqfiles-sandbox-completeness-audit`
Base auditada: `54d787a` (`experiment/wqfiles-bundleid-complete`)

## Alcance y evidencia

Se compararon los commits `616899c`, `afa5a48`, `cf0f0fb`, `d394991`,
`983fdf7` y `54d787a` con la copia de referencia WQFiles 0.9.6 (commit
`bb81069401875a470a032830b8e6bc934fbd9146` según los informes previos). Se
inspeccionaron también los archivos de configuración, entitlements y bridging
headers. Esta auditoría no activa código nuevo de evasión.

## Omisiones confirmadas

### `WQAccess.m/.h`

No se incorporó el módulo. Las omisiones relevantes para identificación son:

- `wq_grant`: caché LRU de hasta 192 extensiones, selección de flags y prueba
  de que el token realmente abre el objetivo.
- `wq_query`: intercambio seguro de `Library/Caches`, consulta de
  ContainerManager clase 7, copia/consumo del token y recuperación del swap.
- Segundo intento con flags alternativos: WQFiles prueba primero el conjunto
  dependiente de iOS y luego el otro si el token no abre el objetivo. El
  adaptador 3105 invoca `worse_query(..., alt_flags=false, ...)` solamente.
- `wq_list`, `wq_read`, `wq_open_for_reading` y `wq_stat`: reintento después de
  denegación. 3105 usa `FileManager`, `Data(contentsOf:)` y `attributesOfItem`.
- `wq_enumerate`: cálculo dinámico del límite de inode, `fsgetpath`, cuatro
  trabajadores, cancelación, progreso, cache persistente, TTL de diez minutos,
  escaneo semanal y verificación de identidad inode. 3105 conserva
  `bad_query_list(path, 2_000_000)`, un rango fijo y sin ese ciclo de vida.
- `wq_system_areas_reachable`: diferencia de capacidades entre iOS 26 y 27 no
  existe como proveedor equivalente en 3105.
- `wq_container_label`: xattr, cache de etiquetas de LaunchServices, consulta
  de ContainerManager en clases `{0,2,5,7,8,10,11,13}`, validación device/inode,
  resolver LaunchServices y metadata plist. 3105 tiene piezas separadas de MCM
  y metadata, pero no el mismo orden ni cache de etiquetas.
- `wq_set_container_list_provider` y `wq_set_container_label_resolver`: no se
  registran callbacks en una inicialización común de WQAccess.
- `wq_reset_access_cache`: recuperación de swaps interrumpidos en la caché del
  App Group no existe en 3105.

Las funciones de escritura, backup, delete, move, patch y purge también fueron
omitidas, intencionadamente, pero no son necesarias para reconocer Bundle IDs.

### `WQAccessSafety.h`

No se incorporó como archivo. Se omitieron `WQSameObject`, apertura de
directorios sin symlinks, `WQOpenRegularAt`, fsync, recuperación de marker/cache
swap, gramática absoluta de paths y creación de directorios sin enlaces. Las
comprobaciones `stat`/mtime del parser son equivalentes solo para lectura del
store; no cubren el ciclo de vida de tokens ni la seguridad fd-relativa de
WQAccess.

### Descubrimiento de LaunchServices

`WQLaunchServicesPhase1` adaptó el parser y la ruta recordada, pero no reproduce:

- la búsqueda de todos los `InternalDaemon` mediante `wq_enumerate` autorizado;
- la selección de `LSApplicationWorkspace` (`defaultWorkspace`,
  `allInstalledApplications`, `dataContainerURL`, `plugInKitPlugins`);
- la consulta de ContainerManager por todas las clases;
- el registro de proveedores WQAccess antes del scan.

La fase nueva busca el contenedor MCM clase 10 y roots que `FileManager` pueda
listar. Eso es una simplificación de disponibilidad, no del parser.

### `WQHealth.m`

`WQIdentityHealth` cubre diagnóstico de App Group, muestra de contenedores,
acceso efectivo y fuente, pero no reproduce `wq_health_run` completamente:

- no usa `wq_app_group` con recuperación de cache;
- no distingue estados globales `OK/Skipped/Warning/Failed` como objeto de health;
- no ejecuta el muestreo WQFiles con `wq_grant` + `wq_list` + `wq_container_label`;
- no prueba accesibilidad de app bundles (`wq_ls_bundle_containers`);
- no carga nombres antes del muestreo de etiquetas;
- no conserva un health result reutilizable por Apps/Cache Cleaner.

### `WQApps.m` y `WQAppsSupport.h`

El flujo de Apps no se integró. Por tanto no se incorporaron la cancelación y
progreso de scan, `wq_container_label` como fuente primaria, estado de
instalación/offload, medición de tamaño, evaluación de acceso/identidad, ni la
publicación coordinada de nombre y Bundle ID. Las validaciones de Bundle ID de
`WQAppsSupport.h` tampoco son una dependencia compartida de 3105; el resolver
usa `ContainerBundleCandidateResolver` y filtros propios.

Las funciones de backup/restore, journal, hashes, rollback e iconos se omiten
por alcance y no deben confundirse con la identificación.

### `WQCache.m/.h`

No aporta un parser de identidad, pero sí depende de acceso WQFiles: usa
`wq_measure_tree`, `wq_purge_contents_cancellable`, cancelación, validación de
device/inode y paths seguros. Se omitió completo; la omisión es correcta para
esta fase, pero demuestra que “no es parser” no significa “sin dependencia de
acceso” para la funcionalidad de Cache Cleaner.

La dependencia adicional `WQCacheSafety.h` también quedó fuera: sus helpers de
validación de roots, locks y recuperación de Caches sirven para limpieza, no
para asociar UUID con Bundle ID.

### `WQCore.m/.h`

`WQEditState`, `WQParseHex`, límites de hex y validación de rangos pertenecen a
edición/patch. No participan en reconocimiento de Bundle IDs. Su exclusión es
intencional y no se considera una omisión del flujo de identificación.

## Sustituciones que pueden cambiar el resultado

1. `wq_grant` fue sustituido por `ContainerAccessCoordinator`, pero este hace
   `FileManager.fileExists` antes de intentar MHA-C2, `bad_query` o
   `worse_query`. Si el sandbox oculta el path, el proveedor no se intenta.
2. El probe de `WQIdentityHealth` pasa `bundleID: nil`, por lo que el camino
   MHA-C2 no se ejecuta en esa muestra; solo se prueban `bad_query` y
   `worse_query` después del precheck.
3. La lectura de CSStore2 usa `FileManager`/`Data` y solo reintenta un padre
   mediante el coordinador después de que la fuente ya fue localizada. No puede
   descubrir una fuente dentro de un root que nunca fue listable.
4. `MCMActivateContainerPath` conserva leases, pero ignora el booleano de
   activación antes de abrir el root. El path retornado no demuestra que la
   extensión haya sido activada.
5. `worse_query_adapter` solo usa flags estándar y selecciona el primer App
   Group autorizado; WQFiles recuerda qué flags abrieron efectivamente el
   objetivo.

## No hay evidencia de estas supuestas omisiones

No se encontró una condición de compilación que desactive accidentalmente un
componente de acceso en 3105. Las exclusiones de WQAccess/WQApps/WQCache están
respaldadas por los commits e informes como decisiones de alcance y seguridad.
No existe evidencia de que una función completa de WQFiles haya sido copiada y
quedara sin llamadas; las funciones equivalentes actuales son adaptaciones
distintas y deben clasificarse como parciales.
