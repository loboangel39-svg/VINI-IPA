import Foundation

// MARK: - Patch Manager
// Orquestador principal de patches remotos.
// Coordina: RemotePatchService (API) → PatchDownloadService (descarga) → PatchStorage (almacenamiento)
//
// Responsabilidades:
// 1. Consultar patches disponibles desde el servidor
// 2. Determinar si necesita descarga (nuevo o actualización)
// 3. Ejecutar descarga robusta (temp → verificar → reemplazar)
// 4. Mantener estado local de patches
//
// REGLA FUNDAMENTAL: Una descarga anterior NUNCA bloquea una nueva descarga.

final class PatchManager: ObservableObject {
    static let shared = PatchManager()
    
    @Published var availablePatches: [RemotePatchInfo] = []
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var downloadProgress: [String: String] = [:] // patchId → status message
    @Published var downloadingPatchIds: Set<String> = []
    
    private let remoteService = RemotePatchService.shared
    private let downloadService = PatchDownloadService.shared
    private let storage = PatchStorage.shared
    
    init() {}
    
    // MARK: - Sync
    
    /// Sincroniza la lista de patches desde el servidor y descarga los que faltan o están desactualizados.
    func syncPatches() async {
        guard !isSyncing else { return }
        isSyncing = true

        do {
            // 1. Obtener lista de patches disponibles
            let patches = try await remoteService.fetchAvailablePatches()

            await MainActor.run {
                self.availablePatches = patches
                self.lastSyncDate = Date()
            }

            // 2. Limpiar patches locales que ya no están asignados
            await cleanupUnassignedPatches(serverPatches: patches)

            // 3. Para cada patch, verificar si necesita descarga
            for patch in patches {
                print("[PatchManager] Checking patch: \(patch.name) (id: \(patch.id))")
                let exists = storage.patchExists(patchId: patch.id)
                print("[PatchManager] Local exists: \(exists)")
                let needsDownload = shouldDownload(patch)
                print("[PatchManager] Needs download: \(needsDownload)")
                if needsDownload {
                    print("[PatchManager] Starting download for: \(patch.name)")
                    await downloadIfNeeded(patch)
                }
            }

            // 4. Limpiar archivos temporales
            downloadService.cleanup()

            await MainActor.run {
                self.isSyncing = false
            }

            // 5. Notificar cambios
            NotificationCenter.default.post(name: .patchesDidChange, object: nil)

            print("[PatchManager] Sync complete — \(patches.count) patches available")
        } catch {
            await MainActor.run { self.isSyncing = false }
            print("[PatchManager] Sync failed: \(error.localizedDescription)")
        }
    }

    /// Elimina patches locales que ya no están asignados en el servidor
    private func cleanupUnassignedPatches(serverPatches: [RemotePatchInfo]) async {
        let localPatchIds = storage.localPatchIds()
        let serverPatchIds = Set(serverPatches.map { $0.id })

        for localId in localPatchIds {
            if !serverPatchIds.contains(localId) {
                print("[PatchManager] Removing unassigned patch: \(localId)")
                storage.deletePatch(patchId: localId)

                // También eliminar de la ubicación local (Application Support)
                await removeLocalPatchFile(patchId: localId)
            }
        }
    }

