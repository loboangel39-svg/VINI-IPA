/**
 * VINI Patch Manager - Cloudflare Worker API v3
 * 
 * Arquitectura: Descarga única + verificación remota
 * - Los patches se descargan UNA VEZ cuando se asignan
 * - Se quedan en el dispositivo
 * - Solo se verifica versión y contraseña con el worker
 * - Si hay nueva versión, se descarga de nuevo
 */

export default {
    async fetch(request, env) {
        const url = new URL(request.url);
        const path = url.pathname;
        const method = request.method;

        // CORS
        if (method === 'OPTIONS') {
            return new Response(null, { headers: corsHeaders() });
        }

        try {
            // ========== APP ROUTES (iOS App) ==========
            
            // License validation
            if (path === '/api/app/validate-license' && method === 'POST') {
                return await handleValidateLicense(request, env);
            }

            // Remote config (feature flags, messages, settings)
            if (path === '/api/app/config' && method === 'GET') {
                return await handleGetRemoteConfig(request, env);
            }

            // Check for updates - NUEVO: verifica qué patches necesitan actualización
            if (path === '/api/app/check-updates' && method === 'POST') {
                return await handleCheckUpdates(request, env);
            }

            // Patch list for user (solo metadata, no descarga)
            if (path === '/api/app/patches' && method === 'GET') {
                return await handleAppListPatches(request, env);
            }

            // Patch download (solo cuando se asigna o hay actualización)
            if (path.startsWith('/api/app/patches/') && method === 'GET') {
                return await handleAppDownloadPatch(request, env);
            }

            // Telemetry
            if (path === '/api/app/telemetry' && method === 'POST') {
                return await handleTelemetry(request, env);
            }

            // Acknowledge message
            if (path.startsWith('/api/app/messages/') && path.endsWith('/ack') && method === 'POST') {
                return await handleAckMessage(request, env);
            }

            // ========== ADMIN ROUTES ==========
            
            // Admin login
            if (path === '/api/admin/login' && method === 'POST') {
                return await handleAdminLogin(request, env);
            }

            // All routes below require admin auth
            const admin = await verifyAdminAuth(request, env);
            if (!admin) {
                return jsonResponse({ error: 'Unauthorized' }, 401);
            }

            // Patches CRUD
            if (path === '/api/patches' && method === 'GET') {
                return await handleListPatches(request, env);
            }
            if (path === '/api/patches' && method === 'POST') {
                return await handleCreatePatch(request, env);
            }
            if (path.match(/^\/api\/patches\/[^/]+$/) && method === 'DELETE') {
                return await handleDeletePatch(request, env);
            }
            if (path.match(/^\/api\/patches\/[^/]+\/push-github$/) && method === 'POST') {
                return await handlePushToGitHub(request, env);
            }

            // Users
            if (path === '/api/users' && method === 'GET') {
                return await handleListUsers(request, env);
            }
            if (path.match(/^\/api\/users\/[^/]+$/) && method === 'PUT') {
                return await handleUpdateUser(request, env);
            }
            if (path.match(/^\/api\/users\/[^/]+\/patches$/) && method === 'PUT') {
                return await handleAssignPatches(request, env);
            }

            // Licenses
            if (path === '/api/licenses' && method === 'GET') {
                return await handleListLicenses(request, env);
            }
            if (path === '/api/licenses' && method === 'POST') {
                return await handleGenerateLicense(request, env);
            }
            if (path === '/api/licenses/unbind-all' && method === 'POST') {
                return await handleUnbindAllLicenses(request, env);
            }
            if (path.match(/^\/api\/licenses\/[^/]+\/unbind$/) && method === 'POST') {
                return await handleUnbindLicense(request, env);
            }
            if (path.match(/^\/api\/licenses\/[^/]+\/delete$/) && method === 'DELETE') {
                return await handleDeleteLicense(request, env);
            }
            if (path.match(/^\/api\/licenses\/[^/]+$/) && method === 'DELETE') {
                return await handleRevokeLicense(request, env);
            }

            // Remote Config (Admin)
            if (path === '/api/config' && method === 'GET') {
                return await handleGetConfig(request, env);
            }
            if (path === '/api/config' && method === 'PUT') {
                return await handleUpdateConfig(request, env);
            }

            // Messages (Admin)
            if (path === '/api/messages' && method === 'GET') {
                return await handleListMessages(request, env);
            }
            if (path === '/api/messages' && method === 'POST') {
                return await handleCreateMessage(request, env);
            }
            if (path.match(/^\/api\/messages\/[^/]+$/) && method === 'DELETE') {
                return await handleDeleteMessage(request, env);
            }

            // Statistics
            if (path === '/api/stats' && method === 'GET') {
                return await handleGetStats(request, env);
            }
            if (path === '/api/stats/realtime' && method === 'GET') {
                return await handleGetRealtimeStats(request, env);
            }

            // Banners
            if (path === '/api/banners' && method === 'GET') {
                return await handleListBanners(request, env);
            }
            if (path === '/api/banners' && method === 'POST') {
                return await handleCreateBanner(request, env);
            }
            if (path.match(/^\/api\/banners\/[^/]+$/) && method === 'DELETE') {
                return await handleDeleteBanner(request, env);
            }

            // Versions
            if (path === '/api/versions' && method === 'GET') {
                return await handleListVersions(request, env);
            }
            if (path === '/api/versions' && method === 'POST') {
                return await handleCreateVersion(request, env);
            }
            if (path.match(/^\/api\/versions\/[^/]+$/) && method === 'DELETE') {
                return await handleDeleteVersion(request, env);
            }

            // Logs
            if (path === '/api/logs' && method === 'GET') {
                return await handleGetLogs(request, env);
            }
            if (path === '/api/logs' && method === 'DELETE') {
                return await handleClearLogs(request, env);
            }

            // Security
            if (path === '/api/security' && method === 'GET') {
                return await handleGetSecurity(request, env);
            }
            if (path === '/api/security/block-ip' && method === 'POST') {
                return await handleBlockIP(request, env);
            }
            if (path === '/api/security/unblock-ip' && method === 'POST') {
                return await handleUnblockIP(request, env);
            }
            if (path === '/api/security/rate-limit' && method === 'POST') {
                return await handleSaveRateLimit(request, env);
            }
            if (path === '/api/security/api-keys' && method === 'POST') {
                return await handleGenerateAPIKey(request, env);
            }
            if (path.match(/^\/api\/security\/api-keys\/[^/]+$/) && method === 'DELETE') {
                return await handleRevokeAPIKey(request, env);
            }

            // Webhooks
            if (path === '/api/webhooks' && method === 'GET') {
                return await handleListWebhooks(request, env);
            }
            if (path === '/api/webhooks' && method === 'POST') {
                return await handleCreateWebhook(request, env);
            }
            if (path.match(/^\/api\/webhooks\/[^/]+$/) && method === 'DELETE') {
                return await handleDeleteWebhook(request, env);
            }

            // Maintenance
            if (path === '/api/maintenance' && method === 'GET') {
                return await handleGetMaintenance(request, env);
            }
            if (path === '/api/maintenance' && method === 'POST') {
                return await handleSetMaintenance(request, env);
            }

            return jsonResponse({ error: 'Not found' }, 404);
        } catch (err) {
            console.error('Error:', err);
            return jsonResponse({ error: err.message }, 500);
        }
    }
};

