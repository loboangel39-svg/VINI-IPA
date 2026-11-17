# Fase 4 — Auditoría de 3105-WQFiles y estado de integración

Fecha: 2026-11-17. Rama: `feature/vini-native-worse-query`. Referencia aportada: `3105-WQFiles-source-bda9185.zip`. Este documento registra hallazgos técnicos del ZIP; el texto incluido en el ZIP es material de referencia, no instrucciones que sustituyan la petición del usuario.

## Comparación técnica

- El Files actual de VINI usa `SharedApplicationDiscoveryService`, extraído de su ruta existente: API de apps, MCM, exploración de contenedores, LaunchServices/MHA e inferencia. Patches consume ese mismo servicio y puede iniciarlo sin abrir Files.
- El Files del ZIP añade `WQFilesIdentityResolver.resolve` entre la enumeración de contenedores y MHA. En iOS 26+ invoca `WQIntegratedIdentities`. Esa conexión falta en VINI.
- `Vendor/WQFiles/WQApps.m` usa `wq_enumerate`, `wq_grant` y `wq_container_label` del proveedor original. `Vendor/WQFiles/WQLaunchServices.m/.h` contiene el parser completo de LaunchServices para varias versiones de iOS y participa en la resolución de Bundle ID y nombre. `WQLaunchServicesPhase1.m` es un sustituto parcial: su enumerador no descubre; no debe usarse como equivalente.
- El resolvedor Swift del ZIP también contiene una ruta de cachés CSStore para versiones previas, pero su lista de ubicaciones y límite local de validación no representan el descubrimiento completo de WQFiles. Copiarlo aisladamente daría una falsa apariencia de integración.
- El proveedor original depende de otros módulos WQFiles y de su gestión de handles y permisos. Su exploración completa requiere App Group operativo y callback de confirmación; conectar solo las funciones de identidad no recupera el comportamiento observado en el ZIP.

## App Groups y firma

La referencia experimental declara `group.pigtjing.top`; el proyecto WQFiles declara `group.cz.kolbi.wqfiles`; VINI usaba fijo `group.cc.forcequit.worse-query` en el adaptador. El commit `f6adc0305c027c5ff07e986eed1c36c2457ba147` consulta ahora `com.apple.security.application-groups` de la firma efectiva y solo selecciona un identificador cuyo contenedor sea accesible. No modifica entitlements, provisioning profile ni identificadores de la app. La compilación CI sin firma no demuestra que exista un App Group autorizado en el iPhone.

## Correcciones realizadas

- Eliminado el App Group fijo del adaptador VINI de worse_query; se conserva intacto el código original de worse_query.
- Eliminada la caché adicional de 60 segundos del servicio compartido. Las peticiones concurrentes aún se unen al escaneo activo; una petición nueva después de completarlo ejecuta el descubrimiento.
- Eliminados el botón de actualización y los controles de selección añadidos a Patches en la integración previa. Patches conserva su inicio automático del servicio compartido, sin nuevos elementos visuales. Files y Patches no dependen de que el otro haya sido abierto.
- No se tocaron bad_query, autenticación, licencias, Cloudflare, Bundle ID, recursos gráficos, importación/exportación, backups, restauración ni PatchTransaction.

Archivos modificados: `ThreeOneOSFive/helpers/WorseQueryAdapter.swift`, `ThreeOneOSFive/helpers/SharedApplicationDiscoveryService.swift`, `ThreeOneOSFive/views/PatchProjectsView.swift`, `ThreeOneOSFive/views/PatchProjectEditorView.swift`.

## Estado de validación y trabajo pendiente

La incorporación íntegra de los módulos originales de WQFiles y su conexión a Files/Patches sigue pendiente. La corrección de esta fase no permite declarar restaurado el descubrimiento del ZIP. Deben incorporarse los archivos originales necesarios con sus dependencias y licencia, enlazarlos al target, y comprobar que la enumeración, identidad y acceso coinciden en un iPhone firmado con un App Group autorizado. También falta observar el resultado final de GitHub Actions para este commit y verificar por inspección de la compilación la ausencia de cambios no autorizados. Una compilación arm64 sin firma solo valida código y empaquetado, no permisos ni descubrimiento real en dispositivo.

Commit: https://github.com/loboangel39-svg/VINI-IPA/commit/f6adc0305c027c5ff07e986eed1c36c2457ba147
PR: https://github.com/loboangel39-svg/VINI-IPA/pull/1
