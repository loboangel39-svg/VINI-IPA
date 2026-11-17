# Fase 5 — Validación

## A. Resumen
Validación estática realizada frente al baseline; compilación completa, integración en dispositivo y reinstalación real pendientes. La primera compilación del PR detectó un error de tipo y se corrigió en `de66af4d930d7c8404fe4da55cb310b9fda52b9b`.

## B. Estado inicial
Rama `feature/vini-native-worse-query`, base `df99bf2fbb32b86966990077864a9d355271197b`, upstream `d1540e20cd82b974d891e0551ced6d6aeb570ac2`. PR draft [#1](https://github.com/loboangel39-svg/VINI-IPA/pull/1).

## C. Modificaciones
Este informe únicamente. El código integrado figura en los informes de Fases 1–4. No se alteran motores, permisos ni transacciones para declarar éxito.

## D. Recursos preservados
La comparación base→rama lista únicamente la nueva fuente upstream, informes, workflow, proyecto/bridging header, adaptador, catálogo y los puntos de conexión de Files y Patches. `Info.plist`, autenticación, motor `bad_query`, `PatchTransaction`, assets y Cloudflare no figuran como modificados. Se conservan entitlements, App Groups, Bundle ID, login, licencias, tokens, backups y restauración.

## E. Integridad
Se comprobaron 17/17 SHA Git de blobs contra upstream en Fase 1 y se generó el manifiesto SHA-256. La verificación SHA-256 del checkout por Actions permanece en cola. Diferencias upstream detectadas: cero.

## F. Compilación
- [Build VINI inicial del PR](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44158620752): falló con error de tipo `FileBrowserView.swift:1154`; código corregido.
- [Build VINI posterior](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44159017069) y [workflow de integración](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44159007689): en cola al redactar.
- IPA unsigned: no confirmada. Compilación firmada: no intentada.

## G. Pruebas
- Estáticas: procedencia de blobs y comparación de archivos modificados, realizadas.
- Unitarias: no existe target de tests en el proyecto inspeccionado.
- Compilación y enlace: primera ejecución falló; corrección pendiente de nueva ejecución.
- Integración: pendiente.
- Dispositivo: pendiente, incluidas adquisición de worse_query, identidad tras reinstalación, Files→Patches, aplicación y restauración de patches.

## H. Riesgos
El ejecutable VINI no tiene entitlement de App Group configurado. Sin provisión autorizada, `WorseQueryAdapter` devuelve un error verificable y el proveedor no puede demostrar acceso. El catálogo compartido se actualiza cuando Files refresca; no detecta desinstalaciones sin refresh. Un estado de catálogo no sustituye validación de ruta ni una transacción exitosa.

## I. Conclusión
**Parcial.** No se declara integración funcional hasta obtener build exitoso y pruebas reales en dispositivo autorizado.
