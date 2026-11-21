# Implementación Christmas Red

## Cambios correctivos de fidelidad

- Se extrajeron de la referencia aprobada capas independientes `Christmas-Top-Lights`, `Christmas-Bottom-Gifts` y `Christmas-Red-Glow`.
- Las pantallas ya no dependen de caracteres `✦`/`❄︎` como decoración principal.
- La composición superior e inferior se adapta con `scaledToFill`, safe areas y capas sin interacción.
- Login, arranque, pausa y mantenimiento usan además el resplandor rojo de referencia; Instaladas, Archivos y Ajustes conservan la decoración fotográfica superior/inferior sin tapar contenido.

- Paleta centralizada negro, rojo y dorado en `DesignSystem.swift`.
- `ChristmasBackdrop` reutilizable con luces y copos discretos, sin interacción ni posiciones dependientes del dispositivo.
- Logo navideño añadido como `VINI-Christmas.imageset` y utilizado por `AppLogo`.
- AppIcon navideño PNG cuadrado de 1024×1024; el original se conserva como `AppIcon-1024.original.png`.
- Ajustes y espacio de trabajo muestran `VINI` como etiqueta comercial, preservando rutas físicas.
- Pausa y mantenimiento reutilizan la misma decoración visual y mantienen sus reintentos y estados.

## Reversión

Revertir el commit de esta rama o restaurar `AppIcon-1024.original.png` a `AppIcon-1024.png`. No se requiere migración de datos.
