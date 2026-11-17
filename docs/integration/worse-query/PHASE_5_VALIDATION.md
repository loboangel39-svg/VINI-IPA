# Fase 5 — Validación de la integración y corrección modelo 2

## A. Resumen
La integración anterior compiló y verificó integridad en GitHub Actions. La corrección de descubrimiento compartido está implementada en `097849a8e00de6856a0355c762b57aa0001a0dfd`; su compilación macOS y las pruebas de dispositivo siguen pendientes.

## B. Estado inicial
Rama `feature/vini-native-worse-query`, base VINI `df99bf2fbb32b86966990077864a9d355271197b`, upstream worse_query `d1540e20cd82b974d891e0551ced6d6aeb570ac2`, [PR draft #1](https://github.com/loboangel39-svg/VINI-IPA/pull/1).

## C. Modificaciones validadas
El modelo 2 extrae la secuencia de `AppDataBrowserView.reload()` a `SharedApplicationDiscoveryService`. Files y Patches llaman a ese único servicio. Patches inicia descubrimiento al entrar, permite refresh explícito y no requiere abrir Files. `DiscoveredAppCatalog` queda como caché y observador; `DevicePatchService` sigue resolviendo por Bundle ID en cada operación. Véase [informe específico](PHASE_3_SHARED_DISCOVERY_V2.md).

## D. Recursos preservados
Comparación con baseline: sin cambios en `Info.plist`, autenticación, `bad_query`, `PatchTransaction`, assets o Cloudflare. Código upstream, entitlements, App Groups, Bundle ID, licencias, tokens, backups y restauración no se alteraron con el modelo 2.

## E. Integridad
17/17 blobs Git de worse_query siguen idénticos al origen. El manifiesto SHA-256 pasó en [Actions sobre `0873306d`](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44159957931). El workflow de la nueva cabeza volverá a ejecutarlo.

## F. Compilación
- [Integración `0873306d`](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44159957931): **éxito** con Xcode, arm64, integridad y [IPA unsigned](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44159957931/artifacts/14363278059).
- [Corrección modelo 2 `097849a8`](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44162180980): **en cola** al redactar. No se atribuye el éxito anterior a este código.
- Firma válida: no intentada.

## G. Pruebas
- Estáticas: orden de fuentes y merges comparados con el flujo de Files; coalescencia de solicitudes y refresh explícito presentes; diff de recursos protegidos revisado.
- Automatizadas: integridad y compilación del commit anterior completadas; no hay target unitario en el proyecto. Build del modelo 2 pendiente.
- Dispositivo: pendientes Files, Patches sin abrir Files, simultaneidad, refresh, reinstalación, adquisición de worse_query, aplicación y restauración.

## H. Riesgos
El App Group original de worse_query no está autorizado automáticamente para VINI. La caché de 60 segundos puede mantener identidades hasta un refresh, pero no se usan rutas de esa caché al operar. La validación de identidad y acceso real exige dispositivo y firma autorizados.

## I. Conclusión
**Modelo 2 implementado y verificado estáticamente; compilación de la corrección y validación funcional pendientes.**
