// VINI V2 - Cloudflare Worker API
// Backend completo con D1 + R2

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

// === DEBUG STORAGE ===
if (path === '/debug/storage' && method === 'GET') {
  const db = await env.DB.prepare('SELECT 1 AS test').first();

  const object = await env.R2.head(
    'patches/0cb65ae9-3d46-4d79-ac4d-5d517ad522e7.3105'
  );

  return Response.json({
    worker: 'OK',
    d1: db?.test === 1 ? 'OK' : 'ERROR',
    r2: object ? 'OK' : 'NOT_FOUND',
    file: object ? {
      key: 'patches/0cb65ae9-3d46-4d79-ac4d-5d517ad522e7.3105',
      size: object.size
    } : null
  });
}

    // CORS
    if (method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        },
      });
    }

    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Content-Type': 'application/json',
    };

    try {
      // === AUTH ROUTES ===
      if (path === '/api/admin/login' && method === 'POST') {
        return handleLogin(request, env, corsHeaders);
      }

      // Verify auth for all other routes
      const auth = await verifyAuth(request, env);
      if (!auth.valid) {
        return Response.json({ error: 'Unauthorized' }, { status: 401, headers: corsHeaders });
      }

      // === DASHBOARD ===
      if (path === '/api/dashboard/stats' && method === 'GET') {
        return handleDashboardStats(env, corsHeaders);
      }
      if (path === '/api/dashboard/activity' && method === 'GET') {
        return handleDashboardActivity(env, corsHeaders);
      }

      // === USERS ===
      if (path === '/api/users' && method === 'GET') {
        return handleGetUsers(env, corsHeaders, url);
      }
      if (path === '/api/users' && method === 'POST') {
        return handleCreateUser(request, env, corsHeaders);
      }
      if (path.match(/^\/api\/users\/[^/]+$/) && method === 'PUT') {
        const id = path.split('/')[3];
        return handleUpdateUser(id, request, env, corsHeaders);
      }
      if (path.match(/^\/api\/users\/[^/]+\/pause$/) && method === 'POST') {
        const id = path.split('/')[3];
        return handleTogglePause(id, env, corsHeaders);
      }
      if (path.match(/^\/api\/users\/[^/]+\/hwid$/) && method === 'POST') {
        const id = path.split('/')[3];
        return handleResetHWID(id, env, corsHeaders);
      }
      if (path.match(/^\/api\/users\/[^/]+\/block$/) && method === 'POST') {
        const id = path.split('/')[3];
        return handleToggleBlock(id, env, corsHeaders);
      }

      // === PATCHES ===
      if (path === '/api/patches' && method === 'GET') {
        return handleGetPatches(env, corsHeaders, url);
      }
      if (path === '/api/patches' && method === 'POST') {
        return handleCreatePatch(request, env, corsHeaders);
      }
      if (path.match(/^\/api\/patches\/[^/]+$/) && method === 'PUT') {
        const id = path.split('/')[3];
        return handleUpdatePatch(id, request, env, corsHeaders);
      }
      if (path.match(/^\/api\/patches\/[^/]+$/) && method === 'DELETE') {
        const id = path.split('/')[3];
        return handleDeletePatch(id, env, corsHeaders);
      }
      if (path.match(/^\/api\/patches\/[^/]+\/toggle$/) && method === 'POST') {
        const id = path.split('/')[3];
        return handleTogglePatch(id, env, corsHeaders);
      }

      // === ACCESS ===
      if (path === '/api/access' && method === 'GET') {
        return handleGetAccess(env, corsHeaders);
      }
      if (path === '/api/access' && method === 'POST') {
        return handleGrantAccess(request, env, corsHeaders);
      }
      if (path === '/api/access' && method === 'DELETE') {
        return handleRevokeAccess(request, env, corsHeaders);
      }

      // === MESSAGES ===
      if (path === '/api/messages' && method === 'GET') {
        return handleGetMessages(env, corsHeaders);
      }
      if (path === '/api/messages' && method === 'POST') {
        return handleCreateMessage(request, env, corsHeaders);
      }
      if (path.match(/^\/api\/messages\/[^/]+$/) && method === 'PUT') {
        const id = path.split('/')[3];
        return handleUpdateMessage(id, request, env, corsHeaders);
      }
      if (path.match(/^\/api\/messages\/[^/]+$/) && method === 'DELETE') {
        const id = path.split('/')[3];
        return handleDeleteMessage(id, env, corsHeaders);
      }
      if (path.match(/^\/api\/messages\/[^/]+\/toggle$/) && method === 'POST') {
        const id = path.split('/')[3];
        return handleToggleMessage(id, env, corsHeaders);
      }

      // === STATS ===
      if (path === '/api/stats' && method === 'GET') {
        return handleStats(env, corsHeaders, url);
      }

      // === ACTIVITY LOG ===
      if (path === '/api/activity' && method === 'GET') {
        return handleGetActivity(env, corsHeaders, url);
      }

      // === CONFIG ===
      if (path === '/api/config' && method === 'GET') {
        return handleGetConfig(env, corsHeaders);
      }
      if (path === '/api/config' && method === 'PUT') {
        return handleUpdateConfig(request, env, corsHeaders);
      }

      return Response.json({ error: 'Not found' }, { status: 404, headers: corsHeaders });
    } catch (err) {
      return Response.json({ error: err.message }, { status: 500, headers: corsHeaders });
    }
  },
};

