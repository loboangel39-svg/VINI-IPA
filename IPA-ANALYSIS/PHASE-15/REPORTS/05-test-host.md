# Host de prueba

`ViniBootstrapTestHost` crea su propia `UIWindow`, invoca `ViniBootstrapStart()` explícitamente y presenta una pantalla UIKit de diagnóstico. El controlador de login VINI está preparado en el proyecto, pero no se conecta al arranque hasta que la Etapa A se compile y ejecute correctamente.

El código preparado usa el endpoint VINI obligatorio y Keychain para HWID/licencia/token. La pantalla distingue `licenseExpiresAt` de `expiresAt` en el contrato previsto, pero la Etapa B aún no está conectada ni validada; no se incluyeron secretos ni licencias reales.

La interfaz de diagnóstico y el código de cliente solo están en el host de prueba; no se integraron en 8 Ball Pool.
