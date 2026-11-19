# Informe de corrección mínima

## Cambio aplicado

Solo se añadieron diagnósticos al resolver y al flujo de Files:

- origen y disponibilidad de cada fuente;
- raíces accesibles/inaccesibles y número de candidatos;
- lectura iniciada, completada o fallida;
- parser iniciado y terminado;
- registros procesados, rechazados y coincidencias;
- archivos finalmente mostrados;
- descartes asíncronos visibles.

No se modificó el parser CSStore2 ni se añadió ninguna autorización.

## Motivo

La evidencia de iOS 27.2.1 muestra `candidates=0`, de modo que el parser no recibe datos.
Modificar offsets o validaciones en este punto no resolvería el fallo demostrado.

## Fallback

Cuando la fuente no está disponible, `resolve` devuelve un mapa vacío y
`ContainerDiscoveryMerger` conserva los contenedores UUID originales. Las identidades nuevas
solo se publican después de pasar validación de ruta, UUID, Bundle ID, conflicto y vigencia.

## Validación en dispositivo

1. Instalar la IPA del commit final, no reutilizar la instalación anterior.
2. Abrir Files y recargar el listado.
3. Confirmar `build revision`, `source origin`, `source status`, `read attempted` y
   `parser started/completed`.
4. Si `candidates=0`, la limitación sigue siendo de disponibilidad/autorización.
5. Si aparece `read status=success`, revisar los estados del parser antes de considerar una
   corrección funcional.

No fusionar la Pull Request hasta disponer de evidencia de dispositivo.
