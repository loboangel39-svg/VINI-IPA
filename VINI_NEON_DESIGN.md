# VINI Neon Design

## Alcance

Rediseño visual conservador basado en el icono violeta neón proporcionado: fondo negro profundo, superficies violetas, degradados violeta-magenta, reflejos lavanda y glow limitado a jerarquía/interacción.

## Sistema centralizado

`ThreeOneOSFive/views/DesignSystem.swift` centraliza `AppTheme`, `VINIButtonStyle`, `VINICardBackground` y el emblema VINI. La aplicación usa esquema oscuro para conservar contraste y consistencia en las vistas existentes sin cambiar navegación ni modelos.

## Compatibilidad

No se modificaron Worker, D1, R2, autenticación, catálogo, descargas ni motores locales de parches. La sincronización mantiene la política de `5575bf1`: `access == nil` permite sincronizar para Worker antiguo; estados explícitos bloqueantes no.

## Limitación

El archivo original de imagen no existe como recurso local del repositorio; se implementó un emblema SwiftUI ligero inspirado en su V, gradientes y anillo neón. No se añadió una imagen pesada como fondo.
