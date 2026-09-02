# VINI Patch Manager - Sistema Completo de Actualización Remota

Sistema completo para gestión remota de patches, control de features, mensajes broadcast y estadísticas en tiempo real para la app VINI, usando Cloudflare Pages y Workers.

## 🎯 Características

### Para Usuarios (App iOS)
- ✅ **Actualización automática de patches** sin reinstalar la app
- ✅ **Mensajes remotos** del administrador (info, alertas, actualizaciones)
- ✅ **Feature flags** que activan/desactivan funciones remotamente
- ✅ **Licencia persistente** en Keychain (sobrevive reinstalaciones)
- ✅ **Vinculación por dispositivo** (HWID) - no se puede transferir

### Para Administradores (Panel Web)
- ✅ **Dashboard en tiempo real** con estadísticas y gráficos
- ✅ **Gestión de patches** - crear, eliminar, asignar a usuarios
- ✅ **Gestión de licencias** - generar, revocar, ver estado
- ✅ **Mensajes broadcast** - enviar a todos o usuarios específicos
- ✅ **Feature flags** - activar/desactivar funciones remotamente
- ✅ **Push a GitHub** - subir patches automáticamente al repo
- ✅ **Monitoreo de usuarios** - ver dispositivos, iOS, última conexión

## 📁 Estructura del Proyecto

```
vini-patch-system/
├── admin-panel/              # Panel de administración web
│   ├── index.html           # Interfaz principal
│   └── app.js               # Lógica del panel
│
├── worker/                   # Cloudflare Worker (API backend)
│   ├── index.js             # API completa
│   ├── schema.sql           # Schema de base de datos
│   └── wrangler.toml        # Configuración
│
├── app-integration/          # Archivos para la app iOS
│   ├── RemotePatchService.swift      # Comunicación con Worker
│   ├── PatchSyncService.swift        # Sincronización de patches
│   ├── RemotePatchesView.swift       # UI de patches remotos
│   ├── KeychainManager.swift         # Licencia persistente
│   ├── RemoteConfigService.swift     # Remote config & features
│   └── INTEGRATION_GUIDE.swift       # Guía de integración
│
├── .github/workflows/        # CI/CD
│   ├── deploy-admin.yml     # Deploy admin panel
│   └── deploy-worker.yml    # Deploy worker
│
├── setup.sh                  # Script de setup automático
├── IMPLEMENTACION.md         # Guía completa de implementación
└── README.md                 # Este archivo
```

## 🚀 Quick Start

### Opción 1: Setup Automático
```bash
chmod +x setup.sh
./setup.sh
```

### Opción 2: Setup Manual
Sigue la [guía completa de implementación](IMPLEMENTACION.md)

## 🔧 Configuración Rápida

### 1. Cloudflare
```bash
# Instalar Wrangler
npm install -g wrangler

# Login
wrangler login

# Crear recursos
wrangler d1 create vini-patch-db
wrangler r2 bucket create vini-patches
wrangler kv:namespace create VINI_CONFIG

# Setear secrets
wrangler secret put ADMIN_PASSWORD_HASH
wrangler secret put JWT_SECRET
wrangler secret put GITHUB_TOKEN
```

### 2. Deploy Worker
```bash
cd worker
wrangler d1 execute vini-patch-db --file=schema.sql
wrangler deploy
```

### 3. Deploy Admin Panel
1. Ve a Cloudflare Dashboard > Pages
2. Create project > Connect to Git
3. Selecciona tu repo
4. Build output: `admin-panel`
5. Deploy

### 4. Integrar en App iOS
Copia los archivos de `app-integration/` a tu proyecto Xcode:
- `helpers/`: RemotePatchService, PatchSyncService, KeychainManager, RemoteConfigService
- `views/`: RemotePatchesView

Configura la URL del Worker:
```swift
RemotePatchService.shared.baseURL = "https://tu-worker.workers.dev"
```

## 📊 API Endpoints

### App (iOS)
```
POST /api/app/validate-license     - Validar licencia
GET  /api/app/config               - Remote config
GET  /api/app/patches              - Lista de patches
GET  /api/app/patches/:id          - Descargar patch
POST /api/app/telemetry            - Enviar telemetría
POST /api/app/messages/:id/ack     - Acknowledge mensaje
```

### Admin
```
POST /api/admin/login              - Login admin
GET  /api/patches                  - Lista patches
POST /api/patches                  - Crear patch
GET  /api/users                    - Lista usuarios
PUT  /api/users/:hwid/patches      - Asignar patches
GET  /api/licenses                 - Lista licencias
POST /api/licenses                 - Generar licencia
GET  /api/messages                 - Lista mensajes
POST /api/messages                 - Crear mensaje
GET  /api/config                   - Remote config
PUT  /api/config                   - Actualizar config
GET  /api/stats                    - Estadísticas
GET  /api/stats/realtime           - Stats tiempo real
```

## 🔐 Seguridad

- **Licencias vinculadas por HWID** - No se pueden transferir
- **Keychain con `ThisDeviceOnly`** - Sobrevive reinstalaciones pero no backups
- **JWT tokens** - Autenticación segura
- **CORS configurado** - Solo tu dominio
- **Secrets en Cloudflare** - Nunca en el código

## 📈 Estadísticas

El dashboard muestra en tiempo real:
- Usuarios activos
- Licencias activas
- Total de patches
- Descargas hoy
- Gráfico de actividad (24h)
- Distribución de dispositivos
- Eventos recientes

## 🎛️ Feature Flags

Ejemplos de uso:
```swift
// En la app
if RemoteConfigService.shared.isFeatureEnabled("cleaner") {
    // Mostrar tab de cleaner
}

let maxFileSize = RemoteConfigService.shared.settingValue("maxFileSize", default: 100)
```

Desde el panel admin puedes:
- Crear feature flags
- Activar/desactivar sin actualizar la app
- Configurar valores remotamente

## 💬 Mensajes Broadcast

Tipos de mensajes:
- `info` - Información general
- `warning` - Advertencias
- `error` - Errores críticos
- `success` - Confirmaciones
- `update` - Actualizaciones disponibles

Puedes enviar a:
- Todos los usuarios
- Usuario específico (por HWID)

## 🔄 Sincronización

La app sincroniza automáticamente:
- Cada 5 minutos en background
- Al abrir la app
- Al volver de background

El usuario ve:
- Notificación de nuevos patches
- Badge de actualizaciones disponibles
- Mensajes no leídos

## 🛠️ Troubleshooting

### Worker no responde
```bash
wrangler tail
```

### Error de base de datos
```bash
wrangler d1 execute vini-patch-db --command="SELECT * FROM patches;"
```

### Admin panel no carga
Verifica la variable `WORKER_URL` en Cloudflare Pages.

### La app no se conecta
Verifica que `RemotePatchService.shared.baseURL` esté correcto.

## 📝 Licencia

Este sistema es para uso con VINI IPA.

## 🤝 Soporte

Para issues o preguntas, abre un issue en el repo de GitHub.

---

**Hecho con ❤️ para VINI**
