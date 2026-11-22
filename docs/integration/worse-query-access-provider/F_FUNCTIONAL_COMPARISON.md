# F. Comparación funcional con VINI-IPA de producción

## 1. Tabla comparativa

| Área | `main` (`df99bf2`) | Rama experimental | ¿Cambia el comportamiento observable? |
|---|---|---|---|
| Bundle ID | `com.apple.mobile.MobileHouseArrest` | idéntico | No |
| App Group | ninguno configurado | ninguno añadido | No |
| Login / JWT / Keychain | original | intacto | No |
| Licencias / Cloudflare | original | intacto | No |
| Kernel exploit | `kexploit_opa334` + `sandbox_escape` | intacto | No |
| `bad_query` | proveedor existente | intacto; primero en versiones verificadas | No cuando funciona |
| MHA-C2 / MCM | resolución autoritativa | intacta | No |
| Descubrimiento de Files | API/MCM/MHA/LS/metadata | intacto | No |
| Resolución Bundle ID -> UUID | `resolveAppContainerPath` | misma función y misma prioridad | No |
| UI de Files | original | sin cambios | No |
| Apply Patch | `PatchProjectsView` -> `DevicePatchService` -> `PatchTransaction` | mismo flujo | No en el camino normal |
| Restore / inspect / rollback | original | intacto | No |
| Formato `.3105` / import/export | original | intacto | No |
| Firma | sin entitlements en repo | sin entitlements añadidos | No |
| Nuevo acceso | no existía | fallback `worse_query` | Sí, sólo si el acceso original falla y hay App Group autorizado |

## 2. Comportamiento cuando `worse_query` no está disponible

Es el caso esperado en este repositorio (no hay App Group):

1. `worseQueryAvailable` es `false`.
2. `grantContainerAccess` no llama al upstream.
3. Se conserva exactamente el resultado de `bad_query`.
4. `DevicePatchService` exige acceso de escritura; si no lo hay, lanza el mismo
   `targetAppUnavailable` que antes.
5. Files y Patches no ganan ni pierden rutas.

## 3. Comportamiento cuando `worse_query` sí está disponible

Sólo si la firma aporta un App Group autorizado:

1. En el orden elegido por la política, se intenta `worse_query` sobre una ruta
   **ya resuelta** por VINI.
2. Se comprueba `access(2)` antes de aceptar el handle.
3. Para patches se exige `R_OK|W_OK|X_OK` y se retiene el handle durante toda la
   transacción.
4. Si la metadata MCM es legible y no coincide, se aborta.
5. `PatchTransaction` recibe la misma raíz y aplica sus mismas validaciones.

## 4. Lo que no se reconstruyó

- No hay un segundo motor de Files.
- No hay un segundo motor de Patches.
- No hay un catálogo alternativo.
- No hay una tabla persistente de UUID.
- No hay una enumeración duplicada de aplicaciones.
- No hay una nueva pantalla, botón, alerta o elemento visual.
- No se tocó el formato `.3105`, los backups, los journals ni los recibos.

## 5. Diferencias técnicas deliberadas

| Diferencia | Motivo | Reversible |
|---|---|---|
| `grantContainerAccess` acepta `requiringWrite` y elige proveedor | Conectar el proveedor adicional en la capa de acceso | Sí; eliminar el archivo de política y restaurar el cuerpo original |
| `DevicePatchService` verifica acceso de escritura y metadata | No tratar una ruta existente como prueba de vigencia | Sí; bloque acotado |
| El escaneo de metadata concede acceso por contenedor | Permitir identificación cuando MCM no entrega lease y no hay escape kernel | Sí; el escaneo y su comparación de Bundle ID son los originales |
| Se añadió el workflow de validación | Evidencia reproducible | Sí; no altera `main.yml` |

## 6. Riesgos y bloqueos

1. **Licencia GPL-3.0 del upstream.** VINI no declara una licencia compatible.
   No distribuir un IPA comercial con este código hasta resolverlo.
2. **App Group no autorizado.** Sin él, `worse_query` no se ejecuta. El código
   funciona, pero la validación real queda bloqueada.
3. **Conflicto de versiones 27.3 beta 1.** El mapa solicitado incluye esa
   versión; el README del upstream sólo declara hasta 27.2. La política
   conserva `bad_query` y documenta el conflicto.
4. **Builds 27.0 beta 5+.** VINI sólo tiene tabla de builds para beta 1–4. No se
   adivina el número de beta a partir del build; se conserva `bad_query`.
5. **Efecto sobre `Library/Caches` del App Group.** El upstream lo reemplaza
   temporalmente. Con un App Group dedicado es aceptable; con uno compartido
   puede interferir con otras apps.
6. **Rendimiento del escaneo.** Si no hay acceso raíz, se intenta una concesión
   por contenedor. Es el camino de fallback, no el camino normal.
7. **Sin prueba en dispositivo.** No se afirma que el acceso funcione en un
   iPhone real.

## 7. Estado de aceptación

| Condición | Estado |
|---|---|
| VINI conserva su funcionamiento original | **Cumplida por diseño y build**; falta prueba de dispositivo |
| Files conserva descubrimiento | Código intacto; falta prueba de dispositivo |
| Patches conserva resolvedor y motor | Código intacto; falta prueba de dispositivo |
| `bad_query` intacto | Verificado por hash |
| `worse_query` encapsulado | Cumplido |
| Sin reconstrucción de componentes | Cumplido |
| Sin permisos debilitados/eliminados | Cumplido; no se añadieron entitlements |
| Firma experimental con entitlements autorizados | **BLOQUEADA**: no hay App Group autorizado |
| Sin cambios visuales | Cumplido |
| Cambios documentados | Cumplido |
| Compilación satisfactoria | **PENDIENTE** de la ejecución del CI de la rama |
| Pruebas reales de acceso | **PENDIENTE** |

Por tanto, la integración **no se declara completada**. Se entrega como rama
experimental revisable, con los bloqueos y las pruebas pendientes explícitos.
