# Informe de pausa e icono

## Causa raíz

La pausa antigua del panel se guarda en `users.is_paused`. El Worker rechazaba ese usuario en `verifyAppAuth` y `handleAppValidateLicense` antes de ejecutar `getAccessState`, devolviendo 401/403. La aplicación interpretaba el resultado como sesión revocada y navegaba a Login.

## Corrección

Para clientes V2 con `access-state-v1`, el Worker conserva la autenticación validando JWT, expiración, firma, `session_version`, HWID, `is_active` e `is_blocked`. `users.is_paused` y `license_access_state.individual_pause` se exponen como `license_paused`. Los clientes antiguos conservan su contrato anterior.

## Matriz revisada

| Caso | Resultado esperado | Evidencia |
|---|---|---|
| V2 activo | `active`, contenido principal | código Worker/cliente |
| V2 pausado | sesión válida, `license_paused`, pantalla bloqueante | código Worker/cliente |
| V2 reactivado | `active`, recuperación sin Login | código `getAccessState` |
| mantenimiento | `maintenance`, pantalla bloqueante | código `getAccessState`/`App.swift` |
| JWT inválido | 401, Login | `verifyAppAuth` |
| V1 pausado | rechazo histórico | rama sin `access-state-v1` |

La prueba contra un Worker/D1 de staging con transición administrativa real queda pendiente; no se ejecutó sobre licencias reales ni producción.

## Icono

`AppIcon.appiconset/AppIcon-1024.png` y `VINI-Neon.imageset/VINI-Neon.png` son byte-identicos. SHA-256: `B0900823E4909D36C0BBD295682A402F6B033CDEB86F1661CBBCFECCBCCF6D52`.
