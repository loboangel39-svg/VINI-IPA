/**
 * VINI Patch Manager - Cloudflare Worker API v3
 * 
 * Changelog v3:
 * - Patch Journal: registro de apply/restore para "Restore Original" sin errores
 * - Descarga optimizada: Cache-Control, ETag, Range requests (resume)
 * - Reintentos automáticos en el cliente
 * 
 * Bindings required (wrangler.toml):
 * - D1 Database: VINI_DB
 * - R2 Bucket: VINI_PATCHES
 * - KV Namespace: VINI_CONFIG
 * - Secret: ADMIN_PASSWORD_HASH
 * - Secret: JWT_SECRET
 * - Secret: GITHUB_TOKEN
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

            if (path === '/api/app/validate-license' && method === 'POST') {
                return await handleValidateLicense(request, env);
            }
            if (path === '/api/app/config' && method === 'GET') {
                return await handleGetRemoteConfig(request, env);
            }
            if (path === '/api/app/check-updates' && method === 'GET') {
                return await handleCheckUpdates(request, env);
            }
            if (path === '/api/app/patches' && method === 'GET') {
                return await handleAppListPatches(request, env);
            }
            if (path.startsWith('/api/app/patches/') && method === 'GET') {
                return await handleAppDownloadPatch(request, env);
            }
            if (path === '/api/app/telemetry' && method === 'POST') {
                return await handleTelemetry(request, env);
            }
            if (path.startsWith('/api/app/messages/') && path.endsWith('/ack') && method === 'POST') {
                return await handleAckMessage(request, env);
            }

            // ========== JOURNAL ROUTES (App) ==========
            if (path === '/api/app/journal' && method === 'GET') {
                return await handleJournalList(request, env);
            }
            if (path === '/api/app/journal/apply' && method === 'POST') {
                return await handleJournalApply(request, env);
            }
            if (path === '/api/app/journal/restore' && method === 'POST') {
                return await handleJournalRestore(request, env);
            }

            // ========== ADMIN ROUTES ==========

            if (path === '/api/admin/login' && method === 'POST') {
                return await handleAdminLogin(request, env);
            }

            const admin = await verifyAdminAuth(request, env);
            if (!admin) {
                return jsonResponse({ error: 'Unauthorized' }, 401);
            }

            // Patches CRUD
            if (path === '/api/patches' && method === 'GET') return await handleListPatches(request, env);
            if (path === '/api/patches' && method === 'POST') return await handleCreatePatch(request, env);
            if (path.match(/^\/api\/patches\/[^/]+$/) && method === 'DELETE') return await handleDeletePatch(request, env);
            if (path.match(/^\/api\/patches\/[^/]+\/push-github$/) && method === 'POST') return await handlePushToGitHub(request, env);

            // Users
            if (path === '/api/users' && method === 'GET') return await handleListUsers(request, env);
            if (path.match(/^\/api\/users\/[^/]+$/) && method === 'PUT') return await handleUpdateUser(request, env);
            if (path.match(/^\/api\/users\/[^/]+\/patches$/) && method === 'PUT') return await handleAssignPatches(request, env);

            // Licenses
            if (path === '/api/licenses' && method === 'GET') return await handleListLicenses(request, env);
            if (path === '/api/licenses' && method === 'POST') return await handleGenerateLicense(request, env);
            if (path === '/api/licenses/unbind-all' && method === 'POST') return await handleUnbindAllLicenses(request, env);
            if (path.match(/^\/api\/licenses\/[^/]+\/unbind$/) && method === 'POST') return await handleUnbindLicense(request, env);
            if (path.match(/^\/api\/licenses\/[^/]+\/delete$/) && method === 'DELETE') return await handleDeleteLicense(request, env);
            if (path.match(/^\/api\/licenses\/[^/]+$/) && method === 'DELETE') return await handleRevokeLicense(request, env);

            // Remote Config
            if (path === '/api/config' && method === 'GET') return await handleGetConfig(request, env);
            if (path === '/api/config' && method === 'PUT') return await handleUpdateConfig(request, env);

            // Messages
            if (path === '/api/messages' && method === 'GET') return await handleListMessages(request, env);
            if (path === '/api/messages' && method === 'POST') return await handleCreateMessage(request, env);
            if (path.match(/^\/api\/messages\/[^/]+$/) && method === 'DELETE') return await handleDeleteMessage(request, env);

            // Statistics
            if (path === '/api/stats' && method === 'GET') return await handleGetStats(request, env);
            if (path === '/api/stats/realtime' && method === 'GET') return await handleGetRealtimeStats(request, env);

            // Banners
            if (path === '/api/banners' && method === 'GET') return await handleListBanners(request, env);
            if (path === '/api/banners' && method === 'POST') return await handleCreateBanner(request, env);
            if (path.match(/^\/api\/banners\/[^/]+$/) && method === 'DELETE') return await handleDeleteBanner(request, env);

            // Versions
            if (path === '/api/versions' && method === 'GET') return await handleListVersions(request, env);
            if (path === '/api/versions' && method === 'POST') return await handleCreateVersion(request, env);
            if (path.match(/^\/api\/versions\/[^/]+$/) && method === 'DELETE') return await handleDeleteVersion(request, env);

            // Logs
            if (path === '/api/logs' && method === 'GET') return await handleGetLogs(request, env);
            if (path === '/api/logs' && method === 'DELETE') return await handleClearLogs(request, env);

            // Security
            if (path === '/api/security' && method === 'GET') return await handleGetSecurity(request, env);
            if (path === '/api/security/block-ip' && method === 'POST') return await handleBlockIP(request, env);
            if (path === '/api/security/unblock-ip' && method === 'POST') return await handleUnblockIP(request, env);
            if (path === '/api/security/rate-limit' && method === 'POST') return await handleSetRateLimit(request, env);
            if (path === '/api/security/api-keys' && method === 'GET') return await handleListAPIKeys(request, env);
            if (path === '/api/security/api-keys' && method === 'POST') return await handleGenerateAPIKey(request, env);
            if (path.match(/^\/api\/security\/api-keys\/[^/]+$/) && method === 'DELETE') return await handleRevokeAPIKey(request, env);

            // Webhooks
            if (path === '/api/webhooks' && method === 'GET') return await handleListWebhooks(request, env);
            if (path === '/api/webhooks' && method === 'POST') return await handleCreateWebhook(request, env);
            if (path.match(/^\/api\/webhooks\/[^/]+$/) && method === 'DELETE') return await handleDeleteWebhook(request, env);

            // Maintenance
            if (path === '/api/maintenance' && method === 'GET') return await handleGetMaintenance(request, env);
            if (path === '/api/maintenance' && method === 'POST') return await handleSetMaintenance(request, env);

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
        'Access-Control-Allow-Headers': 'Content-Type, Authorization, Range',
        'Access-Control-Max-Age': '86400',
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

async function hashPassword(password) {
    const encoder = new TextEncoder();
    const data = encoder.encode(password);
    const hash = await crypto.subtle.digest('SHA-256', data);
    return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('');
}

async function createJWT(payload, secret) {
    const header = { alg: 'HS256', typ: 'JWT' };
    const encodedHeader = btoa(JSON.stringify(header));
    const encodedPayload = btoa(JSON.stringify({ ...payload, iat: Math.floor(Date.now() / 1000) }));
    const signingInput = `${encodedHeader}.${encodedPayload}`;
    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(signingInput));
    const encodedSignature = btoa(String.fromCharCode(...new Uint8Array(signature)));
    return `${encodedHeader}.${encodedPayload}.${encodedSignature}`;
}

async function verifyJWT(token, secret) {
    try {
        const [encodedHeader, encodedPayload, encodedSignature] = token.split('.');
        const signingInput = `${encodedHeader}.${encodedPayload}`;
        const encoder = new TextEncoder();
        const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
        const signature = Uint8Array.from(atob(encodedSignature), c => c.charCodeAt(0));
        const valid = await crypto.subtle.verify('HMAC', key, signature, encoder.encode(signingInput));
        if (!valid) return null;
        return JSON.parse(atob(encodedPayload));
    } catch { return null; }
}

function generateKey(length = 24) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let result = '';
    const array = new Uint8Array(length);
    crypto.getRandomValues(array);
    for (let i = 0; i < length; i++) result += chars[array[i] % chars.length];
    return result.match(/.{1,4}/g).join('-');
}

async function verifyAdminAuth(request, env) {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return null;
    const token = authHeader.slice(7);
    const payload = await verifyJWT(token, env.JWT_SECRET);
    if (!payload || payload.role !== 'admin') return null;
    return payload;
}

async function verifyLicenseAuth(request, env) {
    const authHeader = request.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return null;
    const token = authHeader.slice(7);
    const { results } = await env.VINI_DB.prepare(
        'SELECT * FROM licenses WHERE key = ? AND revoked = 0 AND expires_at > datetime("now")'
    ).bind(token).all();
    if (results.length > 0) return { type: 'license', data: results[0] };
    const payload = await verifyJWT(token, env.JWT_SECRET);
    if (payload?.role === 'user') return { type: 'jwt', data: payload };
    return null;
}

// ========== APP ROUTES ==========

async function handleValidateLicense(request, env) {
    const { licenseKey, hwid, deviceModel, iosVersion } = await request.json();
    const { results } = await env.VINI_DB.prepare('SELECT * FROM licenses WHERE key = ?').bind(licenseKey).all();
    if (results.length === 0) return jsonResponse({ valid: false, error: 'Licencia no encontrada' }, 404);
    const license = results[0];
    if (license.revoked) return jsonResponse({ valid: false, error: 'Licencia revocada' }, 403);
    if (new Date(license.expires_at) < new Date()) return jsonResponse({ valid: false, error: 'Licencia expirada' }, 403);
    if (!license.hwid) {
        await env.VINI_DB.prepare(
            'UPDATE licenses SET hwid = ?, bound_at = datetime("now"), device_model = ?, ios_version = ? WHERE key = ?'
        ).bind(hwid, deviceModel || '', iosVersion || '', licenseKey).run();
    } else if (license.hwid !== hwid) {
        return jsonResponse({ valid: false, error: 'Licencia vinculada a otro dispositivo' }, 403);
    }
    await env.VINI_DB.prepare('UPDATE licenses SET last_login = datetime("now") WHERE key = ?').bind(licenseKey).run();
    await env.VINI_DB.prepare(
        `INSERT INTO users (hwid, license_key, device_model, ios_version, active, created_at, last_seen_at) 
         VALUES (?, ?, ?, ?, 1, datetime("now"), datetime("now"))
         ON CONFLICT(hwid) DO UPDATE SET 
            license_key = excluded.license_key, device_model = excluded.device_model,
            ios_version = excluded.ios_version, active = 1, last_seen_at = datetime("now")`
    ).bind(hwid, licenseKey, deviceModel || '', iosVersion || '').run();
    const token = await createJWT({ hwid, role: 'user', license: licenseKey }, env.JWT_SECRET);
    await env.VINI_DB.prepare(
        'INSERT INTO telemetry (hwid, event_type, event_data, created_at) VALUES (?, "session_start", ?, datetime("now"))'
    ).bind(hwid, JSON.stringify({ deviceModel, iosVersion })).run();
    return jsonResponse({ valid: true, token, expiresAt: license.expires_at });
}

async function handleGetRemoteConfig(request, env) {
    const auth = await verifyLicenseAuth(request, env);
    if (!auth) return jsonResponse({ error: 'Unauthorized' }, 401);
    const configData = await env.VINI_CONFIG.get('app_config', 'json');
    const config = configData || { featureFlags: {}, messages: [], settings: {} };
    const hwid = auth.type === 'jwt' ? auth.data.hwid : auth.data.hwid;
    const { results: messages } = await env.VINI_DB.prepare(
        'SELECT * FROM messages WHERE active = 1 AND (target_hwid IS NULL OR target_hwid = ?) ORDER BY created_at DESC LIMIT 10'
    ).bind(hwid).all();
    const { results: acks } = await env.VINI_DB.prepare('SELECT message_id FROM message_acks WHERE hwid = ?').bind(hwid).all();
    const ackedIds = new Set(acks.map(a => a.message_id));
    const activeMessages = messages.filter(m => !ackedIds.has(m.id));
    return jsonResponse({ featureFlags: config.featureFlags || {}, settings: config.settings || {}, messages: activeMessages, timestamp: new Date().toISOString() });
}

async function handleCheckUpdates(request, env) {
    const { currentVersion } = Object.fromEntries(new URL(request.url).searchParams);
    const githubToken = env.GITHUB_TOKEN;
    const repo = 'loboangel39-svg/VINI-IPA';
    try {
        const res = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, {
            headers: { 'Authorization': `token ${githubToken}`, 'User-Agent': 'VINI-Worker' },
        });
        if (!res.ok) return jsonResponse({ updateAvailable: false });
        const release = await res.json();
        const latestVersion = release.tag_name.replace('v', '');
        if (currentVersion && latestVersion !== currentVersion) {
            return jsonResponse({ updateAvailable: true, latestVersion, releaseNotes: release.body, downloadUrl: release.assets?.[0]?.browser_download_url || release.html_url });
        }
    } catch (err) { /* silently fail */ }
    return jsonResponse({ updateAvailable: false });
}

