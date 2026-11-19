# Comparación con WQFiles

## WQFiles auditado

Commit: `bb81069401875a470a032830b8e6bc934fbd9146`.

Funciones relevantes:

- `wq_find_ls_store`: usa la ruta persistida, valida el archivo y considera el store más
  reciente.
- `wq_parse_ls_store`: verifica magic `bdsl`, layouts conocidos, referencias de strings,
  conflictos y cobertura.
- `wq_bundle_id_for_container`: consulta el mapa de ruta a Bundle ID ya publicado.
- `wq_enumerate`: puede explorar `InternalDaemon` mediante el mecanismo de acceso propio de
  WQFiles.

## Diferencias verificadas

El proveedor 3105:

- usa `MCMActivateContainerPath(10, "com.apple.lsd", ...)` como fuente de información;
- comprueba dos raíces fallback con `FileManager`;
- reutiliza `WQLaunchServicesStore` solo si está configurado en sus propios defaults;
- no realiza una búsqueda adicional de todos los contenedores `InternalDaemon`;
- no usa tokens ni mecanismos nuevos para superar el sandbox;
- no llega al parser cuando `candidates=0`.

WQFiles dispone de una ruta de descubrimiento más amplia, pero su funcionamiento depende de
autorizaciones y componentes que no están presentes o demostrados en 3105. No es válido
copiar el App Group de la Beta ni inferir que un handle ajeno sea reproducible.

## iOS 26.6.1

El log `candidates=1 records=247 rejected=247` demuestra que en esa versión sí hubo lectura
de un store. Es un problema separado de interpretación/validación y no prueba que el parser
sea la causa del bloqueo primario de iOS 27.2.1.

## Conclusión

La comparación justifica mejorar diagnóstico y procedencia, pero no modificar el parser ni
introducir una nueva ruta de acceso sin autorización explícita del sistema.
