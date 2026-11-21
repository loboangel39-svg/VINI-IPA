# Preparación para despliegue

## Estado: NO LISTO PARA PRODUCCIÓN

La rama contiene correcciones y un empaquetado CI corregido para generar `.ipa` real. No se desplegaron Worker, panel ni migraciones.

Antes de autorizar despliegue faltan: preflight D1 contra staging, backup verificable, pruebas de concurrencia, validación binaria del IPA nuevo, prueba en dispositivo y regresión con IPA antigua.

## Reversión

No ejecutar `0004` hasta confirmar columnas/tablas faltantes. Desplegar Worker y panel solo tras backup y smoke tests en staging; revertir al commit anterior si falla autenticación, estado de acceso o contrato legacy. Mantener `main` sin cambios.
