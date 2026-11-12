# Workflow macOS

`.github/workflows/vini-native-ios-build.yml` realiza:

1. Selección de Xcode y listado de SDK.
2. Build `iphoneos` con `ARCHS=arm64` y sin firma.
3. Verificación de `libViniNativeBootstrap.a` mediante `lipo` y `nm`.
4. Build para simulador, propagando correctamente los errores de `xcodebuild` mediante `pipefail`.
5. Instalación/arranque del host controlado en un simulador disponible.
6. Búsqueda del mensaje `[ViniNativeBootstrap] explicit start invoked` en el log.
7. Publicación de logs y binarios como artifact.

El workflow todavía no se ha ejecutado desde este entorno.
