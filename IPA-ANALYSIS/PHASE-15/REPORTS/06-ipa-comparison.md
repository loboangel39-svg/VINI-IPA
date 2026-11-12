# Comparación con el IPA

El host de prueba tiene un target fuente controlado, dependencia estática declarada y una llamada explícita desde su `AppDelegate`. El IPA experimental tiene `pool`, `libloader`, `FluAudit` y `Ogiosx11.dylib` ya compilados, con inicializadores y dependencias internas.

La existencia de una biblioteca funcional en el host no demuestra que pueda cargarse en `pool`. No se modificó `pool`, `_startAPITrial`, `_OgiosTelegramInit`, `libloader` ni `FluAudit`.