    /// Elimina el archivo del patch de la ubicación local (Application Support/PatchProjects)
    private func removeLocalPatchFile(patchId: String) async {
        await Task.detached {
            do {
                let appSupport = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false
                )
                let patchProjectsDir = appSupport.appendingPathComponent("PatchProjects", isDirectory: true)

                if FileManager.default.fileExists(atPath: patchProjectsDir.path) {
                    let files = try FileManager.default.contentsOfDirectory(at: patchProjectsDir, includingPropertiesForKeys: nil)
                    for file in files {
                        // Buscar archivos que contengan el patchId en el nombre
                        if file.lastPathComponent.contains(patchId) {
                            try FileManager.default.removeItem(at: file)
                            print("[PatchManager] Removed local patch file: \(file.lastPathComponent)")
                        }
                    }
                }
            } catch {
                print("[PatchManager] Error removing local patch file: \(error.localizedDescription)")
            }
        }.value
    }

    /// Copia el patch descargado a la ubicación local (Application Support/PatchProjects)
    /// para que aparezca en la pestaña de Patches
    private func copyToLocalPatchesDirectory(patchId: String, patchName: String) throws {
        guard let patchData = storage.readPatchData(patchId: patchId) else {
            throw NSError(domain: "PatchManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Patch data not found"])
        }

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let patchProjectsDir = appSupport.appendingPathComponent("PatchProjects", isDirectory: true)

        // Crear directorio si no existe
        try FileManager.default.createDirectory(at: patchProjectsDir, withIntermediateDirectories: true)

        // Crear nombre de archivo seguro
        let safeName = patchName.replacingOccurrences(of: "[^a-zA-Z0-9-_]", with: "-", options: .regularExpression)
        let fileName = "\(safeName)-\(patchId.prefix(8)).3105"
        let destinationURL = patchProjectsDir.appendingPathComponent(fileName)

        // Escribir archivo
        try patchData.write(to: destinationURL, options: .atomic)
        print("[PatchManager] Copied patch to local directory: \(fileName)")
    }
    
    // MARK: - Download Decision
    
    /// Determina si un patch necesita descargarse.
    /// Se descarga si:
    /// - No existe localmente, O
    /// - La versión del servidor es mayor que la local
    /// NO se bloquea por haberlo descargado antes.
    private func shouldDownload(_ patch: RemotePatchInfo) -> Bool {
        // Si no existe localmente → descargar
        guard storage.patchExists(patchId: patch.id) else {
            return true
        }
        
        // Si existe, comparar versiones
        if let localVersion = storage.localVersion(patchId: patch.id) {
            return compareVersions(patch.version, localVersion) > 0
        }
        
        // Sin metadata local → descargar
        return true
    }
    
    /// Compara versiones semver. Retorna > 0 si a > b, < 0 si a < b, 0 si iguales.
    private func compareVersions(_ a: String, _ b: String) -> Int {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        
        let maxLen = max(partsA.count, partsB.count)
        for i in 0..<maxLen {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va != vb { return va > vb ? 1 : -1 }
        }
        return 0
    }
    
    // MARK: - Download
    
    /// Descarga un patch específico de forma robusta.
    func downloadIfNeeded(_ patch: RemotePatchInfo) async {
        // No descargar dos veces el mismo patch simultáneamente
        guard !downloadingPatchIds.contains(patch.id) else { return }
        
        await MainActor.run {
            self.downloadingPatchIds.insert(patch.id)
            self.downloadProgress[patch.id] = "Downloading..."
        }
        
        var lastError: Error?
        
        for attempt in 1...3 {
            do {
                // 1. Descargar a archivo temporal
                let result = try await downloadService.downloadPatch(patchId: patch.id)
                
                await MainActor.run {
                    self.downloadProgress[patch.id] = "Verifying..."
                }
                
                // 2. Guardar de forma atómica (temp → verificar → reemplazar)
                try storage.savePatch(
                    patchId: patch.id,
                    tempURL: result.tempURL,
                    version: result.version,
                    expectedSize: result.fileSize
                )
                
                // 3. Copiar a la ubicación de patches locales para que aparezca en la UI
                try copyToLocalPatchesDirectory(patchId: patch.id, patchName: patch.name)
                
                await MainActor.run {
                    self.downloadProgress[patch.id] = "Complete"
                    self.downloadingPatchIds.remove(patch.id)
                }
                
                print("[PatchManager] Patch \(patch.name) saved successfully (v\(result.version))")
                return
                
            } catch {
                lastError = error
                print("[PatchManager] Download attempt \(attempt) failed for \(patch.name): \(error.localizedDescription)")
                
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                }
            }
        }
        
        // Todas las intentos fallaron
        await MainActor.run {
            self.downloadProgress[patch.id] = "Failed: \(lastError?.localizedDescription ?? "Unknown error")"
            self.downloadingPatchIds.remove(patch.id)
        }
    }
    
    /// Fuerza la re-descarga de un patch (ignora versión local).
    /// Este es el método clave para resolver el problema de "segunda descarga falla".
    func forceRedownload(_ patch: RemotePatchInfo) async {
        print("[PatchManager] Force re-download: \(patch.name)")
        await downloadIfNeeded(patch)
    }
    
    // MARK: - Local State
    
    /// Verifica si un patch está descargado localmente
    func isDownloaded(_ patchId: String) -> Bool {
        return storage.patchExists(patchId: patchId)
    }
    
    /// Obtiene la versión local de un patch
    func localVersion(_ patchId: String) -> String? {
        return storage.localVersion(patchId: patchId)
    }
    
    /// Verifica si hay actualización disponible para un patch
    func hasUpdate(_ patch: RemotePatchInfo) -> Bool {
        guard let localVer = storage.localVersion(patchId: patch.id) else { return false }
        return compareVersions(patch.version, localVer) > 0
    }
    
    /// Obtiene los datos de un patch almacenado
    func patchData(_ patchId: String) -> Data? {
        return storage.readPatchData(patchId: patchId)
    }
    
    /// Elimina un patch local
    func deleteLocalPatch(_ patchId: String) {
        storage.deletePatch(patchId: patchId)
        NotificationCenter.default.post(name: .patchesDidChange, object: nil)
    }
    
    /// Lista todos los IDs de patches almacenados localmente
    func localPatchIds() -> [String] {
        return storage.localPatchIds()
    }
    
    /// Notifica que los patches cambiaron
    func notifyPatchesChanged() {
        NotificationCenter.default.post(name: .patchesDidChange, object: nil)
    }
}