// === AUTH HELPERS ===

async function handleLogin(request, env, headers) {
  const { username, password } = await request.json();
  const adminUser = env.ADMIN_USERNAME || 'admin';
  const adminPass = env.ADMIN_PASSWORD || 'vini2026';

  if (username === adminUser && password === adminPass) {
    const token = await createJWT({ user: username, exp: Date.now() + 86400000 }, env);
    return Response.json({ token, username }, { headers });
  }
  return Response.json({ error: 'Invalid credentials' }, { status: 401, headers });
}

async function createJWT(payload, env) {
  const secret = env.JWT_SECRET || 'vini-jwt-secret-change-me';
  const header = btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = btoa(JSON.stringify(payload));
  const signature = await hmacSign(`${header}.${body}`, secret);
  return `${header}.${body}.${signature}`;
}

async function verifyAuth(request, env) {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) return { valid: false };

  const token = authHeader.split(' ')[1];
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return { valid: false };
    const payload = JSON.parse(atob(parts[1]));
    if (payload.exp < Date.now()) return { valid: false };

    const secret = env.JWT_SECRET || 'vini-jwt-secret-change-me';
    const expectedSig = await hmacSign(`${parts[0]}.${parts[1]}`, secret);
    if (expectedSig !== parts[2]) return { valid: false };

    return { valid: true, user: payload.user };
  } catch {
    return { valid: false };
  }
}

async function hmacSign(data, secret) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(data));
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

// === LOG ACTIVITY ===

async function logActivity(env, action, details) {
  await env.DB.prepare(
    'INSERT INTO activity_log (action, details, created_at) VALUES (?, ?, ?)'
  ).bind(action, details, new Date().toISOString()).run();
}

// === DASHBOARD ===

async function handleDashboardStats(env, headers) {
  const users = await env.DB.prepare('SELECT COUNT(*) as count FROM users').first();
  const patches = await env.DB.prepare('SELECT COUNT(*) as count FROM patches').first();
  const activePatches = await env.DB.prepare('SELECT COUNT(*) as count FROM patches WHERE active = 1').first();
  const downloads = await env.DB.prepare('SELECT COUNT(*) as count FROM downloads').first();

  return Response.json({
    totalUsers: users.count,
    totalPatches: patches.count,
    activePatches: activePatches.count,
    totalDownloads: downloads.count,
  }, { headers });
}

async function handleDashboardActivity(env, headers) {
  const result = await env.DB.prepare(
    'SELECT * FROM activity_log ORDER BY created_at DESC LIMIT 10'
  ).all();
  return Response.json(result.results, { headers });
}

