# Biblioteca nativa

`NATIVE-MODULE/ViniNativeBootstrap.m` solo implementa:

```objc
void ViniBootstrapStart(void)
```

La función registra un diagnóstico cuando el host la invoca. No usa `__attribute__((constructor))`, no instala hooks, no obtiene ventanas de otras aplicaciones y no toca mecanismos de integridad.
