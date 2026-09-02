// VINI Super Admin Panel - Complete JavaScript
// All features: Dashboard, Patches, Users, Licenses, Messages, Features, Banners, Versions, Analytics, Logs, Security, Webhooks, Maintenance

const API_BASE = localStorage.getItem('workerUrl') || 'https://vini-worker.your-subdomain.workers.dev';

let authToken = localStorage.getItem('adminToken');
let currentUser = JSON.parse(localStorage.getItem('adminUser') || 'null');
let charts = {};
let refreshInterval = null;

// ========== INIT ==========
if (authToken && currentUser) {
    showMainApp();
}

document.getElementById('loginForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const username = document.getElementById('loginUsername').value;
    const password = document.getElementById('loginPassword').value;

    try {
        const res = await fetch(`${API_BASE}/api/admin/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password })
        });
        const data = await res.json();
        if (data.token) {
            authToken = data.token;
            currentUser = data.admin;
            localStorage.setItem('adminToken', authToken);
            localStorage.setItem('adminUser', JSON.stringify(currentUser));
            showMainApp();
        } else {
            showToast('Credenciales inválidas', 'error');
        }
    } catch (err) {
        showToast('Error de conexión', 'error');
    }
});

function logout() {
    authToken = null;
    currentUser = null;
    localStorage.removeItem('adminToken');
    localStorage.removeItem('adminUser');
    if (refreshInterval) clearInterval(refreshInterval);
    document.getElementById('loginScreen').classList.remove('hidden');
    document.getElementById('mainApp').classList.add('hidden');
}

function showMainApp() {
    document.getElementById('loginScreen').classList.add('hidden');
    document.getElementById('mainApp').classList.remove('hidden');
    loadAllData();
    refreshInterval = setInterval(loadAllData, 30000);
}

function loadAllData() {
    loadDashboardStats();
    loadPatches();
    loadUsers();
    loadLicenses();
    loadMessages();
    loadFeatures();
    loadBanners();
    loadVersions();
    loadLogs();
    loadSecurity();
    loadWebhooks();
    loadMaintenance();
    loadSettings();
}

// ========== NAVIGATION ==========
function showSection(section) {
    document.querySelectorAll('.section').forEach(el => el.classList.add('hidden'));
    document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
    
    document.getElementById(`${section}Section`).classList.remove('hidden');
    event.currentTarget.classList.add('active');
    
    const titles = {
        dashboard: 'Dashboard', patches: 'Patches', users: 'Usuarios',
        licenses: 'Licencias', messages: 'Mensajes', features: 'Feature Flags',
        banners: 'Banners', versions: 'Versiones', analytics: 'Analíticas',
        logs: 'Logs', security: 'Seguridad', webhooks: 'Webhooks',
        maintenance: 'Mantenimiento', settings: 'Configuración'
    };
    document.getElementById('sectionTitle').textContent = titles[section] || section;
}

function toggleSidebar() {
    document.getElementById('sidebar').classList.toggle('collapsed');
    document.getElementById('mainContent').classList.toggle('expanded');
}

// ========== MODALS ==========
function openModal(id) {
    document.getElementById(id).classList.add('active');
}

function closeModal(id) {
    document.getElementById(id).classList.remove('active');
}

// ========== DASHBOARD ==========
async function loadDashboardStats() {
    try {
        const [statsRes, realtimeRes] = await Promise.all([
            fetch(`${API_BASE}/api/stats`, { headers: { 'Authorization': `Bearer ${authToken}` } }),
            fetch(`${API_BASE}/api/stats/realtime`, { headers: { 'Authorization': `Bearer ${authToken}` } })
        ]);

        const stats = await statsRes.json();
        const realtime = await realtimeRes.json();

        document.getElementById('statUsers').textContent = stats.totalUsers || 0;
        document.getElementById('statLicenses').textContent = stats.totalLicenses || 0;
        document.getElementById('statPatches').textContent = stats.totalPatches || 0;
        document.getElementById('statDownloads').textContent = stats.totalDownloads || 0;
        document.getElementById('statOnline').textContent = stats.activeToday || 0;

        renderCharts(realtime);
        renderRecentActivity(stats.recentEvents || []);
    } catch (err) {
        console.error('Error loading stats:', err);
    }
}

function renderCharts(realtime) {
    // Activity Chart
    const actCtx = document.getElementById('activityChart');
    if (charts.activity) charts.activity.destroy();
    
    const hours = realtime.hourlyActivity || [];
    charts.activity = new Chart(actCtx, {
        type: 'line',
        data: {
            labels: hours.map(h => new Date(h.hour).toLocaleTimeString('es', { hour: '2-digit' })),
            datasets: [{
                label: 'Eventos',
                data: hours.map(h => h.events),
                borderColor: '#667eea',
                backgroundColor: 'rgba(102, 126, 234, 0.1)',
                tension: 0.4,
                fill: true
            }]
        },
        options: { responsive: true, plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true } } }
    });

    // Patches Chart
    const patchCtx = document.getElementById('patchesChart');
    if (charts.patches) charts.patches.destroy();
    
    const patches = realtime.patchPopularity || [];
    charts.patches = new Chart(patchCtx, {
        type: 'bar',
        data: {
            labels: patches.map(p => p.name),
            datasets: [{
                label: 'Descargas',
                data: patches.map(p => p.downloads),
                backgroundColor: '#667eea'
            }]
        },
        options: { responsive: true, plugins: { legend: { display: false } }, scales: { y: { beginAtZero: true } } }
    });

    // Device Chart
    const devCtx = document.getElementById('deviceChart');
    if (charts.device) charts.device.destroy();
    
    const devices = realtime.deviceBreakdown || [];
    charts.device = new Chart(devCtx, {
        type: 'doughnut',
        data: {
            labels: devices.map(d => `${d.device_model || 'Unknown'} (iOS ${d.ios_version || '?'})`),
            datasets: [{
                data: devices.map(d => d.count),
                backgroundColor: ['#667eea', '#764ba2', '#f093fb', '#f5576c', '#38ef7d', '#4facfe']
            }]
        },
        options: { responsive: true, plugins: { legend: { position: 'bottom' } } }
    });
}

function renderRecentActivity(events) {
    const container = document.getElementById('recentActivity');
    if (events.length === 0) {
        container.innerHTML = '<p class="text-gray-500 text-center py-4">No hay actividad reciente</p>';
        return;
    }

    container.innerHTML = events.map(event => `
        <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
            <div class="flex items-center space-x-3">
                <i class="fas fa-${getEventIcon(event.event_type)} text-purple-600"></i>
                <div>
                    <p class="font-medium text-gray-800">${event.event_type}</p>
                    <p class="text-xs text-gray-500">${event.count} ocurrencias</p>
                </div>
            </div>
        </div>
    `).join('');
}

function getEventIcon(type) {
    const icons = { 'session_start': 'play-circle', 'patch_download': 'download', 'app_launch': 'rocket', 'error': 'exclamation-circle' };
    return icons[type] || 'circle';
}

// ========== PATCHES ==========
let patches = [];

async function loadPatches() {
    try {
        const res = await fetch(`${API_BASE}/api/patches`, { headers: { 'Authorization': `Bearer ${authToken}` } });
        patches = await res.json();
        renderPatches();
    } catch (err) {
        console.error('Error loading patches:', err);
    }
}

function renderPatches() {
    const container = document.getElementById('patchesGrid');
    if (!patches || patches.length === 0) {
        container.innerHTML = '<div class="col-span-3 text-center py-12"><i class="fas fa-puzzle-piece text-4xl text-gray-300 mb-4"></i><p class="text-gray-500">No hay patches</p></div>';
        return;
    }

    container.innerHTML = patches.map(patch => `
        <div class="bg-white rounded-xl shadow card-hover p-6">
            <div class="flex justify-between items-start mb-4">
                <div>
                    <h3 class="text-lg font-bold text-gray-800">${patch.name}</h3>
                    <p class="text-sm text-gray-500">${patch.bundle_id}</p>
                </div>
                <span class="px-2 py-1 text-xs font-medium bg-purple-100 text-purple-800 rounded-full">v${patch.version}</span>
            </div>
            <p class="text-sm text-gray-600 mb-4">${patch.description || 'Sin descripción'}</p>
            <div class="flex items-center justify-between text-sm text-gray-500 mb-4">
                <span><i class="fas fa-download mr-1"></i>${patch.downloads || 0} descargas</span>
                <span><i class="fas fa-calendar mr-1"></i>${new Date(patch.created_at).toLocaleDateString()}</span>
            </div>
            <div class="flex space-x-2">
                <button onclick="editPatch('${patch.id}')" class="flex-1 bg-blue-50 text-blue-600 py-2 rounded-lg hover:bg-blue-100 text-sm font-medium">
                    <i class="fas fa-edit mr-1"></i>Editar
                </button>
                <button onclick="pushToGitHub('${patch.id}')" class="flex-1 bg-green-50 text-green-600 py-2 rounded-lg hover:bg-green-100 text-sm font-medium">
                    <i class="fab fa-github mr-1"></i>GitHub
                </button>
                <button onclick="deletePatch('${patch.id}')" class="flex-1 bg-red-50 text-red-600 py-2 rounded-lg hover:bg-red-100 text-sm font-medium">
                    <i class="fas fa-trash mr-1"></i>
                </button>
            </div>
        </div>
    `).join('');
}

async function createPatch() {
    const formData = new FormData();
    formData.append('file', document.getElementById('patchFile').files[0]);
    formData.append('name', document.getElementById('patchName').value);
    formData.append('bundleId', document.getElementById('patchBundleId').value);
    formData.append('version', document.getElementById('patchVersion').value);
    formData.append('description', document.getElementById('patchDescription').value);

    try {
        const res = await fetch(`${API_BASE}/api/patches`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${authToken}` },
            body: formData
        });
        if (res.ok) {
            showToast('Patch creado', 'success');
            closeModal('newPatchModal');
            document.getElementById('newPatchForm').reset();
            loadPatches();
        } else {
            showToast('Error creando patch', 'error');
        }
    } catch (err) {
        showToast('Error de conexión', 'error');
    }
}

