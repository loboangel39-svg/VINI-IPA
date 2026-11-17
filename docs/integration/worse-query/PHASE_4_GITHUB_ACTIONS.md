# Fase 4 — GitHub Actions

## A. Resumen
Se añadió un workflow independiente de macOS para integridad SHA-256, comparación de recursos protegidos, compilación iOS arm64 y publicación de logs y un IPA unsigned cuando el build termine correctamente. Los workflows originales permanecen intactos.

## B. Estado inicial
Rama `feature/vini-native-worse-query`, base `df99bf2fbb32b86966990077864a9d355271197b`, origen worse_query `d1540e20cd82b974d891e0551ced6d6aeb570ac2`. Workflow original `main.yml` usa el scheme `3105` y firma desactivada; `fix-login-files.yml` no se modificó.

## C. Modificaciones
- `.github/workflows/vini-worse-query-integration.yml`: checkout completo; registra Xcode y schemes; comprueba el manifiesto de 17 archivos y los recursos VINI protegidos frente al baseline; compila el target 3105 para iOS arm64 sin firma; empaqueta `Payload/*.app` como IPA unsigned si el build tiene éxito; publica logs, informes y el artefacto.
- Este informe: estado y límites de la ejecución.
El workflow no usa certificados ni secretos y no cambia entitlements.

## D. Recursos preservados
Código upstream, motores VINI, Files, Patches, `PatchTransaction`, entitlements, App Groups, Bundle ID, autenticación, licencias, tokens, backups y restauración no se alteraron por esta fase. El workflow original `main.yml` permanece sin cambios.

## E. Integridad
La Fase 1 comprobó 17/17 blobs Git idénticos al upstream. El manifiesto SHA-256 está versionado. La comprobación SHA-256 en el runner está pendiente de la ejecución en cola.

## F. Compilación
- Workflow de integración: [ejecución push 44159007689](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44159007689), en cola al redactar este informe.
- Workflow original del PR: [ejecución 44158620752](https://github.com/loboangel39-svg/VINI-IPA/actions/runs/44158620752), falló por un error de tipo en `FileBrowserView.swift:1154`. Corregido en `de66af4d930d7c8404fe4da55cb310b9fda52b9b`. La nueva ejecución del PR aún está en cola.
- No hay compilación exitosa ni IPA confirmada. No se proporcionan URLs de artefacto inexistente.

## G. Pruebas
Verificación estática de cambios contra baseline realizada mediante comparación de commits. SHA-256 en runner, compilación, enlace, pruebas automatizadas y dispositivo: pendientes.

## H. Riesgos
El runner macOS aún no ha ejecutado el workflow nuevo. Incluso si produce IPA unsigned, eso no prueba firma válida ni adquisición de worse_query. El App Group original de la PoC no está concedido al target VINI por su configuración actual; se mantiene intacto y se requiere aprovisionamiento autorizado para una prueba real.

## I. Conclusión
**Implementada; validación de GitHub Actions pendiente de ejecución.** Actualizar con resultados reales cuando finalice.
