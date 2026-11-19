# WQFiles 0.9.6 — reconocimiento completo de Bundle IDs

Rama experimental: `experiment/wqfiles-bundleid-complete`
Base: `experiment/wqfiles-launchservices` (`d394991`)

Este informe diferencia interpretación de datos, autorización efectiva y
funciones de edición. La presencia de una función equivalente no se considera
prueba de que el permiso funcione en el dispositivo.

## Flujo real reconstruido

1. `wq_health_run` comprueba `wq_app_group`.
2. Con el App Group disponible, `wq_enumerate` descubre los contenedores de
   datos. Su implementación usa `wq_grant`, `wq_list` y, cuando corresponde,
   el escaneo de inodos `fsgetpath`.
3. Para muestras, `wq_grant` + `wq_list` verifican acceso efectivo; un token
   emitido pero que no permite listar no cuenta como acceso.
4. `wq_load_display_names` carga la base de LaunchServices. El cargador busca
   el store recordado y, con la lista de contenedores habilitada, encuentra
   candidatos `com.apple.LaunchServices-*.csstore`, valida `bdsl`, tamaño,
   layout y estabilidad de `stat`.
5. El parser de `WQLaunchServices` produce nombres, Bundle IDs, rutas de
   contenedores de datos y rutas de contenedores `.app`. Las extensiones se
   mantienen separadas y las asociaciones conflictivas se descartan.
6. `wq_container_label` obtiene el identificador MCM del contenedor y usa como
   respaldo el resolver de LaunchServices instalado mediante
   `wq_set_container_label_resolver`.
7. `WQApps` combina `wq_container_label` con `wq_display_name`, publica solo
   identidades comprobadas y conserva el UUID cuando no hay identidad.
8. Si falla el acceso, la fuente o el layout, `WQHealth` deja el paso posterior
   como omitido/advertencia; no convierte un UUID en Bundle ID.

La recuperación de `WQAccess` incluye la reparación renombrando la caché de
tokens (`wq_reset_access_cache`) y la repetición de grants. Esa ruta depende de
la técnica `worse_query` y no se copia ni se ejecuta automáticamente desde esta
integración.

## Dependencias y matriz de equivalencia

| WQFiles / 3105 | Papel en la identificación | Estado experimental |
|---|---|---|
| `WQLaunchServices.m/.h` → carga, selección, parser, nombres | Fuente de identidades y nombres | Integrado y probado con fixtures; acceso de dispositivo pendiente |
| `WQAccess.wq_app_group` | Selección del App Group efectivo | Equivalente verificado por `WQAuthorizedAppGroup` + `containerURL` |
| `WQAccess.wq_grant`, `wq_list`, `wq_read`, `wq_open_for_reading` | Autorización y lectura real | Dependiente de permisos efectivos; adaptado al `ContainerAccessCoordinator` existente |
| `WQAccess.wq_enumerate` / escaneo inode | Descubrimiento cuando el listado normal falla | Parcial: 3105 conserva `bad_query_list`; no se añade otra ruta de escape |
| `WQAccess.wq_container_label` | Asociación UUID/identificador MCM | Parcial: MCM, metadata y resolvers existentes; diagnóstico separado |
| `WQAccess.wq_set_container_list_provider` | Permite que LaunchServices alimente el descubrimiento | Integrado conceptualmente mediante `ContainerStore.launchServicesStoreIdentifiers`; sin importar WQAccess global |
| `WQAccessSafety.h` | `/var` canónico, `openat` sin symlinks, `stat` estable | No requerido para interpretar; principios de identidad/estabilidad conservados |
| `WQHealth` | Orquestación y estados OK/skipped/warning/failed | Integrado como `WQIdentityHealth`, con operación, requisito, recurso y alternativa |
| `WQCache` | Limpieza de cachés | Pendiente por alcance: no interviene en publicación de identidad |
| `WQApps` | UI, backup/restore, iconos, publicación | Solo el contrato de identidad se reproduce; edición/backup/restore no se integran |
| `WQCore` | Hex/editor state y validación de patches | Incompatible con esta fase; no interviene en Bundle IDs |
| `WQFilesIdentityResolver.swift` | Resolver comparable de 3105 | Conservado; se compara y su identidad verificada tiene prioridad |
| `ContainerStore.swift` | MCM/API/MHA, metadata, UUID y candidatos | Integrado como proveedor existente |
| `ContainerAccessCoordinator.swift` | MHA-C2, `bad_query`, `worse_query`, prueba efectiva | Integrado como adaptador de autorización; no se reemplaza |
| `ContainerIdentityResolver.swift` | Fallback y metadata | Conservado; UUID fallback no se eleva a Bundle ID |
| `FileManagerService.swift` | Operaciones de Files | No modificado; no participa en reconocimiento |
| `worse_query.m/.h` y adapter | Proveedor privilegiado ya existente | Dependiente de autorización; se mide, no se amplía |
| `mcm_bridge.m` | rutas/clases MCM y activación | Integrado y reutilizado |

