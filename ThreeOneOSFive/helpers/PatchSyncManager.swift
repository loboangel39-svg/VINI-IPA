import Foundation
import SwiftUI
import CommonCrypto

// MARK: - Patch Sync Manager
// Descarga patches remotos y los guarda en la misma ruta que usa PatchProjectLibrary
// para que aparezcan automáticamente en la pestaña de Patches existente.
// v3: Registra cada descarga en el PatchJournal para que Restore Original no dé error.

final class PatchSyncManager: ObservableObject {
    static let shared = PatchSyncManager()
    
    @Published var availablePatches: [RemotePatchInfo] = []
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var downloadProgress: String?
    
    private let service = RemotePatchService.shared
    private let storageKey = "remotePatch.downloadedIds"
    
    // Ruta donde PatchProjectLibrary busca los patches
    private var patchesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("PatchProjects", isDirectory: true)
    }
    
    // IDs de patches que ya se descargaron
    private var downloadedIds: Set<String> {
        get {
            guard let data = UserDefaults.standard.data(forKey: storageKey),
                  let ids = try? JSONDecoder().decode(Set<String>.self, from: data) else {
                return []
            }
            return ids
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: storageKey)
            }
        }
    }
    
    init() {}
    
    // MARK: - Sincronizar patches remotos
    func syncPatches() async {
        guard !isSyncing else { return }
        isSyncing = true
        downloadProgress = nil
        
        do {
            // 1. Obtener lista de patches disponibles desde el Worker
            let patches = try await service.fetchAvailablePatches()
            
            await MainActor.run {
                self.availablePatches = patches
                self.lastSyncDate = Date()
            }
            
            // 2. Descargar patches nuevos automáticamente (con reintento)
            for patch in patches {
                if !downloadedIds.contains(patch.id) {
                    var lastError: Error?
                    for attempt in 1...3 {
                        do {
                            await MainActor.run { self.downloadProgress = "Descargando \(patch.name)..." }
                            try await downloadPatch(patch)
                            lastError = nil
                            break
                        } catch {
                            lastError = error
                            if attempt < 3 {
                                log("Intento \(attempt) fallido para \(patch.name), reintentando...")
                                try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                            }
                        }
                    }
                    if let error = lastError {
                        log("Error descargando \(patch.name): \(error)")
                    }
                }
            }
            
            await MainActor.run {
                self.downloadProgress = nil
                self.isSyncing = false
            }
            
            // Notificar que hay cambios
            notifyPatchesChanged()
            
            log("remote: sync complete — \(patches.count) patches available")
        } catch {
            await MainActor.run { self.isSyncing = false }
            log("remote: sync failed — \(error.localizedDescription)")
        }
    }
    
    // MARK: - Descargar patch y guardarlo en PatchProjects/
    func downloadPatch(_ patch: RemotePatchInfo) async throws {
        let (data, filename) = try await service.downloadPatch(patchId: patch.id)
        
        // Asegurar que el directorio existe
        try FileManager.default.createDirectory(at: patchesDirectory, withIntermediateDirectories: true)
        
        // Guardar en la misma ruta que usa PatchProjectLibrary
        let fileURL = patchesDirectory.appendingPathComponent(filename)

        // === JOURNAL: Calcular hash del archivo existente antes de sobrescribir ===
        var originalHash = ""
        if FileManager.default.fileExists(atPath: fileURL.path) {
            originalHash = sha256OfFile(at: fileURL)
            // Guardar backup local por seguridad
            let backupURL = patchesDirectory.appendingPathComponent("\(filename).original")
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
        }
        
        // Escribir el patch
        try data.write(to: fileURL)

        // === JOURNAL: Calcular hash del archivo parchado y registrar ===
        let patchedHash = sha256OfFile(at: fileURL)
        try? await PatchJournalService.shared.logApply(
            patchId: patch.id,
            targetFile: filename,
            originalHash: originalHash,
            patchedHash: patchedHash
        )
        
        // Si el patch tiene contraseña, decodificarlo y guardar el contentKey en Keychain
        if let password = patch.password, !password.isEmpty {
            do {
                let summary = try PatchPackageCodec.inspect(data)
                let decoded = try PatchPackageCodec.decode(data, password: password)
                try PatchKeyStore.store(decoded.contentKey, for: summary)
                log("remote: \(filename) decodificado con contraseña y contentKey guardado")
            } catch {
                log("remote: ERROR decodificando \(filename) con contraseña: \(error)")
            }
        }
        
        // Registrar como descargado
        var ids = downloadedIds
        ids.insert(patch.id)
        downloadedIds = ids
        
        log("remote: saved \(filename) to PatchProjects/")
    }
    
    // MARK: - Verificar si ya está descargado
    func isDownloaded(_ patchId: String) -> Bool {
        return downloadedIds.contains(patchId)
    }
    
    // MARK: - Forzar recarga de la lista de patches
    func notifyPatchesChanged() {
        NotificationCenter.default.post(name: .patchesDidChange, object: nil)
    }

    // MARK: - SHA-256 Helper (para el journal)
    private func sha256OfFile(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Notification para recargar patches
extension Notification.Name {
    static let patchesDidChange = Notification.Name("patchesDidChange")
}
