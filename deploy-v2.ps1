# ============================================================
# VINI V2 - Script de Implementacion (PowerShell)
# ============================================================
# Ejecutar desde la raiz del repositorio VINI-IPA:
#   .\deploy-v2.ps1
# ============================================================

$ErrorActionPreference = "Stop"

function Write-Success($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Info($msg) { Write-Host "[->] $msg" -ForegroundColor Cyan }
function Write-Header($msg) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Blue
    Write-Host "  $msg" -ForegroundColor Blue
    Write-Host ("=" * 60) -ForegroundColor Blue
    Write-Host ""
}

# ============================================================
# VERIFICAR DEPENDENCIAS
# ============================================================
Write-Header "VERIFICANDO DEPENDENCIAS"

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Write-Err "Node.js no esta instalado"; exit 1 }
Write-Success "Node.js $(node --version)"

$wranglerCmd = Get-Command wrangler -ErrorAction SilentlyContinue
if (-not $wranglerCmd) { Write-Warn "Instalando wrangler..."; npm install -g wrangler }
Write-Success "Wrangler instalado"

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) { Write-Err "Git no esta instalado"; exit 1 }
Write-Success "Git $(git --version)"

# ============================================================
# VERIFICAR ESTRUCTURA
# ============================================================
Write-Header "VERIFICANDO ESTRUCTURA"

# Usar la ubicacion actual del script o el directorio actual
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = Get-Location }

$workerDir = Join-Path $scriptDir "vini-v2-cloudflare\worker"
$wranglerToml = Join-Path $workerDir "wrangler.toml"
$schemaSql = Join-Path $workerDir "schema.sql"
$workerJs = Join-Path $workerDir "index.js"

if (-not (Test-Path $wranglerToml)) {
    Write-Err "No se encontro wrangler.toml en: $wranglerToml"
    Write-Host "  Ejecuta este script desde la raiz del repositorio VINI-IPA"
    exit 1
}
Write-Success "Estructura verificada"

if (-not (Test-Path $workerJs)) { Write-Err "No se encontro index.js"; exit 1 }
Write-Success "Worker index.js encontrado"

if (-not (Test-Path $schemaSql)) { Write-Err "No se encontro schema.sql"; exit 1 }
Write-Success "Schema SQL encontrado"

# ============================================================
# CONFIGURAR WORKER
# ============================================================
Write-Header "CONFIGURANDO WORKER"

Set-Location $workerDir
Write-Info "Directorio: $workerDir"
Write-Info "Instalando dependencias..."
npm install
Write-Success "Dependencias instaladas"

# ============================================================
# LEER CONFIGURACION
# ============================================================
Write-Header "CONFIGURANDO BASE DE DATOS D1"

$tomlContent = Get-Content $wranglerToml -Raw
$dbName = ($tomlContent | Select-String 'database_name\s*=\s*"([^"]+)"').Matches.Groups[1].Value
$dbId = ($tomlContent | Select-String 'database_id\s*=\s*"([^"]+)"').Matches.Groups[1].Value

Write-Info "Database name: $dbName"
Write-Info "Database ID: $dbId"