## Implementación integrada

`WQLaunchServicesPhase1` ahora distingue `not_found`, `unavailable`,
`located_unreadable`, `incompatible` y `valid`; no trata una ruta recordada
como lectura exitosa. La selección compara candidatos regulares por metadatos,
valida encabezado/layout y lee de forma estable.

`WQBundleIdentityCoordinator` compara el parser adaptado con
`WQFilesIdentityResolver`, elimina IDs inválidos, separa contenedores de datos
de extensiones/grupos/daemons, rechaza conflictos y solo añade una identidad si
el UUID fue descubierto por 3105 y existe un nombre verificado. Nunca inventa
un nombre sustituyendo el Bundle ID.

`WQIdentityHealth` ejecuta una muestra de hasta ocho contenedores mediante los
proveedores ya presentes en `ContainerAccessCoordinator`. Registra el proveedor
que consiguió apertura efectiva o el dominio/código del fallo, sin registrar
paths completos, tokens ni contenidos. Para el store, distingue lectura directa,
reintento autorizado, archivo ausente y autorización no intentada.

## Diagnóstico por etapa

Los eventos `wq.identity.stage` contienen:

- componente y operación concreta;
- requisito esperado y clase de recurso;
- resultado (`success`, `failed`, `not_attempted`);
- alternativa autorizada o razón por la que no existe.

Además se registran App Group, contenedores, bytes del store, layout, registros,
Bundle IDs, UUID asociados, nombres, coincidencias y conflictos. No se registra
contenido privado ni tokens.

## Fixtures y pruebas

`Tests/WQLaunchServicesPhase1Tests.m` cubre cabecera inválida, lectura estable,
persistencia y reintento de ubicación, layouts de iOS 26/27, Unicode, registros
truncados, duplicados, asociaciones ambiguas, extensiones, contenedores `.app`,
layout desconocido, caché y stores sobredimensionados. Son pruebas portables de
interpretación; no sustituyen la prueba de autorización en iPhone.

## Divergencia verificable en iPhone14,3 / iOS 27.2.1 (24B156)

La evidencia disponible antes de esta ampliación fue: App Group utilizable,
267 contenedores detectados, 0 fuentes CSStore2 legibles, 0 nuevas identidades y
MHA-C2 con 1/38 candidatos. Por tanto, el bloqueo observado está entre
descubrimiento/lectura autorizada de la fuente y el parser; no existe evidencia
de fallo del layout con bytes reales del dispositivo.

La nueva build debe reportar si `MHA-C2`, `bad_query` o `worse_query` consigue
acceso efectivo a los contenedores muestreados y si alguno consigue leer el
directorio del store. Hasta esa prueba, la compatibilidad con WQFiles 0.9.6 es
parcial y no debe declararse total.

No se integran `WQCache` (limpieza), `WQApps` (backup/restore), edición,
restauración ni nuevos mecanismos de escape. Patches, Apply/Restore, `.3105`,
firma, navegación, App Group y los proveedores existentes permanecen intactos.
