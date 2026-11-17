# Fase 0 — Auditoría de integración VINI / worse_query

## A. Resumen
Auditoría de solo lectura de VINI-IPA en `df99bf2fbb32b86966990077864a9d355271197b` y worse_query en `d1540e20cd82b974d891e0551ced6d6aeb570ac2`. Se identificaron fuentes de descubrimiento, flujo de patches, API nativa, configuración de Xcode y restricciones de firma. No se ha probado acceso en dispositivo.

## B. Estado inicial
- Rama: `feature/vini-native-worse-query`, creada exactamente desde el commit base anterior.
- Proyecto principal: `ThreeOneOSFive.xcodeproj`, target/scheme `3105`, deployment target iOS 16.0, bridging header `ThreeOneOSFive/ThreeOneOSFive-Bridging-Header.h`.
- Bundle ID del target VINI: `com.apple.mobile.MobileHouseArrest`. `CODE_SIGN_ENTITLEMENTS = ""` en Debug y Release. No se cambiarán estos valores.
- Workflows existentes: `.github/workflows/main.yml` (build macOS, scheme 3105, firma desactivada, artefacto .app) y `.github/workflows/fix-login-files.yml` (manual). Ninguno se reemplazará.
- worse_query: Objective-C en `worse_query.m/.h`, enumeración auxiliar en `pathleak.m/.h`, vistas Swift y recursos de PoC, proyecto Xcode propio y GPL-3.0. Su target declara `group.cc.forcequit.worse-query` en su entitlement y `cc.forcequit.worse-query` como Bundle ID. Se conservarán como referencia, sin sustituir los de VINI.

## C. Arquitectura vigente y puntos de integración
### Files
`AppDataBrowserView.reload()` (líneas 266–375) combina:
1. Catálogo de metadatos de bundles y API de aplicaciones instaladas.
2. Identificadores y rutas de MCM clase 2.
3. Enumeración de contenedores por sistema de archivos.
4. Identificadores LaunchServices, candidatos MHA y nombres inferidos.
5. `ContainerDiscoveryMerger` y `AppDataCatalogMerger`, con resultados preliminares, progresivos y finales.
El resultado reside actualmente en el estado `apps` de la vista. `FilesTabSwitcherView` y `FilesTabControls` gestionan pestañas, no el catálogo de aplicaciones. La conexión mínima es publicar las instantáneas de `apps` en un catálogo compartido, sin cambiar las fuentes ni los mergers.

### Patches
`DevicePatchService.withResolvedContainers` solicita `ContainerStore.resolveAppContainerPath(bundleID:)` por cada Bundle ID y pasa raíces a `PatchTransaction`. `ContainerStore` intenta MCM y luego un escaneo actual de metadatos de contenedores; no consume la instantánea de Files. `PatchManager` coordina patches remotos y no es el resolvedor de contenedores. La conexión debe mostrar Bundle IDs actuales de Files en la interfaz de proyectos y resolver de nuevo al operar, sin confiar en un UUID en caché ni modificar `PatchTransaction`.

### worse_query
La API original es `int64_t worse_query(NSString *, NSString *, bool, bool)` y `void worse_query_release(int64_t)`. El código obtiene el directorio del App Group, configura una consulta de contenedor y una extensión de sandbox, limpia su enlace temporal y devuelve un handle o error negativo. `pathleak` es una API auxiliar de enumeración. La PoC requiere un App Group autorizado y operativo; conservar su entitlement de referencia no concede ese grupo al ejecutable VINI. Un adaptador externo podrá invocar la API original, conservar el handle hasta completar la operación y liberarlo con la función original. No se debe activar por coincidencia superficial de versión.

## D. Recursos preservados
En esta fase no se cambió código de worse_query ni de los motores VINI; Files, Patches, `PatchTransaction`, entitlements, App Groups, Bundle ID, login, licencias, tokens, backups y restauración permanecen en el baseline. Solo se añade este informe.

## E. Integridad
Los SHA de commits fijan las fuentes. Aún no se han incorporado archivos ni comparado hashes SHA-256; esa comparación corresponde a la Fase 1. No se declara integridad de una copia inexistente.

## F. Compilación
Workflow aún no ejecutado para esta rama. El workflow original usa `macos-latest`, `xcodebuild -project ThreeOneOSFive.xcodeproj -scheme 3105 -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`. No verifica el proveedor nuevo. Sin URL de ejecución ni artefacto de integración.

## G. Pruebas
- Estáticas: lectura de árbol, componentes y configuraciones indicada arriba.
- Unitarias, integración, compilación y dispositivo: pendientes.

## H. Riesgos y requisitos
- Firma: `worse_query` necesita un App Group propio accesible; VINI no declara un archivo de entitlements en el proyecto. La PoC no debe integrarse con el grupo de un tercero ni alterar silenciosamente la identidad o permisos de VINI. Si el aprovisionamiento autorizado no permite el grupo necesario, la adquisición real queda bloqueada aunque el código compile.
- Compatibilidad: el README upstream anuncia iOS 26.0–26.7.2 / 27.2. Se requiere prueba de dispositivo; el deployment target iOS 16.0 no demuestra compatibilidad del mecanismo.
- Integridad: la fuente upstream está bajo GPL-3.0; conservar licencia y avisos, y revisar las obligaciones de redistribución antes de publicar binarios.
- Estado: las actualizaciones progresivas de Files deben invalidar rutas antiguas al reinstalar; descubrimiento y acceso deben representarse por separado.
- El código original de worse_query puede tener efectos sobre el directorio Caches del App Group; el adaptador debe acotar su uso y gestionar el ciclo de vida del handle.

## I. Plan de conexión mínima
1. Copiar íntegramente el árbol upstream desde el SHA fijado y generar/comparar SHA-256.
2. Añadir sus archivos Objective-C originales al target VINI, manteniendo las vistas PoC solo como referencia, y exponer el header en el bridging header de VINI.
3. Crear un adaptador externo y añadir worse_query como proveedor opcional sin cambiar los motores actuales ni sus prioridades.
4. Publicar las instantáneas de Files en una fuente compartida; Patches consumirá Bundle IDs actuales y resolverá la ruta de nuevo durante cada operación. Conservar validaciones y `PatchTransaction`.
5. Añadir workflow independiente de macOS para comprobaciones de integridad, build arm64 y artefactos; ejecutar y corregir únicamente fallos de integración.
6. Comparar con baseline y documentar explícitamente lo no probado en dispositivo.

## Estado
**Completada como auditoría estática; integración y validación funcional pendientes.**
