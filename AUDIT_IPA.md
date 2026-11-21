# Auditoría IPA

## Resultado

- El artefacto original `14687833863` pertenece al commit `55a560c` y el workflow `44857689085` terminó correctamente.
- El artefacto se descargó mediante `gh run download`; contiene `VINI.app` directamente, no un contenedor `Payload/*.ipa`. Por ello no cumple literalmente el formato IPA solicitado.
- `VINI.app/VINI` existe (10,260,064 bytes), `Info.plist` existe (2,330 bytes), y el ejecutable contiene `Licencia pausada`, `VINI en mantenimiento`, `access-state-v1`, `PausedLicenseView` y `MaintenanceView`.
- No se pudo certificar firma, entitlements, arquitectura ni Bundle ID con las herramientas disponibles en Windows; la siguiente compilación CI debe entregar el formato esperado o documentar explícitamente el paquete `.app`.

## Hallazgos corregidos

1. El login de V2 no incluía `access`; una licencia pausada podía entrar a la raíz. El Worker ahora devuelve el estado tras validar HWID.
2. Una respuesta HTTP 200 no-JSON en la restauración de sesión podía considerarse válida. Ahora se clasifica como error de red/contrato.
3. La navegación conserva la pantalla bloqueada ante fallos posteriores; no se desbloquea localmente.

## Pendiente

Inspección binaria con un token GitHub que permita descargar el artefacto o con el nuevo artefacto de CI.
