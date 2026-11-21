# Correcciones implementadas

1. `worker/index.js`: estado de acceso incluido en login V2; secretos administrativos por defecto eliminados; autorización Owner; CORS; búsqueda SQL parametrizada; renovación usa estado materializado.
2. `LoginManager.swift`: JSON inválido ya no se acepta como sesión válida.
3. `admin-panel/index.html`: errores HTTP ya no producen éxito falso.
4. `worker/tests/access-state-policy.test.mjs`: regresiones básicas de segundos, unión de causas y cero segundos.

No se modificaron los motores locales protegidos.