async function handleAppListPatches(request, env) {
    const auth = await verifyLicenseAuth(request, env);
    if (!auth) return jsonResponse({ error: 'Unauthorized' }, 401);
    const hwid = auth.type === 'jwt' ? auth.data.hwid : auth.data.hwid;
    const { results: users } = await env.VINI_DB.prepare('SELECT patches FROM users WHERE hwid = ? AND active = 1').bind(hwid).all();
    if (users.length === 0) return jsonResponse({ patches: [] });
    const patchIds = JSON.parse(users[0].patches || '[]');
    if (patchIds.length === 0) return jsonResponse({ patches: [] });
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
    const hwid = auth.type === 'jwt' ? auth.data.hwid : auth.data.hwid;

    // Verificar acceso
    const { results: users } = await env.VINI_DB.prepare('SELECT patches FROM users WHERE hwid = ? AND active = 1').bind(hwid).all();
    if (users.length === 0) return jsonResponse({ error: 'No access', patchId }, 403);
    const patchIds = JSON.parse(users[0].patches || '[]');
    if (!patchIds.includes(patchId)) return jsonResponse({ error: 'No access to this patch', patchId }, 403);

    const { results } = await env.VINI_DB.prepare('SELECT * FROM patches WHERE id = ?').bind(patchId).all();
    if (results.length === 0) return jsonResponse({ error: 'Patch not found', patchId }, 404);
    const patch = results[0];

    const r2Key = `patches/${patchId}.3105`;
    const object = await env.VINI_PATCHES.get(r2Key);
    if (!object) {
        await env.VINI_DB.prepare(
            'INSERT INTO telemetry (hwid, event_type, event_data, created_at) VALUES (?, "patch_missing", ?, datetime("now"))'
        ).bind(hwid, JSON.stringify({ patchId, patchName: patch.name, r2Key })).run();
        return jsonResponse({ error: 'File not found in storage', patchId, patchName: patch.name, r2Key, hint: 'El archivo no existe en R2. Vuelve a subir el patch desde el panel de admin.' }, 404);
    }

    // Incrementar descargas
    await env.VINI_DB.prepare('UPDATE patches SET downloads = downloads + 1 WHERE id = ?').bind(patchId).run();
    await env.VINI_DB.prepare(
        'INSERT INTO telemetry (hwid, event_type, event_data, created_at) VALUES (?, "patch_download", ?, datetime("now"))'
    ).bind(hwid, JSON.stringify({ patchId, patchName: patch.name })).run();

    // === OPTIMIZACIONES DE DESCARGA ===
    const fileSize = object.size;
    const baseHeaders = {
        'Content-Type': 'application/octet-stream',
        'Content-Disposition': `attachment; filename="${patch.name}.3105"`,
        'Cache-Control': 'public, max-age=3600',
        'ETag': `"${patchId}-${patch.version}"`,
        'Accept-Ranges': 'bytes',
        'X-Patch-Id': patchId,
        'X-Patch-Version': patch.version,
        ...corsHeaders(),
    };

    // Soporte Range requests (resume de descargas interrumpidas)
    const rangeHeader = request.headers.get('Range');
    if (rangeHeader) {
        const rangeMatch = rangeHeader.match(/bytes=(\d+)-(\d*)/);
        if (rangeMatch) {
            const start = parseInt(rangeMatch[1]);
            const end = rangeMatch[2] ? parseInt(rangeMatch[2]) : fileSize - 1;
            if (start >= fileSize) {
                return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${fileSize}` } });
            }
            const slice = object.body.slice(start, end + 1);
            return new Response(slice, {
                status: 206,
                headers: {
                    ...baseHeaders,
                    'Content-Range': `bytes ${start}-${end}/${fileSize}`,
                    'Content-Length': String(end - start + 1),
                },
            });
        }
    }

    return new Response(object.body, {
        headers: { ...baseHeaders, 'Content-Length': String(fileSize) },
    });
}

async function handleTelemetry(request, env) {
    const auth = await verifyLicenseAuth(request, env);
    if (!auth) return jsonResponse({ error: 'Unauthorized' }, 401);
    const { eventType, eventData } = await request.json();
    const hwid = auth.type === 'jwt' ? auth.data.hwid : auth.data.hwid;
    await env.VINI_DB.prepare(
        'INSERT INTO telemetry (hwid, event_type, event_data, created_at) VALUES (?, ?, ?, datetime("now"))'
    ).bind(hwid, eventType, JSON.stringify(eventData || {})).run();
    await env.VINI_DB.prepare('UPDATE users SET last_seen_at = datetime("now") WHERE hwid = ?').bind(hwid).run();
    return jsonResponse({ success: true });
}

async function handleAckMessage(request, env) {
    const auth = await verifyLicenseAuth(request, env);
    if (!auth) return jsonResponse({ error: 'Unauthorized' }, 401);
    const messageId = request.url.split('/').slice(-2)[0];
    const hwid = auth.type === 'jwt' ? auth.data.hwid : auth.data.hwid;
    await env.VINI_DB.prepare(
        'INSERT OR IGNORE INTO message_acks (message_id, hwid, acked_at) VALUES (?, ?, datetime("now"))'
    ).bind(messageId, hwid).run();
    return jsonResponse({ success: true });
}

// ========== JOURNAL ROUTES ==========

async function handleJournalApply(request, env) {
    const auth = await verifyLicenseAuth(request, env);
    if (!auth) return jsonResponse({ error: 'Unauthorized' }, 401);
    const hwid = auth.type === 'jwt' ? auth.data.hwid : auth.data.hwid;
    const { patchId, targetFile, originalHash, patchedHash, backupR2Key, metadata } = await request.json();
    if (!patchId) return jsonResponse({ error: 'patchId is required' }, 400);

    await env.VINI_DB.prepare(
        `INSERT INTO patch_journal (hwid, patch_id, action, target_file, original_hash, patched_hash, backup_r2_key, metadata, created_at)
         VALUES (?, ?, 'applied', ?, ?, ?, ?, ?, datetime('now'))`
    ).bind(hwid, patchId, targetFile || '', originalHash || '', patchedHash || '', backupR2Key || '', JSON.stringify(metadata || {})).run();

    return jsonResponse({ success: true, message: 'Patch application logged in journal' });
}

async function handleJournalRestore(request, env) {
    const auth = await verifyLicenseAuth(request, env);
    if (!auth) return jsonResponse({ error: 'Unauthorized' }, 401);
    const hwid = auth.type === 'jwt' ? auth.data.hwid : auth.data.hwid;
    const { patchId } = await request.json();
    if (!patchId) return jsonResponse({ error: 'patchId is required' }, 400);

    // Buscar la última aplicación de este patch
    const { results } = await env.VINI_DB.prepare(
        `SELECT * FROM patch_journal 
         WHERE hwid = ? AND patch_id = ? AND action = 'applied' 
         ORDER BY created_at DESC LIMIT 1`
    ).bind(hwid, patchId).all();

    if (results.length === 0) {
        return jsonResponse({ error: 'No journal entry found. This patch was never applied or already restored.', patchId }, 404);
    }

    const journal = results[0];

    // Registrar la restauración en el journal
    await env.VINI_DB.prepare(
        `INSERT INTO patch_journal (hwid, patch_id, action, target_file, original_hash, patched_hash, backup_r2_key, metadata, created_at)
         VALUES (?, ?, 'restored', ?, ?, ?, ?, ?, datetime('now'))`
    ).bind(hwid, patchId, journal.target_file, journal.original_hash, journal.patched_hash, journal.backup_r2_key, journal.metadata).run();

    return jsonResponse({
        success: true,
        message: 'Restore logged successfully',
        journal: {
            id: journal.id,
            patchId: journal.patch_id,
            targetFile: journal.target_file,
            originalHash: journal.original_hash,
            patchedHash: journal.patched_hash,
            backupR2Key: journal.backup_r2_key,
            metadata: journal.metadata,
            appliedAt: journal.created_at,
        }
    });
}

async function handleJournalList(request, env) {
    const auth = await verifyLicenseAuth(request, env);
    if (!auth) return jsonResponse({ error: 'Unauthorized' }, 401);
    const hwid = auth.type === 'jwt' ? auth.data.hwid : auth.data.hwid;

    // Obtener el último estado de cada patch (solo la entrada más reciente por patch_id)
    const { results } = await env.VINI_DB.prepare(
        `SELECT pj.* FROM patch_journal pj
         INNER JOIN (
             SELECT patch_id, MAX(created_at) as max_date
             FROM patch_journal WHERE hwid = ?
             GROUP BY patch_id
         ) latest ON pj.patch_id = latest.patch_id AND pj.created_at = latest.max_date
         WHERE pj.hwid = ?
         ORDER BY pj.created_at DESC`
    ).bind(hwid, hwid).all();

    // Separar por estado
    const applied = results.filter(r => r.action === 'applied');
    const restored = results.filter(r => r.action === 'restored');

    return jsonResponse({
        journal: results,
        applied: applied.map(r => ({ patchId: r.patch_id, targetFile: r.target_file, appliedAt: r.created_at })),
        restored: restored.map(r => ({ patchId: r.patch_id, targetFile: r.target_file, restoredAt: r.created_at })),
    });
}

// ========== ADMIN ROUTES ==========

async function handleAdminLogin(request, env) {
    const { username, password } = await request.json();
    if (username !== 'admin') return jsonResponse({ error: 'Invalid credentials' }, 401);
    const passwordHash = await hashPassword(password);
    if (passwordHash !== env.ADMIN_PASSWORD_HASH) return jsonResponse({ error: 'Invalid credentials' }, 401);
    const token = await createJWT({ username, role: 'admin' }, env.JWT_SECRET);
    return jsonResponse({ token, admin: { username, role: 'admin' } });
}

async function handleListPatches(request, env) {
    const { results } = await env.VINI_DB.prepare('SELECT * FROM patches ORDER BY created_at DESC').all();
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
    if (!file || !name || !bundleId || !version) return jsonResponse({ error: 'Missing required fields' }, 400);
    const id = crypto.randomUUID();
    await env.VINI_PATCHES.put(`patches/${id}.3105`, file.stream(), { httpMetadata: { contentType: 'application/octet-stream' } });
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
            await env.VINI_DB.prepare('UPDATE users SET patches = ? WHERE hwid = ?').bind(JSON.stringify(updated), user.hwid).run();
        }
    }
    return jsonResponse({ success: true });
}

async function handlePushToGitHub(request, env) {
    const patchId = request.url.split('/').slice(-2)[0];
    const githubToken = env.GITHUB_TOKEN;
    const repo = 'loboangel39-svg/VINI-IPA';
    const { results } = await env.VINI_DB.prepare('SELECT * FROM patches WHERE id = ?').bind(patchId).all();
    if (results.length === 0) return jsonResponse({ error: 'Patch not found' }, 404);
    const patch = results[0];
    const object = await env.VINI_PATCHES.get(`patches/${patchId}.3105`);
    if (!object) return jsonResponse({ error: 'File not found' }, 404);
    const buffer = await object.arrayBuffer();
    const base64 = btoa(String.fromCharCode(...new Uint8Array(buffer)));
    const filePath = `patches/${patch.name.replace(/[^a-zA-Z0-9]/g, '_')}.3105`;
    let sha = null;
    try {
        const existing = await fetch(`https://api.github.com/repos/${repo}/contents/${filePath}`, {
            headers: { 'Authorization': `token ${githubToken}`, 'User-Agent': 'VINI-Worker' },
        });
        if (existing.ok) { const data = await existing.json(); sha = data.sha; }
    } catch (e) { /* File doesn't exist yet */ }
    const body = { message: `Update patch: ${patch.name} v${patch.version}`, content: base64, branch: 'main' };
    if (sha) body.sha = sha;
    const res = await fetch(`https://api.github.com/repos/${repo}/contents/${filePath}`, {
        method: 'PUT',
        headers: { 'Authorization': `token ${githubToken}`, 'Content-Type': 'application/json', 'User-Agent': 'VINI-Worker' },
        body: JSON.stringify(body),
    });
    if (!res.ok) { const err = await res.json(); return jsonResponse({ error: err.message }, 500); }
    return jsonResponse({ success: true, path: filePath });
}

