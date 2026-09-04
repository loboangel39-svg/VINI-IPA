# ============================================================
# VINI V2 - Script de Verificacion del Sistema (PowerShell)
# ============================================================
# Ejecutar en PowerShell:
#   .\verify-v2.ps1
# ============================================================

$ErrorActionPreference = "Continue"

# Colores
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

$workerUrl = "https://vini-v2-api.loboangel39.workers.dev"

# ============================================================
# VERIFICAR WORKER
# ============================================================
Write-Header "VERIFICANDO WORKER"

Write-Info "Probando endpoint /debug/storage..."
try {
    $response = Invoke-RestMethod -Uri "$workerUrl/debug/storage" -Method GET -TimeoutSec 10
    
    if ($response.worker -eq "OK") {
        Write-Success "Worker esta respondiendo"
    } else {
        Write-Err "Worker no responde correctamente"
        Write-Host "  Respuesta: $($response | ConvertTo-Json)"
    }
    
    if ($response.d1 -eq "OK") {
        Write-Success "D1 Database conectada"
    } else {
        Write-Err "D1 Database no conectada"
    }
} catch {
    Write-Err "No se pudo conectar al Worker"
    Write-Host "  Error: $_"
    Write-Host ""
    Write-Warn "Posibles causas:"
    Write-Host "  - El Worker no esta desplegado"
    Write-Host "  - La URL es incorrecta"
    Write-Host "  - No hay conexion a internet"
    exit 1
}

# ============================================================
# VERIFICAR ENDPOINTS
# ============================================================
Write-Header "VERIFICANDO ENDPOINTS"

Write-Info "Probando GET /api/app/config..."
try {
    $configResponse = Invoke-RestMethod -Uri "$workerUrl/api/app/config" -Method GET -TimeoutSec 10
    Write-Success "Endpoint /api/app/config accesible"
} catch {
    Write-Err "Error al acceder a /api/app/config"
}

# ============================================================
# VERIFICAR ADMIN PANEL
# ============================================================
Write-Header "VERIFICANDO ADMIN PANEL"

Write-Info "Probando login de admin..."
try {
    $loginBody = @{
        username = "admin"
        password = "vini2026"
    } | ConvertTo-Json
    
    $loginResponse = Invoke-RestMethod -Uri "$workerUrl/api/admin/login" -Method POST -Body $loginBody -ContentType "application/json" -TimeoutSec 10
    
    if ($loginResponse.token) {
        Write-Success "Admin login funciona"
        $token = $loginResponse.token
        
        Write-Info "Probando endpoint protegido..."
        $headers = @{
            "Authorization" = "Bearer $token"
        }
        
        try {
            $usersResponse = Invoke-RestMethod -Uri "$workerUrl/api/users" -Method GET -Headers $headers -TimeoutSec 10
            Write-Success "Endpoints protegidos funcionan"
        } catch {
            Write-Err "Error en endpoints protegidos"
        }
    } else {
        Write-Err "Admin login fallo"
        Write-Host "  Respuesta: $($loginResponse | ConvertTo-Json)"
    }
} catch {
    Write-Err "Admin login fallo"
    Write-Host "  Error: $_"
    Write-Warn "La contrasena puede ser diferente a 'vini2026'"
}

# ============================================================
# VERIFICAR APP ENDPOINTS
# ============================================================
Write-Header "VERIFICANDO APP ENDPOINTS"

Write-Warn "Los endpoints de la app requieren un usuario valido"
Write-Info "Para probar manualmente:"
Write-Host ""
Write-Host "1. Crea un usuario desde el Admin Panel"
Write-Host ""
Write-Host "2. Usa el license_key para hacer login:"
Write-Host ""
Write-Host "   Invoke-RestMethod -Uri '$workerUrl/api/app/validate-license' \"
Write-Host "     -Method POST \"
Write-Host "     -ContentType 'application/json' \"
Write-Host "     -Body '{`"licenseKey`":`"TU_LICENSE_KEY`",`"hwid`":`"test-hwid`"}'"
Write-Host ""
Write-Host "3. Usa el token retornado para probar otros endpoints:"
Write-Host ""
Write-Host "   Invoke-RestMethod -Uri '$workerUrl/api/app/patches' \"
Write-Host "     -Headers @{ 'Authorization' = 'Bearer TU_TOKEN' }"
Write-Host ""

# ============================================================
# RESUMEN
# ============================================================
Write-Header "RESUMEN DE VERIFICACION"

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  Verificacion completada" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
Write-Host "Worker URL:  $workerUrl" -ForegroundColor Cyan
Write-Host "Admin Panel: $workerUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "PROXIMOS PASOS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Si el Worker no esta desplegado, ejecuta:"
Write-Host "   .\deploy-v2.ps1"
Write-Host ""
Write-Host "2. Para probar la app iOS:"
Write-Host "   - Abre el proyecto en Xcode"
Write-Host "   - Compila y ejecuta en un dispositivo"
Write-Host "   - Inicia sesion con un license_key valido"
Write-Host ""
Write-Host "3. Para crear un usuario de prueba:"
Write-Host "   - Abre el Admin Panel en el navegador"
Write-Host "   - Ve a 'Usuarios' -> 'Nuevo Usuario'"
Write-Host "   - Copia el license_key generado"
Write-Host ""
Write-Host "4. Para crear un patch de prueba:"
Write-Host "   - Ve a 'Patches' -> 'Nuevo Patch'"
Write-Host "   - Sube un archivo .3105"
Write-Host "   - Ve a 'Accesos' -> 'Asignar Acceso'"
Write-Host "   - Asigna el patch al usuario"
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
