# Correcciones implementadas

1. `worker/index.js`: estado de acceso incluido en login V2; secretos administrativos por defecto eliminados; autorización Owner; CORS; búsqueda SQL parametrizada; renovación usa estado materializado.
2. `LoginManager.swift`: JSON inválido ya no se acepta como sesión válida.
3. `admin-panel/index.html`: errores HTTP ya no producen éxito falso.
4. `worker/tests/access-state-policy.test.mjs`: regresiones básicas de segundos, unión de causas y cero segundos.
5. `admin-panel/index.html`: controles movidos a la sección Accesos, con estados explícitos y carga independiente de Usuarios.
6. `App.swift`/`index.js`: estado de acceso explícito para clientes con capacidad; no se sincronizan parches cuando existe bloqueo.

No se modificaron los motores locales protegidos.