# Verificar si la base de datos existe
Write-Info "Verificando base de datos D1..."
$d1Info = wrangler d1 info $dbName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warn "Base de datos no existe. Creando..."
    wrangler d1 create $dbName
    
    # Obtener nuevo ID
    $newInfo = wrangler d1 info $dbName 2>&1
    $newDbId = ($newInfo | Select-String 'uuid\s*[:=]\s*"([^"]+)"').Matches.Groups[1].Value
    
    if ($newDbId) {
        $newToml = $tomlContent -replace 'database_id\s*=\s*"[^"]*"', "database_id = `"$newDbId`""
        Set-Content -Path $wranglerToml -Value $newToml -NoNewline
        Write-Success "wrangler.toml actualizado"
    }
    
    Write-Info "Inicializando schema..."
    wrangler d1 execute $dbName --file=schema.sql --remote
    Write-Success "Schema aplicado"
} else {
    Write-Success "Base de datos D1 ya existe"
    
    $reinit = Read-Host "Quieres reinicializar la base de datos? (borrara todos los datos) [y/N]"
    if ($reinit -eq 'y' -or $reinit -eq 'Y') {
        Write-Warn "Reinicializando..."
        wrangler d1 execute $dbName --file=schema.sql --remote
        Write-Success "Base de datos reinicializada"
    } else {
        Write-Info "Aplicando schema..."
        wrangler d1 execute $dbName --file=schema.sql --remote
        Write-Success "Schema aplicado"
    }
}

# ============================================================
# R2 BUCKET
# ============================================================
Write-Header "CONFIGURANDO R2 STORAGE"

$bucketName = ($tomlContent | Select-String 'bucket_name\s*=\s*"([^"]+)"').Matches.Groups[1].Value
Write-Info "Bucket: $bucketName"

$bucketList = wrangler r2 bucket list 2>&1
if ($bucketList -match $bucketName) {
    Write-Success "Bucket ya existe"
} else {
    Write-Warn "Creando bucket..."
    wrangler r2 bucket create $bucketName
    Write-Success "Bucket creado"
}

# ============================================================
# VARIABLES DE ENTORNO
# ============================================================
Write-Header "CONFIGURANDO VARIABLES DE ENTORNO"

$configAdmin = Read-Host "Configurar contrasena de admin personalizada? [y/N]"
if ($configAdmin -eq 'y' -or $configAdmin -eq 'Y') {
    $adminPass = Read-Host "Ingresa la contrasena" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPass)
    $plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    echo $plainPass | wrangler secret put ADMIN_PASSWORD
    Write-Success "ADMIN_PASSWORD configurado"
} else {
    Write-Info "Usando contrasena por defecto: vini2026"
}

$configJwt = Read-Host "Configurar JWT_SECRET personalizado? [y/N]"
if ($configJwt -eq 'y' -or $configJwt -eq 'Y') {
    $jwtSecret = Read-Host "Ingresa el JWT_SECRET" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($jwtSecret)
    $plainJwt = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    echo $plainJwt | wrangler secret put JWT_SECRET
    Write-Success "JWT_SECRET configurado"
} else {
    Write-Info "Usando JWT_SECRET por defecto"
}

# ============================================================
# DESPLEGAR
# ============================================================
Write-Header "DESPEGANDO WORKER"

Write-Info "Desplegando..."
wrangler deploy
Write-Success "Worker desplegado"

Write-Info "Esperando..."
Start-Sleep -Seconds 5

# ============================================================
# VERIFICAR
# ============================================================
Write-Header "VERIFICANDO DESPLIEGUE"

$workerUrl = "https://vini-v2-api.loboangel39.workers.dev"
Write-Info "Probando $workerUrl/debug/storage ..."

try {
    $response = Invoke-RestMethod -Uri "$workerUrl/debug/storage" -Method GET -TimeoutSec 10
    if ($response.worker -eq "OK") { Write-Success "Worker funcionando" }
    else { Write-Err "Respuesta inesperada: $($response | ConvertTo-Json)" }
    if ($response.d1 -eq "OK") { Write-Success "D1 conectada" }
    else { Write-Err "D1 no conectada" }
} catch {
    Write-Err "No se pudo conectar: $_"
}

# ============================================================
# RESUMEN
# ============================================================
Write-Header "IMPLEMENTACION COMPLETADA"

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  VINI V2 implementado exitosamente" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
Write-Host "Worker URL:  $workerUrl" -ForegroundColor Cyan
Write-Host "Database:    $dbName" -ForegroundColor Cyan
Write-Host "R2 Bucket:   $bucketName" -ForegroundColor Cyan
Write-Host ""
Write-Host "PROXIMOS PASOS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Admin Panel: $workerUrl"
Write-Host "   Login: admin / vini2026"
Write-Host ""
Write-Host "2. Crea un usuario con license_key"
Write-Host ""
Write-Host "3. Crea un patch y sube un archivo .3105"
Write-Host ""
Write-Host "4. Asigna el patch al usuario"
Write-Host ""
Write-Host "5. Abre la app iOS e inicia sesion"
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""

Set-Location $scriptDir
