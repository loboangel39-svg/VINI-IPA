# Auditoría de acceso CSStore2 en iOS 27.2.1

## Alcance

Repositorio: `loboangel39-svg/3105-WORSE-QUERY`  
Rama: `feature/wqfiles-identity-resolver`  
Referencia WQFiles: `bb81069401875a470a032830b8e6bc934fbd9146`.

La auditoría no modifica permisos, entitlements, App Groups, MHA-C2, `worse_query`,
descubrimiento por inodos, Patches, Apply ni Restore.

## Causa observada

El log de iOS 27.2.1:

```text
diagnostic state=access_denied roots=2 inaccessible=2 candidates=0
```

se produce en `WQFilesIdentityResolver.loadSnapshot()` cuando `storeCandidates()` no
obtiene ningún archivo candidato. Las dos raíces fallback comprobadas son:

1. `/var/db/lsd`
2. `/var/mobile/Library/Caches`

La ruta MCM de `com.apple.lsd` tampoco entrega una referencia usable en ese proceso.
Consecuentemente, `Data(contentsOf:)` nunca se ejecuta y el parser CSStore2 no recibe datos.

Esto es una restricción de disponibilidad/autorización de la fuente, no un fallo demostrado
del parser en iOS 27.2.1.

## Diferencia con la Beta

La Beta registra un App Group firmado y un handle sobre `InternalDaemon`. Ese App Group no
pertenece a 3105 y no puede copiarse ni tratarse como autorización intercambiable. Un handle
positivo tampoco demuestra por sí mismo que todas las operaciones posteriores estén
autorizadas.

## Estados

El proveedor conserva el fallback cuando falla y diferencia `source_not_found`,
`access_denied`, `read_failed`, `invalid_header`, `unsupported_layout`, `parse_failed`,
`no_matching_records`, `validation_rejected` y `success`.

## Referencias de código

- `WQFilesIdentityResolver.resolve`: entrada y fallback.
- `WQFilesIdentityResolver.loadSnapshot`: selección de fuente y lectura.
- `WQFilesIdentityResolver.storeCandidates`: comprobación de raíces y candidatos.
- `AppDataBrowserView.reload`: integración asíncrona y comparación.

La referencia WQFiles localiza stores mediante ruta recordada y búsqueda de contenedores
`InternalDaemon`; esa búsqueda requiere acceso que la aplicación actual no demuestra tener.