async function handleListUsers(request, env) {
    const { results } = await env.VINI_DB.prepare('SELECT * FROM users ORDER BY last_seen_at DESC').all();
    return jsonResponse(results.map(u => ({ ...u, patches: JSON.parse(u.patches || '[]') })));
}

async function handleUpdateUser(request, env) {
    const hwid = request.url.split('/').pop();
    const { active } = await request.json();
    await env.VINI_DB.prepare('UPDATE users SET active = ? WHERE hwid = ?').bind(active ? 1 : 0, hwid).run();
    return jsonResponse({ success: true });
}

async function handleAssignPatches(request, env) {
    const hwid = request.url.split('/').slice(-2)[0];
    const { patchIds } = await request.json();
    await env.VINI_DB.prepare('UPDATE users SET patches = ? WHERE hwid = ?').bind(JSON.stringify(patchIds), hwid).run();
    return jsonResponse({ success: true });
}

async function handleListLicenses(request, env) {
    const { results } = await env.VINI_DB.prepare('SELECT * FROM licenses ORDER BY created_at DESC').all();
    return jsonResponse(results);
}

async function handleGenerateLicense(request, env) {
    const { validDays, customKey } = await request.json();
    const key = customKey || generateKey();
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + (validDays || 30));
    await env.VINI_DB.prepare('INSERT INTO licenses (key, expires_at, created_at, revoked) VALUES (?, ?, datetime("now"), 0)').bind(key, expiresAt.toISOString()).run();
    return jsonResponse({ key, expiresAt: expiresAt.toISOString() }, 201);
}