// ========== HELPERS ==========

function corsHeaders() {
    return {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };
}

function jsonResponse(data, status = 200) {
    return new Response(JSON.stringify(data), {
        status,
        headers: {
            'Content-Type': 'application/json',
            ...corsHeaders(),
        },
    });
}

function generateKey() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let result = '';
    const array = new Uint8Array(12);
    crypto.getRandomValues(array);
    for (let i = 0; i < 12; i++) {
        result += chars[array[i] % chars.length];
    }
    return result.match(/.{1,4}/g).join('-');
}

async function createJWT(payload, secret) {
    const header = { alg: 'HS256', typ: 'JWT' };
    const encodedHeader = btoa(JSON.stringify(header));
    const encodedPayload = btoa(JSON.stringify(payload));
    const signature = await signHS256(`${encodedHeader}.${encodedPayload}`, secret);
    return `${encodedHeader}.${encodedPayload}.${signature}`;
}

async function verifyJWT(token, secret) {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    
    const [header, payload, signature] = parts;
    const expectedSignature = await signHS256(`${header}.${payload}`, secret);
    
    if (signature !== expectedSignature) return null;
    
    const decoded = JSON.parse(atob(payload));
    if (decoded.exp && decoded.exp < Date.now() / 1000) return null;
    
    return decoded;
}

async function signHS256(message, secret) {
    const encoder = new TextEncoder();
    const keyData = encoder.encode(secret);
    const messageData = encoder.encode(message);
    
    const key = await crypto.subtle.importKey(
        'raw',
        keyData,
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign']
    );
    
    const signature = await crypto.subtle.sign('HMAC', key, messageData);
    return btoa(String.fromCharCode(...new Uint8Array(signature)))
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/, '');
}

