# Incidente de producción — `741cb9f7`

## Recuperación

- Versión incidente: `741cb9f7-f50e-4ccf-b283-98cd0fb151cd`
- Rollback ejecutado: `c5cb49ea-b669-4903-bc76-08608d26dc7e`
- Tráfico actual: 100% a `c5cb49ea`
- `/api/app/session` sin credenciales después del rollback: HTTP 401, respuesta de autenticación esperada.
- No se modificaron D1, R2, secretos, licencias, sesiones ni parches.

## Causa raíz

La D1 de producción no contiene las tablas de access-state (`access_controls`, `license_access_state`, `provider_maintenance`, etc.) ni las columnas piloto completas (`license_plan_enabled`, `provider_id`) que existen en staging.

La versión `c5cb49ea` evitaba consultar esas tablas para usuarios sin `license_plan_enabled = 1`. `741cb9f7` pasó `allowAccessStateClient = true` para todos los clientes que declaraban `access-state-v1`, saltándose esa salida de compatibilidad y ejecutando consultas a tablas inexistentes. El resultado fue una excepción D1/HTTP 5xx para esas sesiones, que la IPA presentó como «El servidor no responde».

## Impacto

El cambio no afectó datos ni secretos. El rollback restauró el comportamiento anterior. No se declara corregida la pausa en producción: las tablas de access-state deben existir y estar migradas, o el Worker debe aplicar una compatibilidad explícita sin consultar tablas ausentes.

## Acciones no realizadas

- No se ejecutaron migraciones en producción.
- No se desplegó otra corrección.
- No se tocó R2, AppIcon, motor de parches ni licencias.

La solución segura requiere decidir entre preparar migraciones D1 compatibles en staging/producción o añadir una ruta de compatibilidad que detecte el esquema; ambas requieren revisión y pruebas antes de desplegar.
