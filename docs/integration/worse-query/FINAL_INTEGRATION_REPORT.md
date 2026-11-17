# Informe final de integración — estado para revisión

## Resumen
La rama `feature/vini-native-worse-query` y el [PR draft #1](https://github.com/loboangel39-svg/VINI-IPA/pull/1) contienen la copia íntegra de worse_query, un adaptador nativo, conexión del descubrimiento de Files con Patches y un workflow independiente. La integración todavía no está validada funcionalmente: las ejecuciones macOS posteriores a la corrección siguen en cola y no hay prueba en dispositivo.

## Baseline y procedencia
- VINI: `df99bf2fbb32b86966990077864a9d355271197b`.
- worse_query: `d1540e20cd82b974d891e0551ced6d6aeb570ac2`.
- Fuente upstream preservada en `ThirdParty/worse_query/`, 17/17 blobs Git idénticos, SHA-256 en `worse_query.sha256`.
- No se modificaron `main` ni el repositorio de forcequitOS.

## Cambios por fase
- [Fase 0](PHASE_0_AUDIT.md): arquitectura, dependencias y límites de firma.
- [Fase 1](PHASE_1_SOURCE_INTEGRITY.md): código upstream original y manifiesto de integridad.
- [Fase 2](PHASE_2_NATIVE_ADAPTER.md): Objective-C original en el target; adaptador que prioriza bad_query y libera handles según proveedor.
- [Fase 3](PHASE_3_FILES_PATCHES.md): catálogo de identidades publicado por Files, selección en Patches y resolución actual al operar.
- [Fase 4](PHASE_4_GITHUB_ACTIONS.md): workflow macOS independiente, integridad, build arm64 y empaquetado condicional.
- [Fase 5](PHASE_5_VALIDATION.md): validación estática y pruebas pendientes.

## Integridad y recursos preservados
La comparación con el baseline no muestra cambios en `Info.plist`, autenticación, `bad_query`, `PatchTransaction`, assets ni Cloudflare. No se alteraron Bundle ID, entitlements, App Groups, login, licencias, tokens, backups o restauración. Las vistas de la PoC se conservan como referencia fuera del target VINI.

## Compilación
La [primera compilación del PR](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44158620752) falló por una incompatibilidad de tipo en `FileBrowserView`; se corrigió en `de66af4d930d7c8404fe4da55cb310b9fda52b9b`. El [workflow de integración](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44159007689) y la compilación posterior estaban en cola al redactar. No hay IPA confirmada.

## Limitación de firma y pruebas
El origen requiere un App Group autorizado y VINI no declara actualmente un archivo de entitlements. Se mantuvieron los identificadores originales y el adaptador devuelve error cuando el grupo no está disponible. Una firma y un dispositivo autorizados son necesarios para demostrar adquisición efectiva, acceso a contenedor vigente tras reinstalación y aplicación/restauración de patches.

## Estado
**PR draft, integración implementada pero no aceptable todavía.** Pendiente: build exitoso, comprobación SHA-256 en runner, revisión de logs y pruebas en dispositivo. No fusionar automáticamente.
