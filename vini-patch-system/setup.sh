#!/bin/bash
# VINI Patch Manager - Setup Script
# Ejecuta este script para configurar todo el sistema

set -e

echo "🚀 VINI Patch Manager - Setup"
echo "=============================="
echo ""

# Verificar wrangler
if ! command -v wrangler &> /dev/null; then
    echo "📦 Instalando Wrangler CLI..."
    npm install -g wrangler
fi

# Login
echo "🔐 Login en Cloudflare..."
wrangler login

# Crear recursos
echo ""
echo "📊 Creando D1 Database..."
DB_OUTPUT=$(wrangler d1 create vini-patch-db 2>&1 || true)
DB_ID=$(echo "$DB_OUTPUT" | grep -o 'database_id = "[^"]*"' | cut -d'"' -f2 || echo "")

if [ -z "$DB_ID" ]; then
    echo "⚠️  Database ya existe o error. Obteniendo ID..."
    DB_ID=$(wrangler d1 list | grep vini-patch-db | awk '{print $2}' || echo "NEEDS_MANUAL_SETUP")
fi

echo "✅ Database ID: $DB_ID"

echo ""
echo "🗄️  Creando R2 Bucket..."
wrangler r2 bucket create vini-patches 2>&1 || echo "⚠️  Bucket ya existe"

echo ""
echo "📝 Creando KV Namespace..."
KV_OUTPUT=$(wrangler kv:namespace create VINI_CONFIG 2>&1 || true)
KV_ID=$(echo "$KV_OUTPUT" | grep -o '[a-f0-9]{32}' | head -1 || echo "NEEDS_MANUAL_SETUP")

echo "✅ KV Namespace ID: $KV_ID"

# Actualizar wrangler.toml
echo ""
echo "⚙️  Actualizando wrangler.toml..."
cd worker
sed -i.bak "s/TU_DATABASE_ID_AQUI/$DB_ID/g" wrangler.toml
sed -i.bak "s/TU_KV_NAMESPACE_ID_AQUI/$KV_ID/g" wrangler.toml
rm -f wrangler.toml.bak

# Setear secrets
echo ""
echo "🔑 Configurando secrets..."
echo ""
read -p "Password para admin (se hasheará con SHA-256): " ADMIN_PASS
ADMIN_HASH=$(echo -n "$ADMIN_PASS" | shasum -a 256 | awk '{print $1}')
echo "$ADMIN_HASH" | wrangler secret put ADMIN_PASSWORD_HASH

JWT_SECRET=$(openssl rand -hex 32)
echo "$JWT_SECRET" | wrangler secret put JWT_SECRET

read -p "GitHub Personal Access Token: " GITHUB_TOKEN
echo "$GITHUB_TOKEN" | wrangler secret put GITHUB_TOKEN

# Inicializar DB
echo ""
echo "📋 Inicializando base de datos..."
wrangler d1 execute vini-patch-db --file=schema.sql

# Deploy Worker
echo ""
echo "🚀 Deployando Worker..."
wrangler deploy

WORKER_URL=$(wrangler deployments list | head -1 | grep -o 'https://[^ ]*' || echo "CHECK_DASHBOARD")
echo "✅ Worker URL: $WORKER_URL"

cd ..

# Resumen
echo ""
echo "=============================="
echo "✅ SETUP COMPLETADO"
echo "=============================="
echo ""
echo "📋 Próximos pasos:"
echo ""
echo "1. Ve a Cloudflare Dashboard > Workers & Pages"
echo "2. Crea un proyecto Pages:"
echo "   - Conecta tu repo de GitHub"
echo "   - Build output: admin-panel"
echo "   - Project name: vini-admin"
echo ""
echo "3. En la app iOS, configura:"
echo "   RemotePatchService.shared.baseURL = \"$WORKER_URL\""
echo ""
echo "4. Agrega estos secrets a GitHub Actions:"
echo "   - CLOUDFLARE_API_TOKEN"
echo "   - CLOUDFLARE_ACCOUNT_ID"
echo ""
echo "5. Login al admin panel con:"
echo "   Usuario: admin"
echo "   Password: (el que configuraste)"
echo ""
echo "🎉 ¡Listo!"
