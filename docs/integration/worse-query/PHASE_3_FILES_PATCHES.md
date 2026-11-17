# Fase 3 — Files y Patches (modelo inicial)

> Este informe registra el modelo inicial. La corrección que permite a Patches ejecutar el mismo motor de descubrimiento está en [PHASE_3_SHARED_DISCOVERY_V2.md](PHASE_3_SHARED_DISCOVERY_V2.md). El catálogo ya no depende únicamente de que Files publique resultados.

## A. Resumen
Files conserva todas sus fuentes de descubrimiento y publica las mismas instantáneas que muestra en pantalla. El editor de proyectos de Patches ofrece los Bundle IDs publicados. Patches vuelve a resolver la ruta al aplicar, inspeccionar o restaurar; no guarda UUID de contenedor desde el catálogo.

## B. Estado inicial
Rama `feature/vini-native-worse-query`; base VINI `df99bf2fbb32b86966990077864a9d355271197b`; Fase 2 `f3bc23c3c5749d09694b70d26cc45102f042128e`.

## C. Modificaciones
- `ThreeOneOSFive/helpers/DiscoveredAppCatalog.swift`: catálogo compartido en memoria de identidades descubiertas, con estados `discovered`, `resolved`, `accessible`, `unavailable`. No ejecuta enumeración.
- `ThreeOneOSFive/views/AppDataBrowserView.swift`: limpia el catálogo al refrescar y publica resultados preliminares, progresivos y finales del flujo original.
- `ThreeOneOSFive/views/PatchProjectEditorView.swift`: permite elegir Bundle IDs publicados por Files; conserva entrada manual para casos donde Files aún no haya cargado.
- `ThreeOneOSFive/helpers/DevicePatchService.swift`: marca estados de resolución/acceso; solicita una ruta actual por Bundle ID en cada operación, mantiene grants durante `PatchTransaction` y rechaza metadatos de otra aplicación.
- `ThreeOneOSFive.xcodeproj/project.pbxproj`: registra el nuevo archivo Swift.

## D. Recursos preservados
No se sustituyeron API, MCM, enumeración de sistema de archivos, LaunchServices, MHA ni mergers de Files. `PatchTransaction`, motores existentes, código original de worse_query, entitlements, App Groups, Bundle ID, login, licencias, tokens, backups y restauración permanecen intactos.

## E. Integridad
Los 17 archivos upstream siguen en el árbol de referencia y no se editaron. Manifiesto `worse_query.sha256`; comprobación en runner pendiente. Las rutas de VINI sí cambiaron según la lista C.

## F. Compilación
Pendiente del workflow de Fase 4; sin URL ni artefacto en esta fase.

## G. Pruebas
Estáticas: el catálogo no contiene código de enumeración; Files publica la lista que presenta; Patches toma IDs de ese catálogo; DevicePatchService resuelve por Bundle ID para cada transacción. Unitarias, compilación, integración y reinstalación en dispositivo pendientes.

## H. Riesgos
El catálogo es memoria de proceso: requiere que Files se abra y refresque para ofrecer sus resultados, y la entrada manual permanece disponible. Un estado `accessible` representa un grant o lectura de raíz observada, no una operación de patch completa. La comprobación de metadatos se realiza cuando esos metadatos están disponibles; la verificación en dispositivo sigue pendiente. Al refrescar se descartan identidades antiguas, pero desinstalaciones sin refresh no generan un evento automático; la resolución de Patches sigue consultando MCM/escaneo actual antes de operar.

## I. Conclusión
**Sustituida por el modelo 2 compartido; pendiente de compilación de la corrección y pruebas en dispositivo.** No se afirma que los casos de reinstalación hayan superado una prueba real.
