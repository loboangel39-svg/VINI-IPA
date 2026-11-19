# Análisis del fallo de acceso en iOS 27.2.1

Dispositivo: iPhone14,3, iOS 27.2.1 (24B156)

## Evidencia observada

```text
appgroup: usable=true
filesystem: 267 containers
CSStore2: 0 accessible sources
bundle_id: 0 additional identities
MHA-C2: 1/38 resolved
```

## Secuencia real de 3105

`AppDataBrowserView.reload` ejecuta primero metadata/API/MCM, luego
`ContainerStore.containersFromFilesystem`, después
`WQFilesIdentityResolver.resolve`. El resolver inspecciona la ruta MCM clase 10,
la ruta persistida y dos roots fallback mediante `FileManager`. Si no puede
listar los roots, termina con `candidates=0`; `Data(contentsOf:)` no se llama y
el parser no recibe bytes.

Tras esa resolución, `WQBundleIdentityCoordinator` llama a
`wq_phase1_identity_report` y `WQIdentityHealth`. El health samplea hasta ocho
contenedores con `ContainerAccessCoordinator`, pero pasa `bundleID=nil`; por
tanto esa muestra no prueba MHA-C2. El source retry solo puede operar si la
fuente ya fue localizada y su path existe.

## Causas confirmadas

1. **No disponibilidad de fuente:** el resultado histórico `candidates=0` prueba
   que el parser no fue alcanzado en esa ejecución.
2. **Dependencia de autorización:** la ruta de WQFiles encuentra stores dentro
   de `InternalDaemon` mediante `wq_enumerate`/`wq_grant`; 3105 no tiene ese
   proveedor completo en el orden de su resolver.
3. **Divergencia de flags:** WQFiles reintenta flags alternativos si el token
   consumido no abre el target; el adaptador 3105 invoca solo flags estándar.
4. **Precheck restrictivo:** `ContainerAccessCoordinator.acquire` devuelve
   error antes de invocar providers cuando `FileManager.fileExists` es falso.
   Eso puede convertir una denegación sandbox en “container does not exist”.

## Hipótesis todavía no demostradas

- Que el App Group experimental sea aceptado por el daemon con la misma
  autorización que el grupo de WQFiles. La IPA CI sin firmar no puede probarlo.
- Que `worse_query` o `bad_query` puedan abrir el contenedor de `com.apple.lsd`
  en esa instalación concreta.
- Que el store leído en WQFiles sea el mismo store/layout que el parser 3105
  espera. No hay bytes del dispositivo en la ejecución fallida.
- Que el único problema sea el source root: también pueden faltar símbolos MCM,
  token activation o permisos POSIX después de localizarlo.

## Lo que no debe atribuirse al parser

`invalid_header`, `unsupported_layout`, `no_matching_records` y
`validation_rejected` solo son diagnósticos posteriores a una lectura. Con
`candidates=0` no existe evidencia para elegir ninguno. La afirmación correcta
es “fallo de descubrimiento/autorización de fuente antes del parser”.

## Alternativas autorizadas

- Verificar con una build firmada que contenga un App Group registrado para el
  Team ID de 3105.
- Medir disponibilidad de símbolos y resultado efectivo de MHA-C2,
  `bad_query` y `worse_query` sin registrar tokens.
- Ejecutar un probe controlado sobre el propio App Group y un fixture CSStore2
  local para separar acceso autorizado de interpretación.
- Si el sistema niega la fuente privada, conservar UUIDs y reportar la
  dependencia como no reproducible; no copiar un entitlement o token de WQFiles.