async function deletePatch(id) {
    if (!confirm('¿Eliminar este patch?')) return;
    try {
        await fetch(`${API_BASE}/api/patches/${id}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        showToast('Patch eliminado', 'success');
        loadPatches();
    } catch (err) {
        showToast('Error', 'error');
    }
}

async function pushToGitHub(patchId) {
    showToast('Subiendo a GitHub...', 'info');
    try {
        const res = await fetch(`${API_BASE}/api/patches/${patchId}/push-github`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        if (res.ok) {
            showToast('Subido a GitHub', 'success');
        } else {
            const data = await res.json();
            showToast(data.error || 'Error', 'error');
        }
    } catch (err) {
        showToast('Error', 'error');
    }
}

function editPatch(id) {
    showToast('Editor de patches - próximamente', 'info');
}

// ========== USERS ==========
let users = [];
let selectedUserHwid = null;

async function loadUsers() {
    try {
        const res = await fetch(`${API_BASE}/api/users`, { headers: { 'Authorization': `Bearer ${authToken}` } });
        users = await res.json();
        renderUsers();
    } catch (err) {
        console.error('Error loading users:', err);
    }
}

function renderUsers() {
    const tbody = document.getElementById('usersTable');
    if (!users || users.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="px-6 py-8 text-center text-gray-500">No hay usuarios</td></tr>';
        return;
    }

    tbody.innerHTML = users.map(user => `
        <tr class="hover:bg-gray-50">
            <td class="px-6 py-4 text-sm font-mono">${user.hwid.substring(0, 12)}...</td>
            <td class="px-6 py-4 text-sm">${user.device_model || '-'}</td>
            <td class="px-6 py-4 text-sm">${user.ios_version || '-'}</td>
            <td class="px-6 py-4"><span class="px-2 py-1 bg-purple-100 text-purple-800 rounded-full text-xs">${(user.patches || []).length}</span></td>
            <td class="px-6 py-4"><span class="px-2 py-1 text-xs font-medium ${user.active ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'} rounded-full">${user.active ? 'Activo' : 'Inactivo'}</span></td>
            <td class="px-6 py-4 text-sm text-gray-500">${user.last_seen_at ? new Date(user.last_seen_at).toLocaleString('es') : 'Nunca'}</td>
            <td class="px-6 py-4 text-sm">
                <button onclick="viewUserDetail('${user.hwid}')" class="text-blue-600 hover:text-blue-800 mr-2"><i class="fas fa-eye"></i></button>
                <button onclick="assignPatchesToUser('${user.hwid}')" class="text-purple-600 hover:text-purple-800 mr-2"><i class="fas fa-puzzle-piece"></i></button>
                <button onclick="toggleUser('${user.hwid}', ${!user.active})" class="${user.active ? 'text-red-600' : 'text-green-600'}"><i class="fas ${user.active ? 'fa-ban' : 'fa-check'}"></i></button>
            </td>
        </tr>
    `).join('');
}

async function toggleUser(hwid, active) {
    try {
        await fetch(`${API_BASE}/api/users/${hwid}`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${authToken}` },
            body: JSON.stringify({ active })
        });
        showToast(`Usuario ${active ? 'activado' : 'desactivado'}`, 'success');
        loadUsers();
    } catch (err) {
        showToast('Error', 'error');
    }
}

