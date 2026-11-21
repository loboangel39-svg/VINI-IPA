# Compatibilidad

- La activación depende de `access-state-v1` y `license_plan_enabled = 1`.
- Clientes antiguos que no envían la capacidad conservan el contrato anterior y la autoridad de `user_patches`.
- No se tocaron WQFiles, WQAccess, worse_query, ContainerStore, PatchTransaction, DevicePatchService ni el formato `.3105`.
- La modificación de `license_expires_at` durante una reanudación puede afectar cualquier cliente que comparta la licencia; por eso la regresión real con una IPA antigua queda PENDIENTE.
