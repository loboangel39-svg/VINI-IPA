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
    private let workerURL = "https://vini-patch-worker.loboangel39.workers.dev"
    
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
        await journalLogApply(
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

    // MARK: - Journal (inline, no requiere archivo separado)

    /// Registra en el journal del servidor que un patch fue aplicado.
    private func journalLogApply(patchId: String, targetFile: String, originalHash: String, patchedHash: String) async {
        guard let token = UserDefaults.standard.string(forKey: "remotePatch.authToken") else { return }
        guard let url = URL(string: "\(workerURL)/api/app/journal/apply") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "patchId": patchId,
            "targetFile": targetFile,
            "originalHash": originalHash,
            "patchedHash": patchedHash,
        ]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                log("journal: logged apply for \(patchId)")
            }
        } catch {
            log("journal: failed to log apply — \(error.localizedDescription)")
        }
    }

    /// Registra en el journal del servidor que un patch fue restaurado.
    /// Retorna el backup_r2_key si el servidor lo tiene.
    func journalLogRestore(patchId: String) async -> String? {
        guard let token = UserDefaults.standard.string(forKey: "remotePatch.authToken") else { return nil }
        guard let url = URL(string: "\(workerURL)/api/app/journal/restore") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body = ["patchId": patchId]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }

            struct RestoreResponse: Codable {
                let success: Bool
                let journal: JournalRestoreInfo?
            }
            struct JournalRestoreInfo: Codable {
                let backupR2Key: String
                let targetFile: String
                let originalHash: String

                enum CodingKeys: String, CodingKey {
                    case backupR2Key = "backupR2Key"
                    case targetFile = "targetFile"
                    case originalHash = "originalHash"
                }
            }

            let resp = try JSONDecoder().decode(RestoreResponse.self, from: data)
            if resp.success {
                log("journal: logged restore for \(patchId)")
                return resp.journal?.backupR2Key
            }
        } catch {
            log("journal: failed to log restore — \(error.localizedDescription)")
        }
        return nil
    }
}

// MARK: - Notification para recargar patches
extension Notification.Name {
    static let patchesDidChange = Notification.Name("patchesDidChange")
}