async function assignPatchesToUser(hwid) {
    selectedUserHwid = hwid;
    const user = users.find(u => u.hwid === hwid);
    const userPatches = user?.patches || [];

    const container = document.getElementById('assignPatchesList');
    container.innerHTML = patches.map(patch => `
        <label class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg hover:bg-gray-100 cursor-pointer">
            <input type="checkbox" value="${patch.id}" ${userPatches.includes(patch.id) ? 'checked' : ''} class="w-4 h-4 text-purple-600 rounded">
            <div>
                <span class="font-medium text-gray-800">${patch.name}</span>
                <span class="text-sm text-gray-500 ml-2">v${patch.version}</span>
            </div>
        </label>
    `).join('');

    openModal('assignPatchesModal');
}

async function saveAssignedPatches() {
    const checkboxes = document.querySelectorAll('#assignPatchesList input:checked');
    const patchIds = Array.from(checkboxes).map(cb => cb.value);

    try {
        await fetch(`${API_BASE}/api/users/${selectedUserHwid}/patches`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${authToken}` },
            body: JSON.stringify({ patchIds })
        });
        showToast('Patches asignados', 'success');
        closeModal('assignPatchesModal');
        loadUsers();
    } catch (err) {
        showToast('Error', 'error');
    }
}

function viewUserDetail(hwid) {
    const user = users.find(u => u.hwid === hwid);
    if (!user) return;

    const content = document.getElementById('userDetailContent');
    content.innerHTML = `
        <div class="space-y-4">
            <div class="grid grid-cols-2 gap-4">
                <div><p class="text-sm text-gray-500">HWID</p><p class="font-mono text-sm">${user.hwid}</p></div>
                <div><p class="text-sm text-gray-500">Dispositivo</p><p class="text-sm">${user.device_model || '-'}</p></div>
                <div><p class="text-sm text-gray-500">iOS</p><p class="text-sm">${user.ios_version || '-'}</p></div>
                <div><p class="text-sm text-gray-500">Estado</p><p class="text-sm">${user.active ? 'Activo' : 'Inactivo'}</p></div>
                <div><p class="text-sm text-gray-500">Creado</p><p class="text-sm">${new Date(user.created_at).toLocaleString('es')}</p></div>
                <div><p class="text-sm text-gray-500">Última vez</p><p class="text-sm">${user.last_seen_at ? new Date(user.last_seen_at).toLocaleString('es') : 'Nunca'}</p></div>
            </div>
            <div>
                <p class="text-sm text-gray-500 mb-2">Patches Asignados</p>
                <div class="space-y-2">
                    ${(user.patches || []).map(pid => {
                        const patch = patches.find(p => p.id === pid);
                        return patch ? `<div class="p-2 bg-gray-50 rounded">${patch.name} v${patch.version}</div>` : '';
                    }).join('')}
                </div>
            </div>
        </div>
    `;
    openModal('userDetailModal');
}

function exportUsers() {
    const csv = 'HWID,Dispositivo,iOS,Patches,Estado,Última Vez\n' +
        users.map(u => `${u.hwid},${u.device_model},${u.ios_version},${(u.patches || []).length},${u.active ? 'Activo' : 'Inactivo'},${u.last_seen_at || 'Nunca'}`).join('\n');
    
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'usuarios_vini.csv';
    a.click();
    showToast('Usuarios exportados', 'success');
}

// ========== LICENSES ==========
let licenses = [];

async function loadLicenses() {
    try {
        const res = await fetch(`${API_BASE}/api/licenses`, { headers: { 'Authorization': `Bearer ${authToken}` } });
        licenses = await res.json();
        renderLicenses();
    } catch (err) {
        console.error('Error loading licenses:', err);
    }
}

function renderLicenses() {
    const tbody = document.getElementById('licensesTable');
    if (!licenses || licenses.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="px-6 py-8 text-center text-gray-500">No hay licencias</td></tr>';
        return;
    }

    tbody.innerHTML = licenses.map(lic => {
        const expired = new Date(lic.expires_at) < new Date();
        return `
        <tr class="hover:bg-gray-50">
            <td class="px-6 py-4 text-sm font-mono">${lic.key}</td>
            <td class="px-6 py-4 text-sm">${new Date(lic.expires_at).toLocaleDateString('es')}</td>
            <td class="px-6 py-4"><span class="px-2 py-1 text-xs font-medium ${expired || lic.revoked ? 'bg-red-100 text-red-800' : 'bg-green-100 text-green-800'} rounded-full">${lic.revoked ? 'Revocada' : expired ? 'Expirada' : 'Activa'}</span></td>
            <td class="px-6 py-4 text-sm font-mono">${lic.hwid ? lic.hwid.substring(0, 12) + '...' : 'Sin vincular'}</td>
            <td class="px-6 py-4 text-sm text-gray-500">${lic.last_login ? new Date(lic.last_login).toLocaleString('es') : 'Nunca'}</td>
            <td class="px-6 py-4 text-sm">
                <button onclick="copyLicense('${lic.key}')" class="text-blue-600 hover:text-blue-800 mr-2"><i class="fas fa-copy"></i></button>
                <button onclick="revokeLicense('${lic.key}')" class="text-red-600 hover:text-red-800"><i class="fas fa-ban"></i></button>
            </td>
        </tr>
    `}).join('');
}

async function generateLicense() {
    const days = parseInt(document.getElementById('licenseDays').value);
    try {
        const res = await fetch(`${API_BASE}/api/licenses`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${authToken}` },
            body: JSON.stringify({ validDays: days })
        });
        if (res.ok) {
            const data = await res.json();
            showToast(`Licencia: ${data.key}`, 'success');
            closeModal('generateLicenseModal');
            loadLicenses();
        } else {
            showToast('Error generando licencia', 'error');
        }
    } catch (err) {
        showToast('Error', 'error');
    }
}

