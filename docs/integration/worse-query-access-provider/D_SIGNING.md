# D. Informe de firma, Bundle ID y App Group

## 1. Identidad existente (sin cambios)

| Elemento | Valor |
|---|---|
| Bundle ID | `com.apple.mobile.MobileHouseArrest` |
| `CFBundleDisplayName` / `CFBundleName` | `VINI` |
| Versión | `1.1.1` (build `7`) |
| Deployment target | iOS 16.0 |
| `CODE_SIGN_ENTITLEMENTS` (Debug) | vacío (`""`) |
| `CODE_SIGN_ENTITLEMENTS` (Release) | vacío (`""`) |
| Archivos `.entitlements` en el repositorio | ninguno |
| Provisioning profiles en el repositorio | ninguno |

El Bundle ID y los ajustes de firma no se modificaron.

## 2. App Group observado frente a App Group autorizado

- `group.pigtjing.top` aparece como **referencia observada en pruebas
  anteriores**, no como un grupo autorizado por este repositorio.
- No está presente en ningún entitlement efectivo del proyecto actual.
- No se añadió, no se codificó y no se usó como valor por defecto.
- No se creó un `.entitlements` nuevo ni se tocó `CODE_SIGN_ENTITLEMENTS`.

`worse_query` exige un App Group que la firma real autorice. Para no falsificar
esa condición, el adaptador llama a `WQAuthorizedAppGroup()`:

1. Lee el entitlement efectivo `com.apple.security.application-groups` del
   proceso firmado.
2. Recorre sólo grupos con prefijo `group.`.
3. Comprueba que `containerURLForSecurityApplicationGroupIdentifier:` devuelve
   un contenedor alcanzable.
4. Si no hay ninguno, devuelve `nil` y `worse_query` queda **no disponible**.

Esto es una lectura de entitlements propios, no una petición de privilegios ni
una ampliación de capacidades.

## 3. Entitlements requeridos por el upstream

El proyecto original de `worse_query` incluye:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.cc.forcequit.worse-query</string>
</array>
```

Ese identificador pertenece al autor del upstream y **no** se usa aquí.
La integración no requiere ningún otro entitlement de `worse_query`: el resto
del acceso se obtiene mediante la extensión sandbox emitida por
containermanager.

## 4. Estado de firma de la compilación experimental

- El workflow `WorseQuery access provider validation` compila con
  `CODE_SIGNING_ALLOWED=NO` y `CODE_SIGNING_REQUIRED=NO`.
- Genera un IPA **sin firmar** para inspección, no para instalar en un
  dispositivo.
- No se dispone en este entorno de un certificado, equipo de desarrollo ni
  provisioning profile autorizado para un App Group.
- No se falsificó la firma ni se inyectaron entitlements.

## 5. Bloqueo documentado

**BLOQUEO DE FIRMA:** el repositorio y el perfil disponible no autorizan ningún
App Group. Por tanto:

- `WQAuthorizedAppGroup()` devolverá `nil` en una compilación estándar.
- `worse_query` no se intentará (`worseQueryAvailable = false`).
- Files y Patches conservan el comportamiento original.
- La validación real del proveedor en dispositivo queda **PENDIENTE**.

Para habilitarlo haría falta, fuera de este repositorio y con aprobación
explícita:

1. Un App Group registrado para el equipo de desarrollo.
2. Un provisioning profile que lo incluya.
3. `com.apple.security.application-groups` en los entitlements de la firma
   experimental.
4. Verificar que el contenedor del grupo es alcanzable en el dispositivo.

No se debe reutilizar `group.pigtjing.top` sin esa autorización.

## 6. Material sensible

Este informe no incluye certificados, claves privadas, contraseñas, tokens de
API ni contenido de provisioning profiles.
