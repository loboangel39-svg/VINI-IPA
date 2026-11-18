# Auditoría del upstream `worse_query`

## 1. Fuente

| Elemento | Valor |
|---|---|
| Repositorio | `https://github.com/forcequitOS/worse_query` |
| Commit vendorizado | `d1540e20cd82b974d891e0551ced6d6aeb570ac2` |
| Archivos usados | `worse_query/worse_query.h`, `worse_query/worse_query.m` |
| Licencia | GNU GPL v3 |
| Modificaciones al motor | ninguna |

## 2. Interfaz pública

```c
int64_t worse_query(NSString *path, NSString *group, bool alt_flags, bool create_dir);
void worse_query_release(int64_t handle);
```

No hay estado global, inicialización, singleton ni recursos que cargar. La
función devuelve un handle de extensión sandbox o un código negativo.

## 3. Dependencias

- `Foundation` (`NSFileManager`, `NSString`).
- `dlopen`/`dlsym` sobre `/usr/lib/system/libsystem_containermanager.dylib`.
- `xpc` para los identificadores de App Group.
- `sandbox_extension_consume` / `sandbox_extension_release` desde `RTLD_DEFAULT`.
- `lstat` para comprobar que el destino existe.

No enlaza frameworks privados de forma estática; resuelve símbolos en runtime.

## 4. Requisitos

| Requisito | Detalle |
|---|---|
| App Group | Obligatorio. Debe existir, estar autorizado por la firma y ser alcanzable. |
| Entitlement | `com.apple.security.application-groups` con ese grupo. |
| Ruta destino | Debe existir si `create_dir == false`. |
| iOS | README del upstream: 26.0–26.7.2 y 27.2. |
| Flags | `alt_flags = true` para contenedores App Group en iOS 26.x. |

## 5. Obtención y uso del acceso

1. `containerURLForSecurityApplicationGroupIdentifier:` obtiene la raíz del
   App Group.
2. Se elimina `Library/Caches` y se reemplaza por un symlink al destino.
3. `container_query_create` + clase 7 + identificador de grupo + part 3.
4. `container_query_operation_set_flags` con los flags alternativos o estándar.
5. `container_query_get_single_result` y `container_copy_sandbox_token`.
6. `sandbox_extension_consume(token)` devuelve el handle.
7. Se libera la query, se restaura `Library/Caches` y se devuelve el handle.

El token es una **extensión sandbox para la ruta destino**. No es un JWT, no
autentica una sesión y no concede acceso kernel.

## 6. Códigos de error

| Código | Significado |
|---|---|
| `-255` | El destino no existe y `create_dir` es false. |
| `-1` | App Group inexistente o inaccesible. |
| `-2` | `dlopen` o símbolos no disponibles. |
| `-3` | No se pudo crear la query. |
| `-4` | No se pudo crear el symlink de `Library/Caches`. |
| `-5` | containermanagerd rechazó la query. |
| `-6` | No se emitió token sandbox. |
| otro negativo | `sandbox_extension_consume` falló. |

## 7. Manejo de errores y ciclo de vida

- El adaptador trata cualquier handle negativo como fallo y **no** lo convierte
  en éxito.
- El handle se libera con `worse_query_release` o con
  `bad_query_release` (ambos llaman a `sandbox_extension_release`).
- `WorseQueryAccessProvider` serializa las llamadas con `NSLock` porque el
  upstream comparte y reemplaza un único `Library/Caches` dentro del App Group.
- Si la verificación `access(2)` falla, el handle se libera inmediatamente.

## 8. Conflictos posibles

| Componente | Relación |
|---|---|
| `bad_query` | Ambos consumen extensiones sandbox. Se intentan en secuencia, nunca a la vez. `bad_query` sigue intacto. |
| MHA-C2 / MCM | MCM conserva su lease y su ruta autoritativa. `worse_query` no sustituye la consulta MCM ni sus metadatos. |
| `kexploit_opa334` / `sandbox_escape` | Independientes. `worse_query` no usa kernel R/W ni lo reemplaza. |
| App Group `Library/Caches` | El upstream borra y recrea `Caches`; es un efecto secundario real. En VINI no hay App Group configurado, así que hoy no ocurre. |
| Otros apps del mismo App Group | El symlink compartido puede interferir. El lock evita concurrencia dentro de VINI, no entre procesos distintos. |

## 9. Comparación con WQFiles

Revisión de referencia: `kolbicz/WQFiles` commit
`985cf765cdf3bd4cb88da15de3f7d928664efae6`.

WQFiles confirma el mismo modelo:

- Selecciona el App Group con `SecTaskCopyValueForEntitlement`.
- Concede acceso **por ruta** (`wq_grant`), no por Bundle ID.
- Usa enumeración por inodos para descubrir contenedores.
- En iOS 26, `worse_query` alcanza contenedores individuales, no los
  directorios padre de sistema ni el padre de App Groups.
- Repara el estado de `Library/Caches` con renombrados en lugar de asumir que
  siempre está limpio.

La integración en VINI adopta únicamente el modelo de “concesión por ruta” y
la lectura del App Group efectivo. No copia el motor de Files de WQFiles, su
catálogo, su UI ni su política de backups.

## 10. Licencia y distribución — BLOQUEO

`worse_query` es **GPL-3.0**. El repositorio VINI-IPA no contiene un archivo
`LICENSE` que establezca una licencia compatible. Incorporar y distribuir un
binario que enlaza este código puede obligar a distribuir el conjunto bajo
GPL-3.0.

Consecuencias:

- La rama es válida para auditoría, compilación interna y revisión técnica.
- **No** debe publicarse una versión comercial ni distribuirse un IPA que
  incluya este código hasta resolver la licencia.
- Este PR no publica release ni modifica el backend de licencias.

Esta condición se documenta como bloqueo; no se elimina el aviso de licencia
ni se atribuye el código a VINI.