async function generateBulkLicenses() {
    const count = parseInt(document.getElementById('bulkCount').value);
    const days = parseInt(document.getElementById('bulkDays').value);

    showToast(`Generando ${count} licencias...`, 'info');
    
    for (let i = 0; i < count; i++) {
        try {
            await fetch(`${API_BASE}/api/licenses`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${authToken}` },
                body: JSON.stringify({ validDays: days })
            });
        } catch (err) {
            console.error('Error generating license:', err);
        }
    }

    showToast(`${count} licencias generadas`, 'success');
    closeModal('bulkLicenseModal');
    loadLicenses();
}

function copyLicense(key) {
    navigator.clipboard.writeText(key);
    showToast('Licencia copiada', 'success');
}

async function revokeLicense(key) {
    if (!confirm('¿Revocar esta licencia?')) return;
    try {
        await fetch(`${API_BASE}/api/licenses/${key}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        showToast('Licencia revocada', 'success');
        loadLicenses();
    } catch (err) {
        showToast('Error', 'error');
    }
}

// ========== MESSAGES ==========
let messages = [];

async function loadMessages() {
    try {
        const res = await fetch(`${API_BASE}/api/messages`, { headers: { 'Authorization': `Bearer ${authToken}` } });
        messages = await res.json();
        renderMessages();
    } catch (err) {
        console.error('Error loading messages:', err);
    }
}

function renderMessages() {
    const container = document.getElementById('messagesList');
    if (!messages || messages.length === 0) {
        container.innerHTML = '<p class="text-gray-500 text-center py-8">No hay mensajes</p>';
        return;
    }

    container.innerHTML = messages.map(msg => `
        <div class="bg-white rounded-xl shadow p-6">
            <div class="flex justify-between items-start mb-3">
                <div>
                    <h3 class="text-lg font-bold text-gray-800">${msg.title}</h3>
                    <span class="text-xs px-2 py-1 rounded-full ${getMessageTypeClass(msg.type)}">${msg.type}</span>
                </div>
                <button onclick="deleteMessage('${msg.id}')" class="text-red-600 hover:text-red-800"><i class="fas fa-trash"></i></button>
            </div>
            <p class="text-gray-600 mb-3">${msg.content}</p>
            <div class="text-sm text-gray-500">
                <i class="fas fa-calendar mr-1"></i>${new Date(msg.created_at).toLocaleString('es')}
                ${msg.target_hwid ? `<span class="ml-4"><i class="fas fa-user mr-1"></i>Específico</span>` : '<span class="ml-4 text-purple-600"><i class="fas fa-users mr-1"></i>Todos</span>'}
            </div>
        </div>
    `).join('');
}

function getMessageTypeClass(type) {
    const classes = { 'info': 'bg-blue-100 text-blue-800', 'warning': 'bg-orange-100 text-orange-800', 'error': 'bg-red-100 text-red-800', 'success': 'bg-green-100 text-green-800', 'update': 'bg-purple-100 text-purple-800' };
    return classes[type] || 'bg-gray-100 text-gray-800';
}

async function createMessage() {
    const title = document.getElementById('msgTitle').value;
    const content = document.getElementById('msgContent').value;
    const type = document.getElementById('msgType').value;
    const target = document.getElementById('msgTarget').value || null;

    try {
        const res = await fetch(`${API_BASE}/api/messages`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${authToken}` },
            body: JSON.stringify({ title, content, type, targetHwid: target })
        });
        if (res.ok) {
            showToast('Mensaje enviado', 'success');
            closeModal('newMessageModal');
            loadMessages();
        } else {
            showToast('Error enviando mensaje', 'error');
        }
    } catch (err) {
        showToast('Error', 'error');
    }
}

async function deleteMessage(id) {
    if (!confirm('¿Eliminar este mensaje?')) return;
    try {
        await fetch(`${API_BASE}/api/messages/${id}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        showToast('Mensaje eliminado', 'success');
        loadMessages();
    } catch (err) {
        showToast('Error', 'error');
    }
}

// ========== FEATURES ==========
let featureFlags = {};
let remoteSettings = {};

async function loadFeatures() {
    try {
        const res = await fetch(`${API_BASE}/api/config`, { headers: { 'Authorization': `Bearer ${authToken}` } });
        const config = await res.json();
        featureFlags = config.featureFlags || {};
        remoteSettings = config.settings || {};
        renderFeatures();
    } catch (err) {
        console.error('Error loading features:', err);
    }
}

function renderFeatures() {
    const flagsContainer = document.getElementById('featureFlagsList');
    const flags = Object.entries(featureFlags);

    if (flags.length === 0) {
        flagsContainer.innerHTML = '<p class="text-gray-500 text-center py-4">No hay feature flags</p>';
    } else {
        flagsContainer.innerHTML = flags.map(([key, value]) => `
            <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                <div>
                    <p class="font-medium text-gray-800">${key}</p>
                    <p class="text-xs text-gray-500">${value ? 'Activado' : 'Desactivado'}</p>
                </div>
                <div class="flex items-center space-x-2">
                    <label class="switch">
                        <input type="checkbox" ${value ? 'checked' : ''} onchange="toggleFeature('${key}', this.checked)">
                        <span class="slider"></span>
                    </label>
                    <button onclick="deleteFeature('${key}')" class="text-red-600 hover:text-red-800"><i class="fas fa-trash"></i></button>
                </div>
            </div>
        `).join('');
    }

    const settingsContainer = document.getElementById('remoteSettingsList');
    const settings = Object.entries(remoteSettings);

    if (settings.length === 0) {
        settingsContainer.innerHTML = '<p class="text-gray-500 text-center py-4">No hay settings</p>';
    } else {
        settingsContainer.innerHTML = settings.map(([key, value]) => `
            <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                <div class="flex-1">
                    <p class="font-medium text-gray-800">${key}</p>
                    <input type="text" value="${value}" onchange="updateSetting('${key}', this.value)" class="mt-1 w-full px-2 py-1 border rounded text-sm">
                </div>
                <button onclick="deleteSetting('${key}')" class="ml-2 text-red-600 hover:text-red-800"><i class="fas fa-trash"></i></button>
            </div>
        `).join('');
    }
}

async function toggleFeature(key, enabled) {
    featureFlags[key] = enabled;
    await saveConfig();
}

async function addFeatureFlag() {
    const key = prompt('Nombre del feature flag:');
    if (!key) return;
    featureFlags[key] = false;
    await saveConfig();
    renderFeatures();
}

async function deleteFeature(key) {
    if (!confirm(`¿Eliminar "${key}"?`)) return;
    delete featureFlags[key];
    await saveConfig();
    renderFeatures();
}

async function addRemoteSetting() {
    const key = prompt('Nombre del setting:');
    if (!key) return;
    remoteSettings[key] = '';
    await saveConfig();
    renderFeatures();
}

async function updateSetting(key, value) {
    remoteSettings[key] = value;
    await saveConfig();
}

async function deleteSetting(key) {
    if (!confirm(`¿Eliminar "${key}"?`)) return;
    delete remoteSettings[key];
    await saveConfig();
    renderFeatures();
}

async function saveConfig() {
    try {
        await fetch(`${API_BASE}/api/config`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${authToken}` },
            body: JSON.stringify({ featureFlags, settings: remoteSettings })
        });
        showToast('Config actualizada', 'success');
    } catch (err) {
        showToast('Error', 'error');
    }
}

// ========== BANNERS ==========
let banners = [];

async function loadBanners() {
    try {
        const res = await fetch(`${API_BASE}/api/banners`, { headers: { 'Authorization': `Bearer ${authToken}` } });
        if (res.ok) {
            banners = await res.json();
            renderBanners();
        }
    } catch (err) {
        console.error('Error loading banners:', err);
    }
}

function renderBanners() {
    const container = document.getElementById('bannersList');
    if (!banners || banners.length === 0) {
        container.innerHTML = '<p class="text-gray-500 text-center py-8">No hay banners</p>';
        return;
    }

    container.innerHTML = banners.map(banner => `
        <div class="bg-white rounded-xl shadow p-6">
            <div class="flex justify-between items-start">
                <div class="flex-1">
                    <div class="flex items-center space-x-2 mb-2">
                        <div class="w-4 h-4 rounded" style="background: ${banner.color}"></div>
                        <h3 class="text-lg font-bold">${banner.title}</h3>
                    </div>
                    <p class="text-gray-600">${banner.text}</p>
                    <p class="text-sm text-gray-500 mt-2">Posición: ${banner.position} ${banner.action_url ? `| Acción: ${banner.action_url}` : ''}</p>
                </div>
                <button onclick="deleteBanner('${banner.id}')" class="text-red-600 hover:text-red-800"><i class="fas fa-trash"></i></button>
            </div>
        </div>
    `).join('');
}

async function createBanner() {
    const banner = {
        title: document.getElementById('bannerTitle').value,
        text: document.getElementById('bannerText').value,
        color: document.getElementById('bannerColor').value,
        position: document.getElementById('bannerPosition').value,
        action_url: document.getElementById('bannerAction').value || null
    };

    try {
        const res = await fetch(`${API_BASE}/api/banners`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${authToken}` },
            body: JSON.stringify(banner)
        });
        if (res.ok) {
            showToast('Banner creado', 'success');
            closeModal('newBannerModal');
            loadBanners();
        }
    } catch (err) {
        showToast('Error', 'error');
    }
}

async function deleteBanner(id) {
    if (!confirm('¿Eliminar banner?')) return;
    try {
        await fetch(`${API_BASE}/api/banners/${id}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        showToast('Banner eliminado', 'success');
        loadBanners();
    } catch (err) {
        showToast('Error', 'error');
    }
}

// ========== VERSIONS ==========
let versions = [];

async function loadVersions() {
    try {
        const res = await fetch(`${API_BASE}/api/versions`, { headers: { 'Authorization': `Bearer ${authToken}` } });
        if (res.ok) {
            versions = await res.json();
            renderVersions();
        }
    } catch (err) {
        console.error('Error loading versions:', err);
    }
}

function renderVersions() {
    const container = document.getElementById('versionsList');
    if (!versions || versions.length === 0) {
        container.innerHTML = '<p class="text-gray-500 text-center py-8">No hay versiones</p>';
        return;
    }

    container.innerHTML = versions.map(version => `
        <div class="bg-white rounded-xl shadow p-6">
            <div class="flex justify-between items-start">
                <div>
                    <div class="flex items-center space-x-2 mb-2">
                        <h3 class="text-xl font-bold">v${version.version}</h3>
                        ${version.force_update ? '<span class="px-2 py-1 bg-red-100 text-red-800 text-xs rounded-full">FORZADA</span>' : ''}
                    </div>
                    <p class="text-sm text-gray-500">iOS ${version.min_ios} - ${version.max_ios}</p>
                    <p class="text-gray-600 mt-2">${version.changelog || 'Sin changelog'}</p>
                    ${version.download_url ? `<a href="${version.download_url}" class="text-purple-600 hover:text-purple-800 text-sm mt-2 inline-block"><i class="fas fa-download mr-1"></i>Descargar</a>` : ''}
                </div>
                <button onclick="deleteVersion('${version.id}')" class="text-red-600 hover:text-red-800"><i class="fas fa-trash"></i></button>
            </div>
        </div>
    `).join('');
}

async function createVersion() {
    const version = {
        version: document.getElementById('versionNumber').value,
        min_ios: document.getElementById('versionMinIOS').value,
        max_ios: document.getElementById('versionMaxIOS').value,
        changelog: document.getElementById('versionChangelog').value,
        download_url: document.getElementById('versionDownloadUrl').value,
        force_update: document.getElementById('versionForceUpdate').checked
    };

    try {
        const res = await fetch(`${API_BASE}/api/versions`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${authToken}` },
            body: JSON.stringify(version)
        });
        if (res.ok) {
            showToast('Versión creada', 'success');
            closeModal('newVersionModal');
            loadVersions();
        }
    } catch (err) {
        showToast('Error', 'error');
    }
}