// === USERS ===

async function handleGetUsers(env, headers, url) {
  const search = url.searchParams.get('search') || '';
  let query = 'SELECT * FROM users';
  if (search) query += ` WHERE username LIKE '%${search}%' OR hwid LIKE '%${search}%'`;
  query += ' ORDER BY created_at DESC';
  const result = await env.DB.prepare(query).all();
  return Response.json(result.results, { headers });
}

async function handleCreateUser(request, env, headers) {
  const data = await request.json();
  const id = crypto.randomUUID();
  const now = new Date().toISOString();

  await env.DB.prepare(
    `INSERT INTO users (id, username, hwid, license_key, is_premium, is_active, is_paused, is_blocked, permissions, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 1, 0, 0, ?, ?, ?)`
  ).bind(
    id, data.username, data.hwid || '', data.licenseKey || '',
    data.isPremium ? 1 : 0, data.permissions || '{}', now, now
  ).run();

  await logActivity(env, 'user_created', `User ${data.username} created`);
  return Response.json({ id, ...data }, { headers });
}

async function handleUpdateUser(id, request, env, headers) {
  const data = await request.json();
  const now = new Date().toISOString();

  await env.DB.prepare(
    `UPDATE users SET username = ?, hwid = ?, license_key = ?, is_premium = ?, permissions = ?, updated_at = ? WHERE id = ?`
  ).bind(data.username, data.hwid || '', data.licenseKey || '',
    data.isPremium ? 1 : 0, data.permissions || '{}', now, id
  ).run();

  await logActivity(env, 'user_updated', `User ${id} updated`);
  return Response.json({ success: true }, { headers });
}

async function handleTogglePause(id, env, headers) {
  const user = await env.DB.prepare('SELECT is_paused FROM users WHERE id = ?').bind(id).first();
  const newState = user.is_paused ? 0 : 1;
  await env.DB.prepare('UPDATE users SET is_paused = ? WHERE id = ?').bind(newState, id).run();
  await logActivity(env, 'user_paused', `User ${id} ${newState ? 'paused' : 'resumed'}`);
  return Response.json({ is_paused: newState }, { headers });
}

async function handleResetHWID(id, env, headers) {
  await env.DB.prepare('UPDATE users SET hwid = ? WHERE id = ?').bind('', id).run();
  await logActivity(env, 'hwid_reset', `User ${id} HWID reset`);
  return Response.json({ success: true }, { headers });
}

async function handleToggleBlock(id, env, headers) {
  const user = await env.DB.prepare('SELECT is_blocked FROM users WHERE id = ?').bind(id).first();
  const newState = user.is_blocked ? 0 : 1;
  await env.DB.prepare('UPDATE users SET is_blocked = ? WHERE id = ?').bind(newState, id).run();
  await logActivity(env, 'user_blocked', `User ${id} ${newState ? 'blocked' : 'unblocked'}`);
  return Response.json({ is_blocked: newState }, { headers });
}

// === PATCHES ===

async function handleGetPatches(env, headers, url) {
  const type = url.searchParams.get('type') || '';
  let query = 'SELECT * FROM patches';
  if (type) query += ` WHERE type = '${type}'`;
  query += ' ORDER BY created_at DESC';
  const result = await env.DB.prepare(query).all();
  return Response.json(result.results, { headers });
}

