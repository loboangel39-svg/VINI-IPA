# Fase 3 — Corrección de descubrimiento compartido, modelo 2

## A. Situación anterior
En `0873306de347d7245bd9bbee6d43e1348348d19e`, `AppDataBrowserView.reload()` ejecutaba toda la coordinación de descubrimiento y publicaba sus resultados en `DiscoveredAppCatalog`. `PatchProjectEditorView` solo leía ese catálogo; sin abrir Files, Patches podía encontrarlo vacío. Un refresh de Files era la única forma de volver a ejecutar las fuentes. El catálogo tenía valor como observador de identidades y estados, pero no era un motor de descubrimiento.

## B. Arquitectura nueva
`SharedApplicationDiscoveryService.shared.discover(requester:forceRefresh:onUpdate:)` es ahora el único punto de entrada de coordinación. Files llama con `forceRefresh: true` para su refresh. Patches llama al entrar con `forceRefresh: false` y ofrece refresh explícito con `true`; el editor también puede solicitarlo directamente. El servicio ejecuta la secuencia original fuera del hilo principal, publica resultados preliminares, progresivos y finales en `DiscoveredAppCatalog`, y entrega las mismas etapas a Files. Un `NSLock` agrupa solicitudes simultáneas en un único escaneo; una caché de 60 segundos evita repetir inmediatamente un escaneo terminado, pero el refresh explícito siempre consulta las fuentes. El catálogo no ejecuta ninguna enumeración.

## C. Funciones originales reutilizadas
La coordinación extraída desde `AppDataBrowserView.reload()` conserva este orden:
1. `ContainerStore.applicationBundleMetadataCatalog()`.
2. `installedAppsFromAPI()` y `applyingBundleMetadata`.
3. `dynamicAppIdentifiers()` e `installedAppsFromMCM()`.
4. `containersFromFilesystem()` y `ContainerDiscoveryMerger.merge`, con resultado preliminar.
5. `launchServicesStoreIdentifiers()`.
6. `MHAIdentifierCatalog.identifiers(dynamic:installed:research:custom:launchServices:)`.
7. `installedAppsFromMHACandidates(...progress:)` y `AppDataCatalogMerger.merge`, con resultados progresivos.
8. `inferUnidentifiedApps` para contenedores de filesystem aún no asociados.
9. `AppDataCatalogMerger.merge` final, `ContainerPresentationPolicy.shouldShow` y orden por nombre.
Las implementaciones de las fuentes, los mergers y sus grants siguen en `ContainerStore.swift` y `ContainerBrowserLogic.swift`; no se copiaron para Patches. El servicio publica en main queue y realiza el trabajo de fuentes en una cola global. El contenido de las rutas de contenedores no se utiliza desde el catálogo para aplicar patches.

## D. Modificaciones
- `ThreeOneOSFive/helpers/SharedApplicationDiscoveryService.swift` (nuevo): concentra la secuencia original, coalescencia, caché de resultados, publicación y logs de conteos. Riesgo: un escaneo lento retrasa a ambos consumidores; las solicitudes se unen al mismo escaneo.
- `ThreeOneOSFive/views/AppDataBrowserView.swift`: `reload()` pasa a llamar al servicio y conserva sus estados de carga, progreso, vacío y refresh. Ya no coordina directamente las fuentes.
- `ThreeOneOSFive/views/PatchProjectsView.swift`: solicita descubrimiento al entrar y añade refresh explícito sin bloquear la vista.
- `ThreeOneOSFive/views/PatchProjectEditorView.swift`: permite refresh dentro del editor y puede iniciar descubrimiento si se presenta directamente y no hay identidades.
- `ThreeOneOSFive.xcodeproj/project.pbxproj`: registra el servicio en el target 3105.
`DiscoveredAppCatalog.swift` y `DevicePatchService.swift` no se modificaron para esta corrección. Patches sigue resolviendo la ruta vigente por Bundle ID antes de cada operación; `PatchTransaction` permanece intacto.

## E. Integridad
Origen worse_query `d1540e20cd82b974d891e0551ced6d6aeb570ac2`: 17/17 blobs originales siguen idénticos en la rama. El manifiesto `worse_query.sha256` fue comprobado por [Actions sobre el commit anterior](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44159957931). Comparación baseline VINI `df99bf2fbb32b86966990077864a9d355271197b` → `097849a8e00de6856a0355c762b57aa0001a0dfd`: cero cambios en `Info.plist`, autenticación, bad_query, `PatchTransaction`, assets y Cloudflare. No se cambiaron entitlements, App Groups, Bundle ID, licencias, tokens, backups ni restauración.

## F. Comparación funcional
Antes: Files ejecutaba API, MCM, filesystem, LaunchServices, MHA e inferencia; Patches dependía de la instantánea publicada por Files.
Ahora: el mismo bloque de coordinación, con esas fuentes y el mismo orden de merges y filtros, reside en un servicio al que llaman Files y Patches. Las etapas preliminar, progresiva y final continúan llegando a Files. Patches puede iniciar un escaneo sin abrir Files y forzar una actualización aun con caché no vacía. El servicio no ejecuta escaneos simultáneos idénticos. Esta equivalencia se ha verificado por comparación estática del flujo; la igualdad de resultados reales en iPhone permanece pendiente.

## G. Compilación
- Commit de código: [`097849a8`](https://github.com/loboangel39-svg/VINI-IPA/commit/097849a8e00de6856a0355c762b57aa0001a0dfd).
- [Workflow de integración sobre la cabeza nueva](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44162180980): en cola al redactar; resultado y errores pendientes.
- [Workflow anterior](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44159957931) sobre `0873306d`: éxito, incluido build arm64, integridad y [artefacto IPA unsigned](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44159957931/artifacts/14363278059). Este resultado no valida aún el código del modelo 2.

## H. Pruebas
- Estáticas: inspección de fuentes, orden, callbacks, coalescencia y diff protegido completados.
- Automatizadas: integridad y build del commit anterior completados; build de `097849a8` pendiente. No existe target unitario en el proyecto.
- Files, Patches sin abrir Files, simultaneidad, refresh, reinstalación y aplicación/restauración reales en dispositivo: pendientes. No se declaran éxitos simulados.

## I. Pendientes
Revisar logs del build de la cabeza actual, corregir solo fallos de integración y repetir. Ejecutar pruebas en dispositivo autorizado, especialmente identidad de contenedor tras reinstalación. La caché de 60 segundos puede mostrar una identidad antigua hasta un refresh, aunque `DevicePatchService` no usa rutas del catálogo y resuelve de nuevo al operar. El App Group requerido por worse_query no está disponible automáticamente en la firma VINI.

## J. Conclusión
**Implementado y verificado estáticamente; compilación de la corrección y pruebas en dispositivo pendientes.**
