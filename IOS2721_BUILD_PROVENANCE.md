# Procedencia de build e IPA

## Historial

Cadena auditada:

```text
8fdaac4  Diagnose CSStore2 source and parser failures
  -> 880e1df  Add WQFiles resolver invocation diagnostics
  -> 5898b86  Identify diagnostic build revision accurately
  -> 7a9a871  Stamp exact diagnostic artifact revision
```

El artefacto anterior asociado a `8fdaac4` fue generado por la ejecución
`43651876880`. Su head SHA fue verificado mediante GitHub Actions; el nombre del artefacto
por sí solo no prueba procedencia.

La revisión diagnóstica posterior se identificó dentro del código mediante
`WQFilesIdentityResolver.diagnosticBuildRevision`. La última actualización de ese marcador
debe coincidir con el SHA del commit que genere la IPA final; una instalación existente no
puede verificarse sin leer sus logs o una huella del binario.

## Target

`ThreeOneOSFive.xcodeproj/project.pbxproj` contiene:

- `WQFilesIdentityResolver.swift` como `PBXFileReference`.
- `WQFilesIdentityResolver.swift in Sources` como `PBXBuildFile`.
- entrada en `PBXSourcesBuildPhase`.
- `CODE_SIGN_ENTITLEMENTS = ""`.
- `PRODUCT_BUNDLE_IDENTIFIER = "com.apple.mobile.MobileHouseArrest"`.

No existe un archivo de entitlements del proyecto que habilite un App Group. La build CI es
sin firma y no puede demostrar una autorización externa del dispositivo.

## Limitación

GitHub Actions demuestra compilación y empaquetado, no que la IPA instalada en un iPhone sea
el mismo artefacto. La verificación correcta requiere instalar el artefacto enlazado,
comprobar el marcador de revisión y observar el log de Files.