async function hashPassword(password) {
    const encoder = new TextEncoder();
    const data = encoder.encode(password + 'vini_salt_2024');
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    return btoa(String.fromCharCode(...new Uint8Array(hashBuffer)));
}

async function verifyAdminAuth(request, env) {
    const auth = request.headers.get('Authorization');
    if (!auth || !auth.startsWith('Bearer ')) return null;
    
    const token = auth.substring(7);
    const decoded = await verifyJWT(token, env.JWT_SECRET);
    
    if (!decoded || decoded.role !== 'admin') return null;
    
    return decoded;
}

async function verifyLicenseAuth(request, env) {
    const auth = request.headers.get('Authorization');
    if (!auth) return null;
    
    if (auth.startsWith('Bearer ')) {
        const token = auth.substring(7);
        const decoded = await verifyJWT(token, env.JWT_SECRET);
        if (decoded && decoded.role === 'user') return { type: 'jwt', data: decoded };
    }
    
    return null;
}

// ========== APP HANDLERS ==========

async function handleValidateLicense(request, env) {
    const { licenseKey, hwid, deviceModel, iosVersion } = await request.json();

    const { results } = await env.VINI_DB.prepare(
        'SELECT * FROM licenses WHERE key = ?'
    ).bind(licenseKey).all();

    if (results.length === 0) {
        return jsonResponse({ valid: false, error: 'Licencia no encontrada' }, 404);
    }

    const license = results[0];

    if (license.revoked) {
        return jsonResponse({ valid: false, error: 'Licencia revocada' }, 403);
    }

    if (license.paused) {
        return jsonResponse({ 
            valid: false, 
            error: 'Licencia pausada',
            paused: true 
        }, 403);
    }

    const globalPause = await env.VINI_CONFIG.get('global_license_pause');
    if (globalPause === 'true') {
        const pauseReason = await env.VINI_CONFIG.get('global_pause_reason');
        return jsonResponse({ 
            valid: false, 
            error: pauseReason || 'El servicio está temporalmente pausado',
            paused: true,
            globalPause: true
        }, 403);
    }

    if (new Date(license.expires_at) < new Date()) {
        return jsonResponse({ valid: false, error: 'Licencia expirada' }, 403);
    }

    if (!license.hwid) {
        await env.VINI_DB.prepare(
            'UPDATE licenses SET hwid = ?, bound_at = datetime("now"), device_model = ?, ios_version = ? WHERE key = ?'
        ).bind(hwid, deviceModel || '', iosVersion || '', licenseKey).run();
    } else if (license.hwid !== hwid) {
        return jsonResponse({ valid: false, error: 'Licencia vinculada a otro dispositivo' }, 403);
    }

    await env.VINI_DB.prepare(
        'UPDATE licenses SET last_login = datetime("now") WHERE key = ?'
    ).bind(licenseKey).run();

    await env.VINI_DB.prepare(
        `INSERT INTO users (hwid, license_key, device_model, ios_version, active, created_at, last_seen_at) 
         VALUES (?, ?, ?, ?, 1, datetime("now"), datetime("now"))
         ON CONFLICT(hwid) DO UPDATE SET 
            license_key = excluded.license_key,
            device_model = excluded.device_model,
            ios_version = excluded.ios_version,
            active = 1,
            last_seen_at = datetime("now")`
    ).bind(hwid, licenseKey, deviceModel || '', iosVersion || '').run();

    const token = await createJWT({ hwid, role: 'user', license: licenseKey }, env.JWT_SECRET);

    await env.VINI_DB.prepare(
        'INSERT INTO telemetry (hwid, event_type, event_data, created_at) VALUES (?, "session_start", ?, datetime("now"))'
    ).bind(hwid, JSON.stringify({ deviceModel, iosVersion })).run();

    return jsonResponse({
        valid: true,
        token,
        expiresAt: license.expires_at,
    });
}

async function handleGetRemoteConfig(request, env) {
    const auth = await verifyLicenseAuth(request, env);
    if (!auth) return jsonResponse({ error: 'Unauthorized' }, 401);

    const configData = await env.VINI_CONFIG.get('app_config', 'json');
    const config = configData || {
        featureFlags: {},
        messages: [],
        settings: {},
    };

    const hwid = auth.type === 'jwt' ? auth.data.hwid : auth.data.hwid;
    const { results: messages } = await env.VINI_DB.prepare(
        'SELECT * FROM messages WHERE active = 1 AND (target_hwid IS NULL OR target_hwid = ?) ORDER BY created_at DESC LIMIT 10'
    ).bind(hwid).all();

    return jsonResponse({
        ...config,
        messages,
    });
}

