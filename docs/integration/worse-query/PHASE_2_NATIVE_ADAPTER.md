# Fase 2 — Adaptador nativo

## A. Resumen
El target VINI incluye `worse_query.m` y `pathleak.m` originales. El bridging header expone la API original. `WorseQueryAdapter` obtiene y libera handles sin modificar el código upstream. `ContainerStore.grantContainerAccess` conserva `bad_query` como primera opción y prueba worse_query solo si aquel falla. `DevicePatchService` mantiene el grant durante la transacción.

## B. Estado inicial
Rama `feature/vini-native-worse-query`; base `df99bf2fbb32b86966990077864a9d355271197b`; fuente worse_query `d1540e20cd82b974d891e0551ced6d6aeb570ac2`. Fase 1 en `c55834f5219eeabadd609e2493df337a19a691c3`.

## C. Modificaciones
- `ThreeOneOSFive.xcodeproj/project.pbxproj`: añade los dos .m originales y el adaptador Swift al target, sin incluir las vistas PoC como aplicación ejecutable.
- `ThreeOneOSFive/ThreeOneOSFive-Bridging-Header.h`: importa el encabezado original de worse_query.
- `ThreeOneOSFive/helpers/WorseQueryAdapter.swift`: comprueba versión y disponibilidad del App Group original, llama a `worse_query`, devuelve error explícito y libera con `worse_query_release`.
- `ThreeOneOSFive/helpers/ContainerStore.swift`: representa el proveedor de cada handle y lo libera con su función correspondiente; conserva prioridad de bad_query. El escaneo puede usar un grant de raíz.
- `ThreeOneOSFive/helpers/DevicePatchService.swift`: conserva grants de contenedor hasta terminar `PatchTransaction` y rechaza metadatos que indiquen otro Bundle ID.
- `ThreeOneOSFive/views/FileBrowserView.swift`: conserva el grant tipado durante la vida de la vista y lo libera al terminar. Corrige el error de tipo detectado por la compilación inicial del PR.

## D. Recursos preservados
Los 17 archivos originales de worse_query están intactos; `bad_query` y los demás motores VINI mantienen sus algoritmos. Files, Patches, entitlements, App Groups, Bundle ID, login, licencias, tokens, backups y restauración siguen presentes. `PatchTransaction` no se modificó.

## E. Integridad
Manifiesto en `worse_query.sha256`; copia upstream 17/17 blobs Git coincidentes. Los archivos de referencia no se editaron en esta fase. Verificación SHA-256 en runner pendiente.

## F. Compilación
La primera compilación del workflow original del PR falló en `FileBrowserView.swift:1154` por asignar `ContainerAccessGrant` a `Int64` ([ejecución 44158620752](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44158620752)). Se corrigió en `de66af4d930d7c8404fe4da55cb310b9fda52b9b`. La nueva compilación está en cola; no hay todavía build exitoso ni artefacto.

## G. Pruebas
Estática: rutas de fuente y símbolos configurados en proyecto y bridging header. Compilación, unitarias, integración y dispositivo pendientes.

## H. Riesgos
VINI no tiene un entitlement de App Group configurado; el adaptador informará `unavailableAppGroup` en una firma que no autorice el grupo original. No se alteró el entitlement ni se simuló acceso. La compatibilidad real y la validez del grant tras la reinstalación requieren dispositivo autorizado.

## I. Conclusión
**Implementada, pendiente de compilación y dispositivo.** No se afirma adquisición funcional.