async function handleRevokeLicense(request, env) {
    const key = request.url.split('/').pop();
    await env.VINI_DB.prepare('UPDATE licenses SET revoked = 1 WHERE key = ?').bind(key).run();
    return jsonResponse({ success: true });
}

async function handleUnbindLicense(request, env) {
    const parts = request.url.split('/');
    const key = parts[parts.length - 2];
    await env.VINI_DB.prepare('UPDATE licenses SET hwid = NULL, bound_at = NULL WHERE key = ?').bind(key).run();
    return jsonResponse({ success: true, message: 'License unbound successfully' });
}

async function handleUnbindAllLicenses(request, env) {
    await env.VINI_DB.prepare('UPDATE licenses SET hwid = NULL, bound_at = NULL WHERE hwid IS NOT NULL').run();
    return jsonResponse({ success: true, message: 'All licenses unbound successfully' });
}

async function handleDeleteLicense(request, env) {
    const parts = request.url.split('/');
    const key = parts[parts.length - 2];
    await env.VINI_DB.prepare('DELETE FROM licenses WHERE key = ?').bind(key).run();
    return jsonResponse({ success: true, message: 'License deleted successfully' });
}

async function handleGetConfig(request, env) {
    const configData = await env.VINI_CONFIG.get('app_config', 'json');
    return jsonResponse(configData || { featureFlags: {}, messages: [], settings: {} });
}