// NUEVO: Verificar qué patches necesitan actualización
async function handleCheckUpdates(request, env) {
    const auth = await verifyLicenseAuth(request, env);
    if (!auth) return jsonResponse({ error: 'Unauthorized' }, 401);

    const hwid = auth.data.hwid;
    const { localPatches } = await request.json(); // Array de {id, version} que el usuario tiene localmente

    // Obtener patches asignados al usuario
    const { results: users } = await env.VINI_DB.prepare(
        'SELECT patches FROM users WHERE hwid = ? AND active = 1'
    ).bind(hwid).all();

    if (users.length === 0) {
        return jsonResponse({ updates: [] });
    }

    const patchIds = JSON.parse(users[0].patches || '[]');
    if (patchIds.length === 0) {
        return jsonResponse({ updates: [] });
    }

    const placeholders = patchIds.map(() => '?').join(',');
    const { results: patches } = await env.VINI_DB.prepare(
        `SELECT id, name, version, password FROM patches WHERE id IN (${placeholders})`
    ).bind(...patchIds).all();

    // Comparar versiones locales vs remotas
    const updates = [];
    for (const patch of patches) {
        const local = localPatches.find(lp => lp.id === patch.id);
        
        if (!local) {
            // No tiene el patch localmente → necesita descargarlo
            updates.push({
                id: patch.id,
                name: patch.name,
                version: patch.version,
                password: patch.password,
                action: 'download'
            });
        } else if (local.version !== patch.version) {
            // Versión diferente → necesita actualizar
            updates.push({
                id: patch.id,
                name: patch.name,
                version: patch.version,
                password: patch.password,
                action: 'update'
            });
        }
        // Si versión es igual → no hacer nada (ya está actualizado)
    }

    return jsonResponse({ updates });
}

async function handleAppListPatches(request, env) {
    const auth = await verifyLicenseAuth(request, env);
    if (!auth) return jsonResponse({ error: 'Unauthorized' }, 401);

    const hwid = auth.data.hwid;

    const { results: users } = await env.VINI_DB.prepare(
        'SELECT patches FROM users WHERE hwid = ? AND active = 1'
    ).bind(hwid).all();

    if (users.length === 0) {
        return jsonResponse({ patches: [] });
    }

    const patchIds = JSON.parse(users[0].patches || '[]');
    if (patchIds.length === 0) {
        return jsonResponse({ patches: [] });
    }

    const placeholders = patchIds.map(() => '?').join(',');
    const { results: patches } = await env.VINI_DB.prepare(
        `SELECT id, name, bundle_id, version, description, password, created_at FROM patches WHERE id IN (${placeholders})`
    ).bind(...patchIds).all();

    return jsonResponse({ patches });
}

async function handleAppDownloadPatch(request, env) {
    const auth = await verifyLicenseAuth(request, env);
    if (!auth) return jsonResponse({ error: 'Unauthorized' }, 401);

    const patchId = request.url.split('/').pop();
    const hwid = auth.data.hwid;

    const { results: users } = await env.VINI_DB.prepare(
        'SELECT patches FROM users WHERE hwid = ? AND active = 1'
    ).bind(hwid).all();

    if (users.length === 0) {
        return jsonResponse({ error: 'No access', patchId }, 403);
    }

    const patchIds = JSON.parse(users[0].patches || '[]');
    if (!patchIds.includes(patchId)) {
        return jsonResponse({ error: 'No access to this patch', patchId }, 403);
    }

    const { results } = await env.VINI_DB.prepare(
        'SELECT * FROM patches WHERE id = ?'
    ).bind(patchId).all();

    if (results.length === 0) {
        return jsonResponse({ error: 'Patch not found', patchId }, 404);
    }

    const patch = results[0];

    const r2Key = `patches/${patchId}.3105`;
    const object = await env.VINI_PATCHES.get(r2Key);
    if (!object) {
        await env.VINI_DB.prepare(
            'INSERT INTO telemetry (hwid, event_type, event_data, created_at) VALUES (?, "patch_missing", ?, datetime("now"))'
        ).bind(hwid, JSON.stringify({ patchId, patchName: patch.name, r2Key })).run();

        return jsonResponse({
            error: 'File not found in storage',
            patchId,
            patchName: patch.name,
            r2Key,
            hint: 'El archivo no existe en el bucket R2. Vuelve a subir el patch desde el panel de admin.'
        }, 404);
    }

    await env.VINI_DB.prepare(
        'UPDATE patches SET downloads = downloads + 1 WHERE id = ?'
    ).bind(patchId).run();

    await env.VINI_DB.prepare(
        'INSERT INTO telemetry (hwid, event_type, event_data, created_at) VALUES (?, "patch_download", ?, datetime("now"))'
    ).bind(hwid, JSON.stringify({ patchId, patchName: patch.name })).run();

    return new Response(object.body, {
        headers: {
            'Content-Type': 'application/octet-stream',
            'Content-Disposition': `attachment; filename="${patch.name}.3105"`,
            ...corsHeaders(),
        },
    });
}

