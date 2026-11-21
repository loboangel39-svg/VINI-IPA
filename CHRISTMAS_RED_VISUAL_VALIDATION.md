# Validación visual

- `git diff --check`: PASS.
- Recursos: AppIcon 1024×1024; logo navideño 1254×1254.
- Capas decorativas: `allowsHitTesting(false)` y detrás del contenido.
- No hay iPhone ni simulador disponible en este entorno: navegación, teclado, Dynamic Island, tamaños compactos y previews requieren validación visual posterior.
- No se tomaron capturas antes/después ejecutables aquí; las referencias suministradas se usaron como guía, priorizando la interfaz real.

## Comparación

| Referencia aprobada | Implementación SwiftUI |
|---|---|
| `VINI Christmas Neon App Screens.png` — guirnalda, iluminación roja y nieve/regalos inferiores | `Christmas-Top-Lights`, `Christmas-Red-Glow` y `Christmas-Bottom-Gifts` como capas independientes |
| `VINI Christmas UI Screen Collection.png` — composiciones de login, validación, pausa y mantenimiento | `LoginView`, `VINIStartupView` y `AccessStateViews` con la misma familia de capas |

La comparación final píxel a píxel de la IPA requiere una captura de la aplicación en un iPhone o simulador. Esa evidencia no está disponible en este entorno y no se declara fidelidad verificada únicamente por CI.

Las ocho referencias individuales se conservaron como especificación de comparación; sus marcos, textos y controles no se empaquetaron en la aplicación.
