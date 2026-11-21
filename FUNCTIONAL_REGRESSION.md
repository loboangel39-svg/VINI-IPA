# Regresión funcional

## Verificado estáticamente

- La función `shouldSynchronizeRemotePatches(for:)` conserva `access == nil` y `active` como permitidos.
- `license_paused`, `maintenance`, `expired` y `unauthorized` continúan bloqueando sincronización.
- No se modificaron `RemotePatchService`, `RemotePatchImportCoordinator`, `PatchDownloadService`, `PatchTransaction` ni el formato `.3105`.
- La navegación de pestañas, nombres, orden y destinos no fue modificada.

## Pendiente

Login real, restauración JWT, catálogo remoto, descarga `.3105`, Installed, pausa/mantenimiento en dispositivo y regresión con Worker antiguo requieren dispositivo o staging. No se declara PASS para esas pruebas sin ejecución real.