async function handleTelemetry(request, env) {
    const auth = await verifyLicenseAuth(request, env);
    if (!auth) return jsonResponse({ error: 'Unauthorized' }, 401);

    const hwid = auth.data.hwid;
    const { eventType, eventData } = await request.json();

    await env.VINI_DB.prepare(
        'INSERT INTO telemetry (hwid, event_type, event_data, created_at) VALUES (?, ?, ?, datetime("now"))'
    ).bind(hwid, eventType, JSON.stringify(eventData || {})).run();

    return jsonResponse({ success: true });
}

async function handleAckMessage(request, env) {
    const auth = await verifyLicenseAuth(request, env);
    if (!auth) return jsonResponse({ error: 'Unauthorized' }, 401);

    const hwid = auth.data.hwid;
    const messageId = request.url.split('/').slice(-2)[0];

    await env.VINI_DB.prepare(
        'INSERT OR IGNORE INTO message_acks (message_id, hwid, acked_at) VALUES (?, ?, datetime("now"))'
    ).bind(messageId, hwid).run();

    return jsonResponse({ success: true });
}

// ========== ADMIN HANDLERS ==========

async function handleAdminLogin(request, env) {
    const { username, password } = await request.json();
    
    if (username !== 'admin') {
        return jsonResponse({ error: 'Invalid credentials' }, 401);
    }

    const storedHash = env.ADMIN_PASSWORD_HASH;
    const providedHash = await hashPassword(password);

    if (providedHash !== storedHash) {
        return jsonResponse({ error: 'Invalid credentials' }, 401);
    }

    const token = await createJWT({ 
        username, 
        role: 'admin',
        exp: Math.floor(Date.now() / 1000) + (24 * 60 * 60)
    }, env.JWT_SECRET);

    return jsonResponse({ token, admin: { username } });
}

async function handleListPatches(request, env) {
    const { results } = await env.VINI_DB.prepare(
        'SELECT * FROM patches ORDER BY created_at DESC'
    ).all();
    return jsonResponse(results);
}

async function handleCreatePatch(request, env) {
    const formData = await request.formData();
    const file = formData.get('file');
    const name = formData.get('name');
    const bundleId = formData.get('bundleId');
    const version = formData.get('version');
    const description = formData.get('description');
    const password = formData.get('password') || '';

    if (!file || !name || !bundleId || !version) {
        return jsonResponse({ error: 'Missing required fields' }, 400);
    }

    const id = crypto.randomUUID();

    await env.VINI_PATCHES.put(`patches/${id}.3105`, file.stream(), {
        httpMetadata: { contentType: 'application/octet-stream' },
    });

    await env.VINI_DB.prepare(
        'INSERT INTO patches (id, name, bundle_id, version, description, password, created_at, downloads) VALUES (?, ?, ?, ?, ?, ?, datetime("now"), 0)'
    ).bind(id, name, bundleId, version, description || '', password).run();

    return jsonResponse({ id, name, version }, 201);
}

async function handleDeletePatch(request, env) {
    const patchId = request.url.split('/').pop();

    await env.VINI_PATCHES.delete(`patches/${patchId}.3105`);
    await env.VINI_DB.prepare('DELETE FROM patches WHERE id = ?').bind(patchId).run();

    const { results: users } = await env.VINI_DB.prepare('SELECT hwid, patches FROM users').all();
    for (const user of users) {
        const patchIds = JSON.parse(user.patches || '[]');
        if (patchIds.includes(patchId)) {
            const updated = patchIds.filter(id => id !== patchId);
            await env.VINI_DB.prepare(
                'UPDATE users SET patches = ? WHERE hwid = ?'
            ).bind(JSON.stringify(updated), user.hwid).run();
        }
    }

    return jsonResponse({ success: true });
}