async function handleCreatePatch(request, env, headers) {
  const formData = await request.formData();
  const id = crypto.randomUUID();
  const name = formData.get('name');
  const description = formData.get('description') || '';
  const version = formData.get('version') || '1.0.0';
  const type = formData.get('type') || 'free';
  const file = formData.get('file');

  let fileKey = '';
  if (file && file.size > 0) {
    fileKey = `patches/${id}/${file.name}`;
    await env.R2.put(fileKey, file.stream());
  }

  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO patches (id, name, description, version, type, file_key, active, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)`
  ).bind(id, name, description, version, type, fileKey, now, now).run();

  await logActivity(env, 'patch_created', `Patch "${name}" created`);
  return Response.json({ id, name, version, type }, { headers });
}

async function handleUpdatePatch(id, request, env, headers) {
  const formData = await request.formData();
  const name = formData.get('name');
  const description = formData.get('description') || '';
  const version = formData.get('version') || '1.0.0';
  const type = formData.get('type') || 'free';
  const file = formData.get('file');

  let patch = await env.DB.prepare('SELECT file_key FROM patches WHERE id = ?').bind(id).first();

  if (file && file.size > 0) {
    const fileKey = `patches/${id}/${file.name}`;
    await env.R2.put(fileKey, file.stream());
    if (patch.file_key) await env.R2.delete(patch.file_key);
    patch = { file_key: fileKey };
  }

  const now = new Date().toISOString();
  await env.DB.prepare(
    `UPDATE patches SET name = ?, description = ?, version = ?, type = ?, file_key = ?, updated_at = ? WHERE id = ?`
  ).bind(name, description, version, type, patch.file_key, now, id).run();

  await logActivity(env, 'patch_updated', `Patch ${id} updated`);
  return Response.json({ success: true }, { headers });
}

async function handleDeletePatch(id, env, headers) {
  const patch = await env.DB.prepare('SELECT file_key FROM patches WHERE id = ?').bind(id).first();
  if (patch?.file_key) await env.R2.delete(patch.file_key);
  await env.DB.prepare('DELETE FROM user_patches WHERE patch_id = ?').bind(id).run();
  await env.DB.prepare('DELETE FROM patches WHERE id = ?').bind(id).run();
  await logActivity(env, 'patch_deleted', `Patch ${id} deleted`);
  return Response.json({ success: true }, { headers });
}

async function handleTogglePatch(id, env, headers) {
  const patch = await env.DB.prepare('SELECT active FROM patches WHERE id = ?').bind(id).first();
  const newState = patch.active ? 0 : 1;
  await env.DB.prepare('UPDATE patches SET active = ? WHERE id = ?').bind(newState, id).run();
  await logActivity(env, 'patch_toggled', `Patch ${id} ${newState ? 'activated' : 'deactivated'}`);
  return Response.json({ active: newState }, { headers });
}

// === ACCESS ===

async function handleGetAccess(env, headers) {
  const result = await env.DB.prepare(
    `SELECT up.*, u.username, p.name as patch_name 
     FROM user_patches up 
     JOIN users u ON up.user_id = u.id 
     JOIN patches p ON up.patch_id = p.id 
     ORDER BY up.created_at DESC`
  ).all();
  return Response.json(result.results, { headers });
}

async function handleGrantAccess(request, env, headers) {
  const { userId, patchId } = await request.json();
  const now = new Date().toISOString();

  await env.DB.prepare(
    'INSERT OR IGNORE INTO user_patches (user_id, patch_id, created_at) VALUES (?, ?, ?)'
  ).bind(userId, patchId, now).run();

  await logActivity(env, 'access_granted', `Access granted: user ${userId} -> patch ${patchId}`);
  return Response.json({ success: true }, { headers });
}

async function handleRevokeAccess(request, env, headers) {
  const { userId, patchId } = await request.json();
  await env.DB.prepare(
    'DELETE FROM user_patches WHERE user_id = ? AND patch_id = ?'
  ).bind(userId, patchId).run();

  await logActivity(env, 'access_revoked', `Access revoked: user ${userId} -> patch ${patchId}`);
  return Response.json({ success: true }, { headers });
}

// === MESSAGES ===

async function handleGetMessages(env, headers) {
  const result = await env.DB.prepare('SELECT * FROM messages ORDER BY created_at DESC').all();
  return Response.json(result.results, { headers });
}

async function handleCreateMessage(request, env, headers) {
  const data = await request.json();
  const id = crypto.randomUUID();
  const now = new Date().toISOString();

  await env.DB.prepare(
    `INSERT INTO messages (id, title, content, type, target_hwid, active, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 1, ?, ?)`
  ).bind(id, data.title, data.content, data.type || 'info', data.targetHwid || null, now, now).run();

  await logActivity(env, 'message_created', `Message "${data.title}" created`);
  return Response.json({ id }, { headers });
}

async function handleUpdateMessage(id, request, env, headers) {
  const data = await request.json();
  const now = new Date().toISOString();

  await env.DB.prepare(
    `UPDATE messages SET title = ?, content = ?, type = ?, target_hwid = ?, updated_at = ? WHERE id = ?`
  ).bind(data.title, data.content, data.type, data.targetHwid || null, now, id).run();

  return Response.json({ success: true }, { headers });
}

async function handleDeleteMessage(id, env, headers) {
  await env.DB.prepare('DELETE FROM messages WHERE id = ?').bind(id).run();
  await logActivity(env, 'message_deleted', `Message ${id} deleted`);
  return Response.json({ success: true }, { headers });
}

async function handleToggleMessage(id, env, headers) {
  const msg = await env.DB.prepare('SELECT active FROM messages WHERE id = ?').bind(id).first();
  const newState = msg.active ? 0 : 1;
  await env.DB.prepare('UPDATE messages SET active = ? WHERE id = ?').bind(newState, id).run();
  return Response.json({ active: newState }, { headers });
}

// === STATS ===

async function handleStats(env, headers, url) {
  const type = url.searchParams.get('type') || 'all';

  if (type === 'downloads') {
    const result = await env.DB.prepare(
      `SELECT DATE(created_at) as date, COUNT(*) as count 
       FROM downloads 
       WHERE created_at > datetime('now', '-30 days')
       GROUP BY DATE(created_at) ORDER BY date`
    ).all();
    return Response.json(result.results, { headers });
  }

  if (type === 'popular') {
    const result = await env.DB.prepare(
      `SELECT p.name, COUNT(d.id) as downloads 
       FROM downloads d JOIN patches p ON d.patch_id = p.id 
       GROUP BY d.patch_id ORDER BY downloads DESC LIMIT 10`
    ).all();
    return Response.json(result.results, { headers });
  }

  // All stats
  const users = await env.DB.prepare('SELECT COUNT(*) as count FROM users').first();
  const patches = await env.DB.prepare('SELECT COUNT(*) as count FROM patches').first();
  const downloads = await env.DB.prepare('SELECT COUNT(*) as count FROM downloads').first();
  const todayDownloads = await env.DB.prepare(
    "SELECT COUNT(*) as count FROM downloads WHERE DATE(created_at) = DATE('now')"
  ).first();

  return Response.json({
    totalUsers: users.count,
    totalPatches: patches.count,
    totalDownloads: downloads.count,
    todayDownloads: todayDownloads.count,
  }, { headers });
}

// === ACTIVITY ===

async function handleGetActivity(env, headers, url) {
  const limit = parseInt(url.searchParams.get('limit') || '50');
  const result = await env.DB.prepare(
    'SELECT * FROM activity_log ORDER BY created_at DESC LIMIT ?'
  ).bind(limit).all();
  return Response.json(result.results, { headers });
}

// === CONFIG ===

async function handleGetConfig(env, headers) {
  const result = await env.DB.prepare('SELECT * FROM config ORDER BY key').all();
  const config = {};
  result.results.forEach(r => { config[r.key] = r.value; });
  return Response.json(config, { headers });
}

async function handleUpdateConfig(request, env, headers) {
  const data = await request.json();
  const now = new Date().toISOString();

  for (const [key, value] of Object.entries(data)) {
    await env.DB.prepare(
      `INSERT INTO config (key, value, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET value = ?, updated_at = ?`
    ).bind(key, value, now, value, now).run();
  }

  await logActivity(env, 'config_updated', 'Configuration updated');
  return Response.json({ success: true }, { headers });
}
