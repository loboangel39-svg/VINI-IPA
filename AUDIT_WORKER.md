# Auditoría Worker

## Hallazgos corregidos

- El login V2 ahora materializa y devuelve `access` para clientes `license-plan-v1,access-state-v1`, incluso cuando están pausados, para permitir la pantalla de bloqueo.
- La autenticación administrativa dejó de aceptar secretos por defecto (`vini2026`/`vini-jwt-secret-change-me`); requiere variables configuradas y el usuario del token debe ser `ADMIN_USERNAME`.
- CORS ahora permite `X-VINI-Capabilities`.
- La búsqueda administrativa dejó de interpolar texto en SQL y usa parámetros.
- El panel ahora trata respuestas HTTP no exitosas como errores y no muestra éxito falso.

## Estado

Los endpoints de acceso están bajo `verifyAuth`; no se implementaron cuentas de proveedor. Los usuarios normales no pueden invocar controles administrativos.

## Riesgos residuales

Las mutaciones que materializan estado recorren usuarios con operaciones separadas. D1 `batch` hace atómicas las sentencias de una operación, pero no convierte el recorrido completo en una transacción serializable. Esto queda BLOQUEADO para producción hasta probar un diseño de transición basado en versionado/conditional updates bajo concurrencia.