async function handlePushToGitHub(request, env) {
    const patchId = request.url.split('/').slice(-2)[0];
    const githubToken = env.GITHUB_TOKEN;
    const repo = 'loboangel39-svg/VINI-IPA';

    const { results } = await env.VINI_DB.prepare(
        'SELECT * FROM patches WHERE id = ?'
    ).bind(patchId).all();

    if (results.length === 0) {
        return jsonResponse({ error: 'Patch not found' }, 404);
    }

    const patch = results[0];
    const r2Key = `patches/${patchId}.3105`;
    const object = await env.VINI_PATCHES.get(r2Key);

    if (!object) {
        return jsonResponse({ error: 'File not found' }, 404);
    }

    const fileData = await object.arrayBuffer();
    const base64 = btoa(String.fromCharCode(...new Uint8Array(fileData)));

    const path = `patches/${patch.name}.3105`;
    const content = base64;

    const response = await fetch(`https://api.github.com/repos/${repo}/contents/${path}`, {
        method: 'PUT',
        headers: {
            'Authorization': `token ${githubToken}`,
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            message: `Add patch: ${patch.name} v${patch.version}`,
            content,
        }),
    });

    if (!response.ok) {
        const error = await response.text();
        return jsonResponse({ error: 'GitHub upload failed', details: error }, 500);
    }

    return jsonResponse({ success: true });
}

async function handleListUsers(request, env) {
    const { results } = await env.VINI_DB.prepare(
        'SELECT * FROM users ORDER BY created_at DESC'
    ).all();
    return jsonResponse(results);
}

async function handleUpdateUser(request, env) {
    const hwid = request.url.split('/').pop();
    const { active } = await request.json();

    await env.VINI_DB.prepare(
        'UPDATE users SET active = ? WHERE hwid = ?'
    ).bind(active ? 1 : 0, hwid).run();

    return jsonResponse({ success: true });
}

async function handleAssignPatches(request, env) {
    const hwid = request.url.split('/').slice(-2)[0];
    const { patchIds } = await request.json();

    await env.VINI_DB.prepare(
        'UPDATE users SET patches = ? WHERE hwid = ?'
    ).bind(JSON.stringify(patchIds), hwid).run();

    return jsonResponse({ success: true });
}

async function handleListLicenses(request, env) {
    const { results } = await env.VINI_DB.prepare(
        'SELECT * FROM licenses ORDER BY created_at DESC'
    ).all();
    return jsonResponse(results);
}

async function handleGenerateLicense(request, env) {
    const { validDays, customKey } = await request.json();
    const key = customKey || generateKey();
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + (validDays || 30));

    await env.VINI_DB.prepare(
        'INSERT INTO licenses (key, expires_at, created_at, revoked) VALUES (?, ?, datetime("now"), 0)'
    ).bind(key, expiresAt.toISOString()).run();

    return jsonResponse({ key, expiresAt: expiresAt.toISOString() }, 201);
}

async function handleRevokeLicense(request, env) {
    const key = request.url.split('/').pop();

    await env.VINI_DB.prepare(
        'UPDATE licenses SET revoked = 1 WHERE key = ?'
    ).bind(key).run();

    return jsonResponse({ success: true });
}

async function handleUnbindLicense(request, env) {
    const key = request.url.split('/').slice(-2)[0];

    await env.VINI_DB.prepare(
        'UPDATE licenses SET hwid = NULL, bound_at = NULL WHERE key = ?'
    ).bind(key).run();

    return jsonResponse({ success: true });
}

async function handleUnbindAllLicenses(request, env) {
    await env.VINI_DB.prepare(
        'UPDATE licenses SET hwid = NULL, bound_at = NULL WHERE hwid IS NOT NULL'
    ).run();

    return jsonResponse({ success: true });
}

async function handleDeleteLicense(request, env) {
    const key = request.url.split('/').slice(-2)[0];

    await env.VINI_DB.prepare(
        'DELETE FROM licenses WHERE key = ?'
    ).bind(key).run();

    return jsonResponse({ success: true });
}

async function handleGetConfig(request, env) {
    const configData = await env.VINI_CONFIG.get('app_config', 'json');
    return jsonResponse(configData || {
        featureFlags: {},
        messages: [],
        settings: {},
    });
}

async function handleUpdateConfig(request, env) {
    const config = await request.json();
    await env.VINI_CONFIG.put('app_config', JSON.stringify(config));
    return jsonResponse({ success: true });
}

async function handleListMessages(request, env) {
    const { results } = await env.VINI_DB.prepare(
        'SELECT * FROM messages WHERE active = 1 ORDER BY created_at DESC LIMIT 50'
    ).all();
    return jsonResponse(results);
}

async function handleCreateMessage(request, env) {
    const { title, content, type, targetHwid } = await request.json();

    if (!title || !content) {
        return jsonResponse({ error: 'Title and content required' }, 400);
    }

    const id = crypto.randomUUID();

    await env.VINI_DB.prepare(
        'INSERT INTO messages (id, title, content, type, target_hwid, expires_at, active, created_at) VALUES (?, ?, ?, ?, ?, ?, 1, datetime("now"))'
    ).bind(id, title, content, type || 'info', targetHwid || null, null).run();

    return jsonResponse({ id }, 201);
}