async function deleteVersion(id) {
    if (!confirm('¿Eliminar versión?')) return;
    try {
        await fetch(`${API_BASE}/api/versions/${id}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        showToast('Versión eliminada', 'success');
        loadVersions();
    } catch (err) {
        showToast('Error', 'error');
    }
}

// ========== LOGS ==========
let logs = [];

async function loadLogs() {
    try {
        const res = await fetch(`${API_BASE}/api/logs`, { headers: { 'Authorization': `Bearer ${authToken}` } });
        if (res.ok) {
            logs = await res.json();
            renderLogs();
        }
    } catch (err) {
        console.error('Error loading logs:', err);
    }
}

function renderLogs() {
    const container = document.getElementById('logsContainer');
    const filter = document.getElementById('logFilter')?.value || 'all';
    
    const filtered = filter === 'all' ? logs : logs.filter(l => l.level === filter);

    if (filtered.length === 0) {
        container.innerHTML = '<p class="text-gray-500 text-center py-4">No hay logs</p>';
        return;
    }

    container.innerHTML = filtered.slice(-100).map(log => `
        <div class="log-entry text-${getLogLevelColor(log.level)}">
            [${new Date(log.timestamp).toLocaleString('es')}] [${log.level.toUpperCase()}] ${log.message}
        </div>
    `).join('');
}

function getLogLevelColor(level) {
    const colors = { 'error': 'red-400', 'warning': 'yellow-400', 'info': 'blue-400', 'debug': 'gray-400' };
    return colors[level] || 'gray-400';
}

async function clearLogs() {
    if (!confirm('¿Limpiar todos los logs?')) return;
    try {
        await fetch(`${API_BASE}/api/logs`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        showToast('Logs limpiados', 'success');
        loadLogs();
    } catch (err) {
        showToast('Error', 'error');
    }
}

// ========== SECURITY ==========
let blockedIPs = [];
let apiKeys = [];

async function loadSecurity() {
    try {
        const res = await fetch(`${API_BASE}/api/security`, { headers: { 'Authorization': `Bearer ${authToken}` } });
        if (res.ok) {
            const data = await res.json();
            blockedIPs = data.blockedIPs || [];
            apiKeys = data.apiKeys || [];
            renderSecurity();
        }
    } catch (err) {
        console.error('Error loading security:', err);
    }
}

function renderSecurity() {
    const ipsContainer = document.getElementById('blockedIPs');
    ipsContainer.innerHTML = blockedIPs.map(ip => `
        <div class="flex items-center justify-between p-2 bg-red-50 rounded">
            <span class="font-mono text-sm">${ip}</span>
            <button onclick="unblockIP('${ip}')" class="text-red-600 hover:text-red-800"><i class="fas fa-times"></i></button>
        </div>
    `).join('') || '<p class="text-gray-500 text-sm">No hay IPs bloqueadas</p>';

    const keysContainer = document.getElementById('apiKeysList');
    keysContainer.innerHTML = apiKeys.map(key => `
        <div class="flex items-center justify-between p-2 bg-gray-50 rounded">
            <span class="font-mono text-xs">${key.key.substring(0, 20)}...</span>
            <button onclick="revokeAPIKey('${key.id}')" class="text-red-600 hover:text-red-800"><i class="fas fa-trash"></i></button>
        </div>
    `).join('') || '<p class="text-gray-500 text-sm">No hay API keys</p>';
}

async function blockIP() {
    const ip = document.getElementById('newBlockedIP').value;
    if (!ip) return;

    try {
        await fetch(`${API_BASE}/api/security/block-ip`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${authToken}` },
            body: JSON.stringify({ ip })
        });
        showToast('IP bloqueada', 'success');
        document.getElementById('newBlockedIP').value = '';
        loadSecurity();
    } catch (err) {
        showToast('Error', 'error');
    }
}

