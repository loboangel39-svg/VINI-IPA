# WQFiles + 3105: auditoría de paridad para Files

Base VINI-IPA: PR #2 (`790ec664a36b2c6e95719f383f293c8c942ead44`) más los
cambios posteriores justificados de Files. Rama: `feature/files-wqfiles-parity-pr2`.

Fuente auditada: `3105-WQFiles-source-bda9185.zip`, WQFiles 0.9.8 según
`THIRD_PARTY_NOTICES.md`.

## Grafo funcional

```text
Files inventory
├─ discovery: wq_enumerate / wq_enumerate_invalidate
│  ├─ fsgetpath + dynamic inode bound + persistent scan cache
│  └─ optional LaunchServices container-path provider
├─ authorization: wq_grant
│  ├─ ContainerManager class 7 query
│  ├─ App Group Caches swap/recovery
│  ├─ token consume/release + effective-open test
│  └─ alternate flags and LRU handles
├─ identity: wq_container_label
│  ├─ xattr com.apple.containermanager.identifier
│  ├─ LaunchServices label cache/API
│  ├─ ContainerManager classes 0,2,5,7,8,10,11,13
│  ├─ registered LaunchServices resolver
│  └─ MCM metadata plist fallback
└─ publication: WQApps.scan
   ├─ label + display name
   ├─ device/inode validation
   ├─ installed/offload state
   └─ explicit unknown identity state
```

## Matriz de dependencias

| Capacidad | WQFiles original | VINI-IPA actual | Estado | Riesgo/observación |
|---|---|---|---|---|
| Enumeración | `WQAccess.m: wq_enumerate`, dynamic bound, cache, generation | `ContainerStore.enumerateDirectories` y `bad_query_list` | Parcial | La ruta actual descubre 266 contenedores en el dispositivo; no es la causa demostrada de la pérdida de identidad |
| Invalidación | `wq_enumerate_invalidate` y generación de scan | `AppDataBrowserView.reload` vuelve a consultar fuentes | Parcial | No hay scan compartido WQFiles; no cambiar sin evidencia nueva |
| Acceso | `wq_grant`, `wq_query`, class 7, cache swap, alternate flags | `ContainerAccessCoordinator`, `bad_query`, `worse_query` | Parcial | Sustituirlo implicaría proveedor/App Group/entitlements protegidos |
| Lectura segura | `wq_list`, `wq_read`, `wq_stat`, fd-safe helpers | `FileManager`, `Data`, `attributesOfItem` | Parcial | No es necesario para publicar una identidad si el xattr es legible |
| Xattr de identidad | `WQAccess.m:3372-3386`, `getxattr(...containermanager.identifier...)` antes/después de grant | No hay `getxattr` ni `sys/xattr` en VINI-IPA | **Ausente** | Es la omisión funcional directa más clara |
| Etiquetas LS/API | `WQAccess.m:3391-3412`, identity-bound cache + resolver callback | `launchServicesStoreIdentifiers`, parser Phase1 y candidatos MHA | Parcial | El log iOS 27.2.1 muestra 0 candidatos LS |
| ContainerManager label | `wq_container_identifier_lookup`, clases múltiples | `MCMActivateContainerPath` y `readContainerMetadata` | Parcial | Dirección principal actual es Bundle ID→path, no path→Bundle ID |
| Metadata MCM | Fallback `WQAccess.m:3413-3421` | `ContainerStore.readContainerMetadata:484-502` | Equivalente parcial | El log muestra `metadata=unavailable` |
| Identidad física | `wq_label_identity`/device/inode | `FileContainerPhysicalIdentity`, `FileContainerValidation` | Parcial | No debe eliminarse ni relajarse |
| Publicación | `WQApps.m` conserva unknown y separa estados | Files ahora usa `UnidentifiedContainer` | Parcial | La nueva UI no inventa Bundle IDs ni permite parcheo |
| Cache associations | label cache ligado a identidad/generation | no existe cache equivalente | Ausente | Integrarlo requiere definir persistencia e invalidación, no copiar cache ciegamente |
| WQCache | limpieza y medición | fuera del flujo de identidad | Correctamente omitido | Toca operaciones destructivas y no aporta Bundle ID |
| WQApps backup/restore | UI y transacciones WQFiles | fuera de alcance | Correctamente omitido | Prohibido mezclar con Patches/backup/rollback |

## Diferencias de configuración y autorización

WQFiles referencia `group.cz.kolbi.wqfiles`; 3105/VINI-IPA usa su propio App
Group. No son intercambiables. WQFiles también depende de selección de flags,
cache swap y símbolos privados de ContainerManager. La presencia de un símbolo o
un token no prueba autorización efectiva.

El log del iPhone muestra que los grants individuales pueden funcionar, pero no
que sean equivalentes a la cadena completa WQFiles:

```text
worse_query granted ... write=false
metadata=unavailable
LaunchServices store total candidates=0
```

## Free Fire

El registro disponible no contiene `com.dts.freefireth` ni
`com.dts.freefiremax`, por lo que no permite asociar ninguno de los 266 UUID a
una de esas aplicaciones. Tampoco demuestra si el UUID mostrado por Erosion es
un `Data/Application` UUID o un path de `Bundle/Application`.

La comparación correcta requiere registrar, sin contenido privado:

1. path class (`Data/Application` o `Bundle/Application`);
2. validación UUID y existencia;
3. resultado del xattr;
4. resultado metadata MCM;
5. resultado de etiqueta LaunchServices;
6. Bundle ID confirmado, distinguiendo ambas variantes de Free Fire.

## Propuesta mínima por fases

1. **Fase compatible, pendiente de implementación:** añadir un adaptador de
   identidad por xattr para Files, usando el acceso ya existente y manteniendo
   `device/inode`. No modificar proveedores ni permisos.
2. Añadir estados separados `xattr_unavailable`, `metadata_unavailable`,
   `launchservices_unavailable`, `access_denied` y `resolved`.
3. Solo aceptar el valor si es un Bundle ID válido y la identidad física sigue
   correspondiendo a la ruta.
4. Mantener `UnidentifiedContainer` cuando todas las fuentes fallen.
5. Evaluar después, con evidencia física, si hace falta una consulta
   ContainerManager adicional. Esa fase requeriría aprobación específica si
   toca App Group, flags, entitlements o proveedores.

No se implementa en esta auditoría ningún mecanismo de escape, cambio de
permisos, nuevo proveedor, App Group o entitlement. Patches permanece intacto.
