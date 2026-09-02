# VINI Patch Manager - Guía de Implementación Completa

## Arquitectura del Sistema

```
┌─────────────────┐
│   iOS App       │
│   (VINI)        │
└────────┬────────┘
         │
         │ HTTPS
         │
┌────────▼────────────────────────────────────────┐
│  Cloudflare Worker (API Backend)                │
│  - Validación de licencias                      │
│  - Gestión de patches                           │
│  - Remote Config & Feature Flags                │
│  - Mensajes broadcast                           │
│  - Telemetría y estadísticas                    │
└────────┬────────────────────────────────────────┘
         │
    ┌────┴────┬──────────┬──────────┐
    │         │          │          │
┌───▼───┐ ┌──▼───┐ ┌───▼───┐ ┌───▼───┐
│ D1 DB │ │ R2   │ │ KV    │ │GitHub │
│       │ │      │ │       │ │  API  │
└───────┘ └──────┘ └───────┘ └───────┘

┌─────────────────┐
│  Admin Panel    │
│  (Cloudflare    │
│   Pages)        │
└─────────────────┘
```

## Paso 1: Configurar Cloudflare

### 1.1 Crear cuenta y proyecto
1. Ve a [cloudflare.com](https://cloudflare.com) y crea una cuenta
2. Verifica tu email

### 1.2 Crear D1 Database
```bash
# Instalar Wrangler CLI
npm install -g wrangler

# Login
wrangler login

# Crear database
wrangler d1 create vini-patch-db

# Copiar el database_id que te da
```

### 1.3 Crear R2 Bucket
```bash
wrangler r2 bucket create vini-patches
```

### 1.4 Crear KV Namespace
```bash
wrangler kv:namespace create VINI_CONFIG

# Copiar el namespace_id que te da
```

### 1.5 Configurar secrets
```bash
# Generar password hash (SHA-256 de tu password)
echo -n "tu_password_admin" | shasum -a 256 | awk '{print $1}'

# Setear secrets
wrangler secret put ADMIN_PASSWORD_HASH
# Pega el hash generado

wrangler secret put JWT_SECRET
# Genera uno: openssl rand -hex 32

wrangler secret put GITHUB_TOKEN
# Tu Personal Access Token de GitHub
```

### 1.6 Actualizar wrangler.toml
Edita `worker/wrangler.toml` con los IDs que obtuviste:
```toml
database_id = "TU_DATABASE_ID_AQUI"
namespace_id = "TU_KV_NAMESPACE_ID_AQUI"
```

### 1.7 Inicializar base de datos
```bash
cd worker
wrangler d1 execute vini-patch-db --file=schema.sql
```

### 1.8 Deploy del Worker
```bash
wrangler deploy
```

Copia la URL del Worker (ej: `https://vini-patch-worker.tu-subdomain.workers.dev`)

## Paso 2: Deploy del Admin Panel

### 2.1 Crear proyecto en Cloudflare Pages
1. Ve a Cloudflare Dashboard > Workers & Pages > Pages
2. Click "Create a project" > "Connect to Git"
3. Selecciona tu repo de GitHub
4. Configura:
   - **Project name**: `vini-admin`
   - **Production branch**: `main`
   - **Build output directory**: `admin-panel`
5. Deploy

### 2.2 Configurar variable de entorno
En Cloudflare Pages > Settings > Environment variables:
- `WORKER_URL`: URL de tu Worker

## Paso 3: Configurar GitHub Actions

### 3.1 Agregar secrets al repo
En tu repo de GitHub > Settings > Secrets and variables > Actions:

| Secret | Valor |
|--------|-------|
| `CLOUDFLARE_API_TOKEN` | Token de Cloudflare (crear en My Profile > API Tokens) |
| `CLOUDFLARE_ACCOUNT_ID` | Tu Account ID (en Cloudflare Dashboard) |

### 3.2 Token de Cloudflare
1. Ve a [dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Create Token > "Edit Cloudflare Workers" template
3. Permisos necesarios:
   - Account > Cloudflare D1 > Edit
   - Account > Cloudflare R2 > Edit
   - Account > Cloudflare KV > Edit
   - Zone > Cloudflare Pages > Edit
   - Zone > Cloudflare Workers > Edit

## Paso 4: Integrar en la App iOS

### 4.1 Copiar archivos Swift
Copia estos archivos a tu proyecto Xcode:

```
app-integration/
├── RemotePatchService.swift      → helpers/
├── PatchSyncService.swift        → helpers/
├── RemotePatchesView.swift       → views/
├── KeychainManager.swift         → helpers/
└── RemoteConfigService.swift     → helpers/
```

### 4.2 Modificar App.swift

Reemplaza el sistema actual de login con `LicenseSessionManager`:

```swift
@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var sessionManager = LicenseSessionManager.shared
    @StateObject private var remoteConfig = RemoteConfigService.shared
    @StateObject private var patchSync = PatchSyncService.shared
    
    // ... resto del código
    
    var body: some Scene {
        WindowGroup {
            Group {
                if sessionManager.isLoggedIn {
                    mainContent
                } else {
                    LoginView { license, expiresAt in
                        Task {
                            do {
                                try await sessionManager.login(licenseKey: license)
                            } catch {
                                // Handle error
                            }
                        }
                    }
                }
            }
            .environmentObject(remoteConfig)
            .environmentObject(patchSync)
        }
    }
}
```

### 4.3 Agregar Remote Patches Tab

En `ContentView.swift`, agrega la pestaña de patches remotos:

```swift
RemotePatchesView()
    .tabItem {
        Label("Remotos", systemImage: "cloud.download")
    }
```

### 4.4 Configurar Worker URL

En el primer launch, configura la URL del Worker:

```swift
RemotePatchService.shared.baseURL = "https://vini-patch-worker.tu-subdomain.workers.dev"
```

O guárdalo en el panel de Settings de la app.

## Paso 5: Verificar Funcionamiento

### 5.1 Test del Worker
```bash
curl https://tu-worker.workers.dev/api/app/check-updates?currentVersion=1.1.1
```

### 5.2 Test del Admin Panel
1. Abre tu URL de Cloudflare Pages
2. Login con `admin` / tu password
3. Genera una licencia
4. Crea un patch
5. Asigna el patch a un usuario

### 5.3 Test en la App
1. Abre VINI
2. Ingresa la licencia generada
3. Verifica que se sincronicen los patches remotos
4. Verifica que aparezcan los mensajes broadcast

## API Endpoints

### App (iOS)
| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/api/app/validate-license` | POST | Validar licencia |
| `/api/app/config` | GET | Obtener remote config |
| `/api/app/patches` | GET | Lista de patches asignados |
| `/api/app/patches/:id` | GET | Descargar patch |
| `/api/app/telemetry` | POST | Enviar telemetría |
| `/api/app/messages/:id/ack` | POST | Acknowledge mensaje |

### Admin
| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/api/admin/login` | POST | Login admin |
| `/api/patches` | GET/POST | CRUD patches |
| `/api/users` | GET | Lista usuarios |
| `/api/users/:hwid/patches` | PUT | Asignar patches |
| `/api/licenses` | GET/POST | CRUD licencias |
| `/api/messages` | GET/POST | CRUD mensajes |
| `/api/config` | GET/PUT | Remote config |
| `/api/stats` | GET | Estadísticas |
| `/api/stats/realtime` | GET | Stats en tiempo real |

## Características Implementadas

### ✅ Actualización Remota de Patches
- Los patches se sincronizan automáticamente cada 5 minutos
- Notificación de actualizaciones disponibles
- Descarga selectiva por usuario

### ✅ Control de Features Remoto
- Feature flags configurables desde el panel admin
- Activar/desactivar features sin actualizar la app
- Valores configurables remotamente

### ✅ Mensajes Broadcast
- Enviar mensajes a todos los usuarios o específicos
- Tipos: info, warning, error, success, update
- Acknowledge tracking

### ✅ Estadísticas en Tiempo Real
- Usuarios activos
- Descargas de patches
- Dispositivos y versiones iOS
- Gráficos de actividad (24h)

### ✅ Licencia Persistente con Keychain
- La licencia se guarda en Keychain (sobrevive reinstalaciones)
- Vinculada al HWID del dispositivo
- No se puede transferir a otro dispositivo

### ✅ Push a GitHub Automático
- Los patches se suben automáticamente al repo
- Workflow de GitHub Actions para deploy

## Troubleshooting

### Worker no responde
```bash
wrangler tail
```

### Error de base de datos
```bash
wrangler d1 execute vini-patch-db --command="SELECT * FROM patches;"
```

### Admin panel no carga
Verifica que la variable `WORKER_URL` esté configurada en Cloudflare Pages.

### La app no se conecta
Verifica que `RemotePatchService.shared.baseURL` esté configurado correctamente.

## Próximos Pasos

1. **Testing completo**: Prueba todos los flujos en un dispositivo real
2. **Monitoreo**: Configura alertas en Cloudflare
3. **Backups**: Configura backups automáticos de D1
4. **Escalado**: Considera Cloudflare Queues para tareas pesadas