async function handleUpdateConfig(request, env) {
    const config = await request.json();
    if (!config.featureFlags && !config.settings) return jsonResponse({ error: 'Invalid config structure' }, 400);
    await env.VINI_CONFIG.put('app_config', JSON.stringify(config));
    return jsonResponse({ success: true });
}

async function handleListMessages(request, env) {
    const { results } = await env.VINI_DB.prepare('SELECT * FROM messages ORDER BY created_at DESC LIMIT 50').all();
    return jsonResponse(results);
}

async function handleCreateMessage(request, env) {
    const { title, content, type, targetHwid, expiresAt } = await request.json();
    if (!title || !content) return jsonResponse({ error: 'Title and content required' }, 400);
    const id = crypto.randomUUID();
    await env.VINI_DB.prepare(
        'INSERT INTO messages (id, title, content, type, target_hwid, expires_at, active, created_at) VALUES (?, ?, ?, ?, ?, ?, 1, datetime("now"))'
    ).bind(id, title, content, type || 'info', targetHwid || null, expiresAt || null).run();
    return jsonResponse({ id }, 201);
}

async function handleDeleteMessage(request, env) {
    const messageId = request.url.split('/').pop();
    await env.VINI_DB.prepare('UPDATE messages SET active = 0 WHERE id = ?').bind(messageId).run();
    return jsonResponse({ success: true });
}

