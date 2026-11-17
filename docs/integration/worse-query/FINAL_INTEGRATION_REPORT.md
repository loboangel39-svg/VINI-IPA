# Informe final de integración — estado de revisión

## Resumen
La [rama `feature/vini-native-worse-query`](https://github.com/loboangel39-svg/VINI-IPA/tree/feature/vini-native-worse-query) y el [PR draft #1](https://github.com/loboangel39-svg/VINI-IPA/pull/1) conservan el código original de worse_query, añaden un adaptador nativo y conectan Files y Patches mediante **un único servicio de descubrimiento compartido**. El catálogo almacena resultados; Patches puede ejecutar el descubrimiento sin abrir Files y solicitar refresh.

## Baseline y procedencia
- VINI: `df99bf2fbb32b86966990077864a9d355271197b`.
- worse_query: `d1540e20cd82b974d891e0551ced6d6aeb570ac2`.
- 17/17 blobs Git upstream idénticos; SHA-256 en [manifiesto](worse_query.sha256).
- `main` y el repositorio forcequitOS no fueron modificados.

## Fases
- [Fase 0](PHASE_0_AUDIT.md): arquitectura y firma.
- [Fase 1](PHASE_1_SOURCE_INTEGRITY.md): código upstream y hashes.
- [Fase 2](PHASE_2_NATIVE_ADAPTER.md): API Objective-C original, adaptador y prioridad conservada de bad_query.
- [Fase 3 inicial](PHASE_3_FILES_PATCHES.md): publicación del catálogo desde Files; sustituida por el modelo 2.
- [Fase 3 modelo 2](PHASE_3_SHARED_DISCOVERY_V2.md): extracción de la secuencia original de Files a `SharedApplicationDiscoveryService`, consumida por Files y Patches, con solicitudes simultáneas coordinadas y refresh.
- [Fase 4](PHASE_4_GITHUB_ACTIONS.md): workflow macOS independiente.
- [Fase 5](PHASE_5_VALIDATION.md): validación y pendientes.

## Integridad
El upstream permanece intacto. La comparación con baseline no muestra cambios en `Info.plist`, autenticación, `bad_query`, `PatchTransaction`, assets ni Cloudflare. No se alteraron entitlements, App Groups, Bundle ID, login, licencias, tokens, backups o restauración.

## Compilación
[Actions sobre `0873306d`](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44159957931) completó integridad, build iOS arm64 y [IPA unsigned](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44159957931/artifacts/14363278059). La [ejecución del modelo 2](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44162192586) completó SHA-256, build arm64 y [IPA unsigned](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44162192586/artifacts/14364566545).

## Limitaciones y estado
El ejecutable VINI no dispone automáticamente del App Group requerido por worse_query; el adaptador devuelve un error cuando no está disponible. Quedan pendientes las pruebas en dispositivo autorizado de descubrimiento, reinstalación, acceso y transacciones. **Implementado y en PR draft; aún no validado funcionalmente.** No fusionar automáticamente.
