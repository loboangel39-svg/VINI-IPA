# Pruebas de estados de acceso iOS

## Cobertura estática

- Active → paused: `accessState.status` cambia a `license_paused`; la raíz selecciona `PausedLicenseView`.
- Paused → active: el mismo JWT permanece y la raíz vuelve a `ContentView`.
- Maintenance: la raíz selecciona `MaintenanceView` antes de Home.
- Expired/unauthorized/revoked: se ejecuta logout y se muestra Login.
- Network error/timeout: se conserva la sesión existente y no se sincronizan parches nuevos.
- Legacy sin `access`: `AccessStateCoordinator.state == nil`; la política legacy permite sincronización.
- Reintentos: el guard `isCheckingSession` evita validaciones concurrentes desde foreground, polling y pantallas de estado.

## Pendiente

No hay iPhone/simulador disponible para una prueba visual interactiva ni XCTest de integración conectado a un Worker. La validación real de pausa/reactivación debe ejecutarse en dispositivo con staging o una cuenta de prueba autorizada.