async function handleDeleteMessage(request, env) {
    const messageId = request.url.split('/').pop();

    await env.VINI_DB.prepare(
        'UPDATE messages SET active = 0 WHERE id = ?'
    ).bind(messageId).run();

    return jsonResponse({ success: true });
}

async function handleGetStats(request, env) {
    const { results: totalUsers } = await env.VINI_DB.prepare(
        'SELECT COUNT(*) as count FROM users WHERE active = 1'
    ).all();

    const { results: totalLicenses } = await env.VINI_DB.prepare(
        'SELECT COUNT(*) as count FROM licenses WHERE revoked = 0 AND expires_at > datetime("now")'
    ).all();

    const { results: totalPatches } = await env.VINI_DB.prepare(
        'SELECT COUNT(*) as count FROM patches'
    ).all();

    const { results: totalDownloads } = await env.VINI_DB.prepare(
        'SELECT SUM(downloads) as total FROM patches'
    ).all();

    return jsonResponse({
        totalUsers: totalUsers[0].count,
        totalLicenses: totalLicenses[0].count,
        totalPatches: totalPatches[0].count,
        totalDownloads: totalDownloads[0].total || 0,
    });
}

async function handleGetRealtimeStats(request, env) {
    const { results: hourlyActivity } = await env.VINI_DB.prepare(
        `SELECT 
            strftime('%Y-%m-%d %H:00:00', created_at) as hour,
            COUNT(*) as events
        FROM telemetry 
        WHERE created_at > datetime("now", "-24 hours")
        GROUP BY hour
        ORDER BY hour`
    ).all();

    const { results: deviceBreakdown } = await env.VINI_DB.prepare(
        `SELECT 
            device_model,
            ios_version,
            COUNT(*) as count
        FROM users 
        WHERE active = 1
        GROUP BY device_model, ios_version
        ORDER BY count DESC
        LIMIT 10`
    ).all();

    const { results: patchPopularity } = await env.VINI_DB.prepare(
        `SELECT 
            p.name,
            p.downloads
        FROM patches p
        ORDER BY p.downloads DESC
        LIMIT 10`
    ).all();

    return jsonResponse({
        hourlyActivity,
        deviceBreakdown,
        patchPopularity,
        timestamp: new Date().toISOString(),
    });
}

async function handleListBanners(request, env) {
    const config = await env.VINI_CONFIG.get('banners', 'json');
    return jsonResponse(config || []);
}

async function handleCreateBanner(request, env) {
    const banner = await request.json();
    const id = crypto.randomUUID();

    const banners = await env.VINI_CONFIG.get('banners', 'json') || [];
    banners.unshift({ id, ...banner, created_at: new Date().toISOString() });

    await env.VINI_CONFIG.put('banners', JSON.stringify(banners));
    return jsonResponse({ id }, 201);
}

async function handleDeleteBanner(request, env) {
    const bannerId = request.url.split('/').pop();
    const banners = await env.VINI_CONFIG.get('banners', 'json') || [];
    const filtered = banners.filter(b => b.id !== bannerId);
    await env.VINI_CONFIG.put('banners', JSON.stringify(filtered));
    return jsonResponse({ success: true });
}

async function handleListVersions(request, env) {
    const { results } = await env.VINI_DB.prepare(
        'SELECT * FROM versions ORDER BY created_at DESC'
    ).all();
    return jsonResponse(results);
}

async function handleCreateVersion(request, env) {
    const version = await request.json();
    const id = crypto.randomUUID();

    await env.VINI_DB.prepare(
        'INSERT INTO versions (id, version, min_ios, max_ios, changelog, download_url, force_update, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, datetime("now"))'
    ).bind(id, version.version, version.min_ios, version.max_ios, version.changelog || '', version.download_url || '', version.force_update ? 1 : 0).run();

    return jsonResponse({ id }, 201);
}

async function handleDeleteVersion(request, env) {
    const versionId = request.url.split('/').pop();
    await env.VINI_DB.prepare('DELETE FROM versions WHERE id = ?').bind(versionId).run();
    return jsonResponse({ success: true });
}

async function handleGetLogs(request, env) {
    const { results } = await env.VINI_DB.prepare(
        'SELECT * FROM logs ORDER BY created_at DESC LIMIT 100'
    ).all();
    return jsonResponse(results);
}

async function handleClearLogs(request, env) {
    await env.VINI_DB.prepare('DELETE FROM logs').run();
    return jsonResponse({ success: true });
}