async function unblockIP(ip) {
    try {
        await fetch(`${API_BASE}/api/security/unblock-ip`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${authToken}` },
            body: JSON.stringify({ ip })
        });
        showToast('IP desbloqueada', 'success');
        loadSecurity();
    } catch (err) {
        showToast('Error', 'error');
    }
}

async function saveRateLimit() {
    const rateLimit = parseInt(document.getElementById('rateLimit').value);
    const banTime = parseInt(document.getElementById('banTime').value);

    try {
        await fetch(`${API_BASE}/api/security/rate-limit`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${authToken}` },
            body: JSON.stringify({ rateLimit, banTime })
        });
        showToast('Rate limit guardado', 'success');
    } catch (err) {
        showToast('Error', 'error');
    }
}

async function generateAPIKey() {
    try {
        const res = await fetch(`${API_BASE}/api/security/api-keys`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        if (res.ok) {
            const data = await res.json();
            showToast(`API Key: ${data.key}`, 'success');
            loadSecurity();
        }
    } catch (err) {
        showToast('Error', 'error');
    }
}

async function revokeAPIKey(id) {
    if (!confirm('¿Revocar esta API key?')) return;
    try {
        await fetch(`${API_BASE}/api/security/api-keys/${id}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        showToast('API key revocada', 'success');
        loadSecurity();
    } catch (err) {
        showToast('Error', 'error');
    }
}

// ========== WEBHOOKS ==========
let webhooks = [];

async function loadWebhooks() {
    try {
        const res = await fetch(`${API_BASE}/api/webhooks`, { headers: { 'Authorization': `Bearer ${authToken}` } });
        if (res.ok) {
            webhooks = await res.json();
            renderWebhooks();
        }
    } catch (err) {
        console.error('Error loading webhooks:', err);
    }
}

function renderWebhooks() {
    const container = document.getElementById('webhooksList');
    if (!webhooks || webhooks.length === 0) {
        container.innerHTML = '<p class="text-gray-500 text-center py-8">No hay webhooks</p>';
        return;
    }

    container.innerHTML = webhooks.map(webhook => `
        <div class="bg-white rounded-xl shadow p-6">
            <div class="flex justify-between items-start">
                <div>
                    <h3 class="text-lg font-bold">${webhook.name}</h3>
                    <p class="text-sm text-gray-500 font-mono">${webhook.url}</p>
                    <div class="flex space-x-2 mt-2">
                        ${(webhook.events || []).map(e => `<span class="px-2 py-1 bg-purple-100 text-purple-800 text-xs rounded-full">${e}</span>`).join('')}
                    </div>
                </div>
                <button onclick="deleteWebhook('${webhook.id}')" class="text-red-600 hover:text-red-800"><i class="fas fa-trash"></i></button>
            </div>
        </div>
    `).join('');
}

async function createWebhook() {
    const events = Array.from(document.querySelectorAll('.webhook-event:checked')).map(cb => cb.value);
    
    const webhook = {
        name: document.getElementById('webhookName').value,
        url: document.getElementById('webhookUrl').value,
        events
    };

    try {
        const res = await fetch(`${API_BASE}/api/webhooks`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${authToken}` },
            body: JSON.stringify(webhook)
        });
        if (res.ok) {
            showToast('Webhook creado', 'success');
            closeModal('newWebhookModal');
            loadWebhooks();
        }
    } catch (err) {
        showToast('Error', 'error');
    }
}

