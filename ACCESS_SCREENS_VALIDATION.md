# Validación de pantallas de acceso

- `App.swift` sigue seleccionando exclusivamente `MaintenanceView` para `maintenance` y `PausedLicenseView` para `license_paused`.
- `AccessStateViews.swift` recibió únicamente presentación: fondo, tarjeta de estado, icono, botón y glow.
- `frozenSeconds` continúa siendo la única fuente de la cifra de tiempo; si falta, se muestra `Tiempo conservado` sin inventar duración.
- Reintento, polling y refresh al volver a foreground permanecen intactos.
- La transición mantenimiento → pausa depende de la siguiente respuesta válida del Worker.
- Una restauración 401/403 intenta revalidar la licencia antes de limpiar el JWT; una licencia pausada conserva la sesión y puede mostrar su pantalla.

No hubo pruebas visuales en un iPhone o simulador disponible; la compilación CI y la inspección estática son las evidencias disponibles.
