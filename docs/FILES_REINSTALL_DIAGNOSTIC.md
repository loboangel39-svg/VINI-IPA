# Files — diagnóstico de reinstalación

## Procedencia verificada

La rama contiene el commit `f72c1888110003962a3d069c94ab195326ab3759`.
La ejecución de Actions `44422632210` terminó correctamente con ese mismo
`headSha`; el artefacto fue generado desde esa revisión. Esto verifica la
procedencia de compilación, no la instalación física ni su ejecución en el
iPhone.

## Tabla inicial — antes de nuevos registros del dispositivo

Los conteos físicos y la aparición de `com.dts.freefireth` no están disponibles
en los logs entregados. Por tanto se marcan como **PENDIENTE**, no se infieren.

| Fuente | Función | Candidatos | Identidades resueltas | Descartes | Motivo | Punto de `com.dts.freefireth` |
|---|---|---:|---:|---:|---|---|
| API instalada | `ContainerStore.installedAppsFromAPI` | PENDIENTE | PENDIENTE | PENDIENTE | ruta ausente, inválida, inexistente o MCM no resuelve | PENDIENTE |
| MCM clase 2 | `dynamicAppIdentifiers` + `installedAppsFromMCM` | PENDIENTE | PENDIENTE | PENDIENTE | `MCMActivateContainerPath` falla | PENDIENTE |
| Sistema de archivos | `containersFromFilesystem` | PENDIENTE | UUID solamente; Bundle ID PENDIENTE | PENDIENTE | identidad física missing/replaced/invalid | PENDIENTE |
| LaunchServices/MHA | `launchServicesStoreIdentifiers` + `installedAppsFromMHACandidates` | PENDIENTE | PENDIENTE | PENDIENTE | catálogo vacío, MCM sin ruta | PENDIENTE |
| Inferencia | `inferUnidentifiedApps` | PENDIENTE | PENDIENTE | PENDIENTE | metadata/candidatos no confirmados | PENDIENTE |
| Merge/presentación | `ContainerDiscoveryMerger`, `AppDataCatalogMerger`, `ContainerPresentationPolicy` | PENDIENTE | PENDIENTE | PENDIENTE | UUID desconocido no se presenta | PENDIENTE |

## Instrumentación añadida

Solo se añadieron logs de conteo y estado, sin contenido de archivos, tokens ni
datos privados:

- `files-diagnostic source=api`
- `files-diagnostic source=mcm`
- `files-diagnostic source=filesystem`
- `files-diagnostic stage=preliminary`
- `files-diagnostic stage=inference`
- `files-diagnostic stage=final`

Los estados de filesystem distinguen `discardedMissing`, `discardedReplaced` y
`discardedInvalid`. La UI distingue `hiddenUnknown` de candidatos presentados.

## Comparación WQFiles + 3105

WQFiles separa enumeración incremental, validación de identidad, publicación por
generación y resolución Bundle ID/ruta mediante LaunchServices. PR #2 combina API,
MCM, enumeración por inodo, candidatos de estado/preferencias y filtros de
presentación. La evidencia actual no permite afirmar cuál fuente omite la
aplicación; se necesita el bloque de logs del refresh del iPhone.

## Estado

- Causa: **no identificada**.
- Corrección funcional: **no aplicada**.
- Cambios de esta fase: **solo instrumentación diagnóstica**.
- Patches y mecanismos protegidos: **sin cambios**.