async function handleGetSecurity(request, env) {
    const securityData = await env.VINI_CONFIG.get('security', 'json');
    return jsonResponse(securityData || {
        blockedIPs: [],
        apiKeys: [],
        rateLimit: { requests: 60, banTime: 300 }
    });
}

async function handleBlockIP(request, env) {
    const { ip } = await request.json();
    const securityData = await env.VINI_CONFIG.get('security', 'json') || { blockedIPs: [], apiKeys: [], rateLimit: { requests: 60, banTime: 300 } };
    
    if (!securityData.blockedIPs.includes(ip)) {
        securityData.blockedIPs.push(ip);
        await env.VINI_CONFIG.put('security', JSON.stringify(securityData));
    }

    return jsonResponse({ success: true });
}

async function handleUnblockIP(request, env) {
    const { ip } = await request.json();
    const securityData = await env.VINI_CONFIG.get('security', 'json') || { blockedIPs: [], apiKeys: [], rateLimit: { requests: 60, banTime: 300 } };
    
    securityData.blockedIPs = securityData.blockedIPs.filter(i => i !== ip);
    await env.VINI_CONFIG.put('security', JSON.stringify(securityData));

    return jsonResponse({ success: true });
}

async function handleSaveRateLimit(request, env) {
    const { rateLimit } = await request.json();
    const securityData = await env.VINI_CONFIG.get('security', 'json') || { blockedIPs: [], apiKeys: [], rateLimit: { requests: 60, banTime: 300 } };
    
    securityData.rateLimit = rateLimit;
    await env.VINI_CONFIG.put('security', JSON.stringify(securityData));

    return jsonResponse({ success: true });
}

async function handleGenerateAPIKey(request, env) {
    const securityData = await env.VINI_CONFIG.get('security', 'json') || { blockedIPs: [], apiKeys: [], rateLimit: { requests: 60, banTime: 300 } };
    
    const id = crypto.randomUUID();
    const key = generateKey() + '-' + generateKey();
    
    securityData.apiKeys.push({ id, key, created_at: new Date().toISOString() });
    await env.VINI_CONFIG.put('security', JSON.stringify(securityData));

    return jsonResponse({ id, key });
}

async function handleRevokeAPIKey(request, env) {
    const keyId = request.url.split('/').pop();
    const securityData = await env.VINI_CONFIG.get('security', 'json') || { blockedIPs: [], apiKeys: [], rateLimit: { requests: 60, banTime: 300 } };
    
    securityData.apiKeys = securityData.apiKeys.filter(k => k.id !== keyId);
    await env.VINI_CONFIG.put('security', JSON.stringify(securityData));

    return jsonResponse({ success: true });
}

async function handleListWebhooks(request, env) {
    const config = await env.VINI_CONFIG.get('webhooks', 'json');
    return jsonResponse(config || []);
}

async function handleCreateWebhook(request, env) {
    const webhook = await request.json();
    const id = crypto.randomUUID();

    const webhooks = await env.VINI_CONFIG.get('webhooks', 'json') || [];
    webhooks.push({ id, ...webhook, created_at: new Date().toISOString() });

    await env.VINI_CONFIG.put('webhooks', JSON.stringify(webhooks));
    return jsonResponse({ id }, 201);
}

async function handleDeleteWebhook(request, env) {
    const webhookId = request.url.split('/').pop();
    const webhooks = await env.VINI_CONFIG.get('webhooks', 'json') || [];
    const filtered = webhooks.filter(w => w.id !== webhookId);
    await env.VINI_CONFIG.put('webhooks', JSON.stringify(filtered));
    return jsonResponse({ success: true });
}

async function handleGetMaintenance(request, env) {
    try {
        if (!env.VINI_CONFIG) {
            return jsonResponse({ error: 'VINI_CONFIG binding not available' }, 500);
        }
        const config = await env.VINI_CONFIG.get('maintenance', 'json');
        return jsonResponse(config || { enabled: false, message: '', whitelist: [] });
    } catch (err) {
        return jsonResponse({ error: 'Failed to read maintenance config: ' + err.message }, 500);
    }
}

async function handleSetMaintenance(request, env) {
    try {
        if (!env.VINI_CONFIG) {
            return jsonResponse({ error: 'VINI_CONFIG binding not available' }, 500);
        }
        const config = await request.json();
        await env.VINI_CONFIG.put('maintenance', JSON.stringify(config));
        return jsonResponse({ success: true });
    } catch (err) {
        return jsonResponse({ error: 'Failed to save maintenance config: ' + err.message }, 500);
    }
}
