# Plan incremental posterior a la auditoría

Este plan no autoriza una nueva técnica de evasión. Cada paso requiere evidencia
real y puede terminar en “no reproducible con los permisos actuales”.

## Paso 1 — instrumentación segura de providers

- Separar `path_missing`, `sandbox_denied`, `provider_failed` y
  `effective_open_failed`.
- Eliminar el falso negativo causado por `fileExists` previo solo si el path
  fue obtenido por un proveedor autorizado y la operación sigue siendo de
  lectura.
- Pasar Bundle ID conocido al health probe para medir MHA-C2 por separado.
- Registrar disponibilidad de símbolos, clase/operación abstracta y códigos,
  nunca tokens ni paths completos.

## Paso 2 — lifecycle de acceso

- Evaluar un adaptador limitado de sesión con retención/liberación explícita,
  equivalente al lifecycle observable de WQFiles.
- Añadir pruebas de doble liberación, error después de adquisición y cierre de
  sesión antes/después de la lectura.
- No copiar `WQAccess.m` completo ni `WQAccessSafety.h` hasta demostrar que cada
  helper es necesario y legal para la build.

## Paso 3 — descubrimiento autorizado de fuente

- Comparar, en un dispositivo autorizado, MCM clase 10, ruta persistida y
  cualquier lista entregada por el sistema.
- Solo si una API ya disponible devuelve una ruta, adaptarla como provider de
  `WQLaunchServicesPhase1`.
- No iniciar el escaneo privado completo de `InternalDaemon` desde 3105 sin
  autorización explícita y prueba de que el mecanismo existente está permitido.

## Paso 4 — equivalencia de labels y nombres

- Medir xattr, metadata, MCM identifier, LaunchServices API y CSStore2 por
  separado.
- Añadir cache ligada a `(device,inode)` únicamente para resultados obtenidos
  de forma autorizada.
- Mantener separadas app, extensión, grupo compartido y daemon.

## Paso 5 — pruebas controladas

- Fixture local CSStore2: header, layouts 26/27, corrupción, duplicados,
  conflicto y estabilidad.
- App Group propio firmado: creación/lectura/listado y recuperación de cache
  local.
- Provider mocks solo en tests portables, nunca como evidencia de dispositivo.
- Prueba de recurso: cada handle/lease/query debe liberarse en éxito y error.

## Criterio de parada

Si el dispositivo devuelve `access_denied` antes de localizar una fuente, no se
integra el parser en ese camino ni se declara paridad. El resultado debe ser
“dependencia ausente o autorización no demostrada”, con el contador y la etapa
exacta.
