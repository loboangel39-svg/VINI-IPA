# Auditoría de estados de acceso iOS

## Estado existente

- `LoginManager.verifyStoredSession()` consulta `/api/app/session` con `access-state-v1`.
- `attemptAutoLogin()` valida la sesión al abrir.
- `scenePhase == .active` dispara otra validación al volver a foreground.
- `refreshLicenseExpirationLoop()` consulta cada 60 segundos.
- `App.swift` ya daba prioridad a `maintenance` y `license_paused` sobre `ContentView`.
- `AccessStateViews.swift` ya contiene reintento manual, foreground refresh y polling propio.

No se añadió un segundo polling ni se modificó la interfaz.

## Cambio mínimo

`AccessStateCoordinator`, alojado junto a `LoginManager`, es ahora la única fuente observable del estado de acceso en la raíz SwiftUI. Todas las respuestas válidas pasan por `apply`; logout/revocación limpia el coordinador. Las respuestas legacy sin `access` conservan estado `nil` y la compatibilidad de `5575bf1`.

Los errores de red no limpian JWT/HWID ni convierten el estado en `active`; se conserva la sesión previamente validada sin iniciar sincronización nueva.