async function handleGetStats(request, env) {
    const { results: totalUsers } = await env.VINI_DB.prepare('SELECT COUNT(*) as count FROM users WHERE active = 1').all();
    const { results: totalLicenses } = await env.VINI_DB.prepare('SELECT COUNT(*) as count FROM licenses WHERE revoked = 0').all();
    const { results: totalPatches } = await env.VINI_DB.prepare('SELECT COUNT(*) as count FROM patches').all();
    const { results: totalDownloads } = await env.VINI_DB.prepare('SELECT COALESCE(SUM(downloads), 0) as count FROM patches').all();
    return jsonResponse({
        totalUsers: totalUsers[0]?.count || 0,
        totalLicenses: totalLicenses[0]?.count || 0,
        totalPatches: totalPatches[0]?.count || 0,
        totalDownloads: totalDownloads[0]?.count || 0,
    });
}

async function handleGetRealtimeStats(request, env) {
    const { results: activeNow } = await env.VINI_DB.prepare(
        'SELECT COUNT(*) as count FROM users WHERE last_seen_at > datetime("now", "-5 minutes")'
    ).all();
    const { results: downloadsToday } = await env.VINI_DB.prepare(
        'SELECT COUNT(*) as count FROM telemetry WHERE event_type = "patch_download" AND created_at > datetime("now", "-1 day")'
    ).all();
    return jsonResponse({
        activeNow: activeNow[0]?.count || 0,
        downloadsToday: downloadsToday[0]?.count || 0,
        timestamp: new Date().toISOString(),
    });
}

