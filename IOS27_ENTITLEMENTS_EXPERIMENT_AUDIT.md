# Auditoría previa: experimento de App Groups en iOS 27.2.1

## Resultado

El experimento A/B no puede ejecutarse legítimamente todavía. No existe en el repositorio
ni en la configuración disponible un App Group autorizado para el equipo que firma 3105.
Por seguridad no se creó un archivo experimental de entitlements y no se usó
`group.pigtjing.top`.

Esta rama es únicamente la rama experimental de auditoría:

`experiment/ios27-appgroup-entitlements`

## Configuración actual de 3105

En `ThreeOneOSFive.xcodeproj/project.pbxproj`, tanto Debug como Release declaran:

```text
CODE_SIGN_ENTITLEMENTS = "";
CODE_SIGN_STYLE = Automatic;
PRODUCT_BUNDLE_IDENTIFIER = "com.apple.mobile.MobileHouseArrest";
```

No hay archivos `.entitlements`, perfiles ni certificados en el repositorio. La workflow
actual compila explícitamente con:

```text
CODE_SIGNING_ALLOWED=NO
CODE_SIGNING_REQUIRED=NO
CODE_SIGN_IDENTITY=""
```

Por tanto, la IPA de CI es sin firmar y no permite comprobar entitlements efectivos de una
instalación.

## Evidencia disponible

- El código existente lee el entitlement firmado mediante `worse_query_adapter`, pero falla
  cerrado cuando no hay un App Group autorizado.
- La configuración del proyecto no declara `com.apple.security.application-groups`.
- No se dispone legítimamente de la IPA firmada de WQFiles 0.9.6 para extraer sus entitlements.
- El identificador `group.pigtjing.top` pertenece a otra firma/equipo según la evidencia
  aportada y no se puede reutilizar.

## Impedimento exacto

Para construir la Variante B se necesita que el propietario del equipo proporcione:

1. Team ID de Apple Developer que firmará 3105.
2. Un App Group registrado para ese Team ID.
3. Un perfil de aprovisionamiento que autorice ese App Group y el Bundle ID existente.
4. Una identidad de firma válida para la instalación de prueba.

No deben enviarse certificados privados, claves ni perfiles al repositorio.

## Qué no se modificó

No se modificaron el Bundle ID, entitlements originales, firma, App Groups, MHA-C2,
`bad_query`, `worse_query`, `ContainerAccessCoordinator`, Patches, Apply, Restore ni el
descubrimiento de Files.

No hay una conclusión A/B todavía: una IPA sin firma no puede probar si un App Group propio
cambia la disponibilidad de CSStore2.