async function deleteWebhook(id) {
    if (!confirm('¿Eliminar webhook?')) return;
    try {
        await fetch(`${API_BASE}/api/webhooks/${id}`, {
            method: 'DELETE',
            headers: { 'Authorization': `Bearer ${authToken}` }
        });
        showToast('Webhook eliminado', 'success');
        loadWebhooks();
    } catch (err) {
        showToast('Error', 'error');
    }
}

// ========== MAINTENANCE ==========
async function loadMaintenance() {
    try {
        const res = await fetch(`${API_BASE}/api/maintenance`, { headers: { 'Authorization': `Bearer ${authToken}` } });
        if (res.ok) {
            const data = await res.json();
            document.getElementById('maintenanceToggle').checked = data.enabled || false;
            document.getElementById('maintenanceMessage').value = data.message || '';
            document.getElementById('maintenanceWhitelist').value = (data.whitelist || []).join(', ');
            document.getElementById('maintenanceConfig').classList.toggle('hidden', !data.enabled);
        }
    } catch (err) {
        console.error('Error loading maintenance:', err);
    }
}

async function toggleMaintenance() {
    const enabled = document.getElementById('maintenanceToggle').checked;
    document.getElementById('maintenanceConfig').classList.toggle('hidden', !enabled);
    await saveMaintenanceConfig();
}

