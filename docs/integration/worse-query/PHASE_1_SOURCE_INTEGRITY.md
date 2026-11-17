# Fase 1 — Código original e integridad

## A. Resumen
Se incorporaron los 17 archivos regulares del árbol completo de `forcequitOS/worse_query` desde `d1540e20cd82b974d891e0551ced6d6aeb570ac2` bajo `ThirdParty/worse_query/`. Se conservaron licencia GPL-3.0, proyecto Xcode, recursos, vistas, Objective-C, bridging header y entitlement original. No se editó ningún archivo upstream.

## B. Estado inicial
Rama `feature/vini-native-worse-query`; base VINI `df99bf2fbb32b86966990077864a9d355271197b`; informe Fase 0 en `0a321abfbd0684a9ae5e05e163503085ba6c87b7`.

## C. Modificaciones
- `ThirdParty/worse_query/**`: copia exacta del árbol upstream; fuente de referencia y futura compilación de `worse_query.m` y `pathleak.m`.
- `docs/integration/worse-query/worse_query.sha256`: manifiesto SHA-256 de los 17 archivos.
- Este informe: procedencia, comprobación e impedimentos.
No se modificó el proyecto VINI ni se enlazó todavía el proveedor.

## D. Recursos preservados
Se preservaron todos los recursos originales de worse_query, incluido `group.cc.forcequit.worse-query` en su archivo de referencia. Motores VINI, Files, Patches, entitlements, App Groups, Bundle ID, login, licencias, tokens, backups, restauración y transacciones no cambiaron.

## E. Integridad
Los 17 blobs fueron creados en VINI desde el contenido upstream y cada SHA Git resultante coincidió exactamente con el SHA Git de origen. Cero diferencias. Los SHA-256 calculados sobre el contenido fuente se registraron en `worse_query.sha256`. El workflow de Fase 4 verificará el manifiesto nuevamente en macOS con `sha256sum -c` o equivalente. No se declara integridad de binarios generados.

## F. Compilación
No ejecutada. El árbol upstream está conservado, pero sus fuentes aún no están en el target VINI. Sin URL ni artefacto.

## G. Pruebas
Estática: 17/17 coincidencias de blobs Git y manifiesto SHA-256 generado. Unitarias, compilación, integración y dispositivo: pendientes.

## H. Riesgos
GPL-3.0 impone obligaciones de distribución. El App Group de la PoC permanece solo como referencia; VINI no obtiene automáticamente ese entitlement. Una firma autorizada y una prueba de dispositivo serán necesarias para demostrar adquisición real.

## I. Conclusión
**Completada y verificada para la copia de fuentes.** Integración nativa y funcionamiento en dispositivo pendientes.
