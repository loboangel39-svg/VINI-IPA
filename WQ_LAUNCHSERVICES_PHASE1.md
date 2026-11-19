# WQFiles LaunchServices — Fase 1

Rama: `experiment/wqfiles-launchservices`  
Base: `experiment/ios27-appgroup-entitlements`

## Alcance

Se integró un módulo independiente basado en `WQLaunchServices.m/.h` de
`kolbicz/WQFiles`, conservando la licencia `GPL-3.0-or-later`:

- Parser CSStore2 con validación de cabecera `bdsl`.
- Límites de tamaño, cantidad de registros y strings.
- Lectura estable mediante comparación de `stat` antes/después.
- Layouts conocidos de iOS 26, 27.0, 27.2 y 27.3.
- Detección acotada de layouts desconocidos.
- Resolución de Bundle IDs para contenedores de aplicaciones y extensiones.
- Resolución de nombres, nombres integrados de Apple y sanitización Unicode.
- Resolución de rutas `.app` y caché de snapshot.
- Rechazo de conflictos de Bundle ID, registros corruptos y datos ambiguos.

Archivos principales:

- `ThreeOneOSFive/exploit/WQLaunchServicesPhase1.m`
- `ThreeOneOSFive/exploit/WQLaunchServicesPhase1.h`
- `Tests/WQLaunchServicesPhase1Tests.m`

## Adaptaciones deliberadas

- No se importó `WQAccess.m`, `WQAccess.h`, `WQCache` ni ningún mecanismo nuevo
  de acceso o evasión del sandbox.
- La lectura de producción solo usa una ruta CSStore2 ya recordada en
  `WQLaunchServicesStore`; no enumera `InternalDaemon` ni descubre nuevas rutas.
- Se sustituyeron las dependencias de localización por nombres sin transformar.
- El resolver Swift original permanece intacto y no fue reemplazado.
- La integración en Files es diagnóstica: ambos lectores reciben los mismos bytes
  cuando existe una fuente disponible, pero el resultado WQFiles no sustituye aún
  identidades ni modifica operaciones de lectura/escritura.

## Comparación registrada

`AppDataBrowserView` registra:

```text
[3105] ls.original: source=...
[3105] ls.original: records=...
[3105] ls.original: identities=...
[3105] ls.wqfiles: source=...
[3105] ls.wqfiles: records=...
[3105] ls.wqfiles: identities=...
[3105] ls.compare: matching=... conflicts=... additional=...
```

Cuando el CSStore2 no está disponible, los valores se registran como
`unavailable`; no se inventan resultados.

## Pruebas preparadas

El fixture portable adaptado de WQFiles cubre:

- Cabecera válida y truncada.
- Fallo y reintento de lectura.
- Nombres Unicode y controles de reordenamiento.
- Layouts de contenedores y extensiones.
- Layout iOS 27.3.
- Layout desconocido con nombres sin identidad inventada.
- Registros corruptos y store sobredimensionado.
- Conflictos de Bundle ID y contenedores ambiguos.
- Coherencia del snapshot y límites del detector de layout.

El proyecto actual no tenía un target XCTest independiente; por eso el fixture se
conserva como prueba portable de referencia y no se incorpora al binario de 3105.

## Resultado pendiente

La compilación y la ejecución en iPhone14,3/iOS 27.2.1 son necesarias para conocer
si la ruta recordada es legible. Si continúa `access_denied`, el resultado solo
demostrará que el lector no recibió una fuente disponible; no probará un fallo del
parser. La comparación A/B y la sustitución de identidades quedan fuera de esta
fase.