async function saveMaintenanceConfig() {
    const enabled = document.getElementById('maintenanceToggle').checked;
    const message = document.getElementById('maintenanceMessage').value;
    const whitelist = document.getElementById('maintenanceWhitelist').value.split(',').map(s => s.trim()).filter(s => s);

    try {
        await fetch(`${API_BASE}/api/maintenance`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${authToken}` },
            body: JSON.stringify({ enabled, message, whitelist })
        });
        showToast('Config guardada', 'success');
    } catch (err) {
        showToast('Error', 'error');
    }
}

// ========== SETTINGS ==========
function loadSettings() {
    document.getElementById('settingsWorkerUrl').value = localStorage.getItem('workerUrl') || API_BASE;
    document.getElementById('settingsGithubRepo').value = localStorage.getItem('githubRepo') || 'loboangel39-svg/VINI-IPA';
    document.getElementById('settingsGithubToken').value = localStorage.getItem('githubToken') || '';
}

function saveSettings() {
    localStorage.setItem('workerUrl', document.getElementById('settingsWorkerUrl').value);
    localStorage.setItem('githubRepo', document.getElementById('settingsGithubRepo').value);
    localStorage.setItem('githubToken', document.getElementById('settingsGithubToken').value);
    showToast('Configuración guardada', 'success');
}

// ========== TOAST ==========
function showToast(message, type = 'info') {
    const container = document.getElementById('toastContainer');
    const colors = { success: 'bg-green-500', error: 'bg-red-500', info: 'bg-blue-500' };
    const icons = { success: 'fa-check-circle', error: 'fa-exclamation-circle', info: 'fa-info-circle' };
    
    const toast = document.createElement('div');
    toast.className = `toast ${colors[type]} text-white px-6 py-3 rounded-lg shadow-lg flex items-center space-x-3`;
    toast.innerHTML = `<i class="fas ${icons[type]}"></i><span>${message}</span>`;
    container.appendChild(toast);
    
    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transition = 'opacity 0.3s';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

// ========== NOTIFICATIONS ==========
function toggleNotifications() {
    showToast('Notificaciones - próximamente', 'info');
}
