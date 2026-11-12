# Proyecto y alcance

Se creó un proyecto Xcode autocontenido en `XCODE-PROJECT/ViniBootstrapTestHost.xcodeproj` con dos targets:

- `ViniNativeBootstrap`: biblioteca estática Objective-C arm64 con `ViniBootstrapStart()`.
- `ViniBootstrapTestHost`: aplicación UIKit que invoca explícitamente esa función en `application:didFinishLaunchingWithOptions:`.

El host de prueba es independiente del IPA de 8 Ball Pool. No contiene hooks, inicializadores automáticos ni cambios al ejecutable del juego.