async function handleListBanners(request, env) {
    const { results } = await env.VINI_DB.prepare('SELECT * FROM messages WHERE type = "banner" AND active = 1 ORDER BY created_at DESC').all();
    return jsonResponse(results);
}

async function handleCreateBanner(request, env) {
    const { title, content, expiresAt } = await request.json();
    if (!title || !content) return jsonResponse({ error: 'Title and content required' }, 400);
    const id = crypto.randomUUID();
    await env.VINI_DB.prepare(
        'INSERT INTO messages (id, title, content, type, expires_at, active, created_at) VALUES (?, ?, ?, "banner", ?, 1, datetime("now"))'
    ).bind(id, title, content, expiresAt || null).run();
    return jsonResponse({ id }, 201);
}

async function handleDeleteBanner(request, env) {
    const messageId = request.url.split('/').pop();
    await env.VINI_DB.prepare('UPDATE messages SET active = 0 WHERE id = ?').bind(messageId).run();
    return jsonResponse({ success: true });
}

async function handleListVersions(request, env) {
    const { results } = await env.VINI_DB.prepare('SELECT * FROM versions ORDER BY created_at DESC').all();
    return jsonResponse(results);
}

async function handleCreateVersion(request, env) {
    const { version, minIos, maxIos, changelog, downloadUrl, forceUpdate } = await request.json();
    if (!version) return jsonResponse({ error: 'Version required' }, 400);
    const id = crypto.randomUUID();
    await env.VINI_DB.prepare(
        'INSERT INTO versions (id, version, min_ios, max_ios, changelog, download_url, force_update, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, datetime("now"))'
    ).bind(id, version, minIos || '14.0', maxIos || '99.0', changelog || '', downloadUrl || '', forceUpdate ? 1 : 0).run();
    return jsonResponse({ id, version }, 201);
}

async function handleDeleteVersion(request, env) {
    const versionId = request.url.split('/').pop();
    await env.VINI_DB.prepare('DELETE FROM versions WHERE id = ?').bind(versionId).run();
    return jsonResponse({ success: true });
}

async function handleGetLogs(request, env) {
    const { results } = await env.VINI_DB.prepare('SELECT * FROM logs ORDER BY created_at DESC LIMIT 100').all();
    return jsonResponse(results);
}

async function handleClearLogs(request, env) {
    await env.VINI_DB.prepare('DELETE FROM logs').run();
    return jsonResponse({ success: true });
}

async function handleGetSecurity(request, env) {
    return jsonResponse({ message: 'Security settings endpoint' });
}

async function handleBlockIP(request, env) {
    const { ip } = await request.json();
    await env.VINI_DB.prepare('INSERT INTO logs (level, message, source, created_at) VALUES ("warning", ?, "security", datetime("now"))').bind(`IP blocked: ${ip}`).run();
    return jsonResponse({ success: true, blocked: ip });
}

async function handleUnblockIP(request, env) {
    const { ip } = await request.json();
    await env.VINI_DB.prepare('INSERT INTO logs (level, message, source, created_at) VALUES ("info", ?, "security", datetime("now"))').bind(`IP unblocked: ${ip}`).run();
    return jsonResponse({ success: true, unblocked: ip });
}

async function handleSetRateLimit(request, env) {
    const { requestsPerMinute } = await request.json();
    await env.VINI_CONFIG.put('rate_limit', JSON.stringify({ requestsPerMinute }));
    return jsonResponse({ success: true, requestsPerMinute });
}

async function handleListAPIKeys(request, env) {
    const configData = await env.VINI_CONFIG.get('api_keys', 'json');
    return jsonResponse(configData || []);
}

async function handleGenerateAPIKey(request, env) {
    const { name } = await request.json();
    const key = `vk_${generateKey(32)}`;
    const keys = (await env.VINI_CONFIG.get('api_keys', 'json')) || [];
    keys.push({ key, name, createdAt: new Date().toISOString() });
    await env.VINI_CONFIG.put('api_keys', JSON.stringify(keys));
    return jsonResponse({ key, name }, 201);
}

async function handleRevokeAPIKey(request, env) {
    const apiKey = request.url.split('/').pop();
    const keys = (await env.VINI_CONFIG.get('api_keys', 'json')) || [];
    const filtered = keys.filter(k => k.key !== apiKey);
    await env.VINI_CONFIG.put('api_keys', JSON.stringify(filtered));
    return jsonResponse({ success: true });
}

async function handleListWebhooks(request, env) {
    const configData = await env.VINI_CONFIG.get('webhooks', 'json');
    return jsonResponse(configData || []);
}

async function handleCreateWebhook(request, env) {
    const { url, events } = await request.json();
    if (!url) return jsonResponse({ error: 'URL required' }, 400);
    const id = crypto.randomUUID();
    const webhooks = (await env.VINI_CONFIG.get('webhooks', 'json')) || [];
    webhooks.push({ id, url, events: events || [], createdAt: new Date().toISOString() });
    await env.VINI_CONFIG.put('webhooks', JSON.stringify(webhooks));
    return jsonResponse({ id, url }, 201);
}

async function handleDeleteWebhook(request, env) {
    const webhookId = request.url.split('/').pop();
    const webhooks = (await env.VINI_CONFIG.get('webhooks', 'json')) || [];
    const filtered = webhooks.filter(w => w.id !== webhookId);
    await env.VINI_CONFIG.put('webhooks', JSON.stringify(filtered));
    return jsonResponse({ success: true });
}

async function handleGetMaintenance(request, env) {
    const configData = await env.VINI_CONFIG.get('maintenance', 'json');
    return jsonResponse(configData || { enabled: false, message: '' });
}

async function handleSetMaintenance(request, env) {
    const { enabled, message } = await request.json();
    await env.VINI_CONFIG.put('maintenance', JSON.stringify({ enabled: !!enabled, message: message || '' }));
    return jsonResponse({ success: true, enabled: !!enabled });
}
