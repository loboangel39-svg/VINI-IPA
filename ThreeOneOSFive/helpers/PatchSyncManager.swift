import Foundation
import SwiftUI
import CommonCrypto

// MARK: - Patch Sync Manager (v3)
// Descarga patches remotos y los guarda en la misma ruta que usa PatchProjectLibrary
// para que aparezcan automáticamente en la pestaña de Patches existente.
// v3: Integración con PatchJournal para "Restore Original" sin errores.
//     Descarga con reintentos y resume automático.

final class PatchSyncManager: ObservableObject {
    static let shared = PatchSyncManager()

    @Published var availablePatches: [RemotePatchInfo] = []
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var downloadProgress: String?
    @Published var isRestoring = false
    @Published var restoreError: String?

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

            // 2. Descargar patches nuevos automáticamente (con reintentos)
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

        let fileURL = patchesDirectory.appendingPathComponent(filename)

        // Si ya existe un archivo, guardar backup para restore original
        var originalHash = ""
        if FileManager.default.fileExists(atPath: fileURL.path) {
            originalHash = sha256OfFile(at: fileURL)
            let backupURL = patchesDirectory.appendingPathComponent("\(filename).original")
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
            log("backed up original: \(backupURL.lastPathComponent)")
        }

        // Guardar el patch en la misma ruta que usa PatchProjectLibrary
        try data.write(to: fileURL)

        // Calcular hash del archivo parchado
        let patchedHash = sha256OfFile(at: fileURL)

        // Registrar en el journal del servidor
        try? await PatchJournalService.shared.logApply(
            patchId: patch.id,
            targetFile: filename,
            originalHash: originalHash,
            patchedHash: patchedHash,
            metadata: [
                "version": patch.version,
                "size": data.count,
                "filename": filename,
            ]
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

    // MARK: - Restore Original

    /// Restaura el archivo original de un patch aplicado.
    /// Consulta el journal para saber qué revertir y dónde está el backup.
    func restoreOriginal(patch: RemotePatchInfo) async {
        guard !isRestoring else { return }
        await MainActor.run {
            self.isRestoring = true
            self.restoreError = nil
        }

        log("restoring original for patch \(patch.id)")

        do {
            // 1. Registrar la restauración en el journal del servidor
            guard let journalEntry = try await PatchJournalService.shared.logRestore(patchId: patch.id) else {
                throw PatchSyncRestoreError.noJournalEntry
            }

            // 2. Buscar el archivo y el backup
            let targetFile = journalEntry.targetFile.isEmpty ? "\(patch.name).3105" : journalEntry.targetFile
            let fileURL = patchesDirectory.appendingPathComponent(targetFile)
            let backupURL = patchesDirectory.appendingPathComponent("\(targetFile).original")

            // 3. Restaurar desde backup local
            if FileManager.default.fileExists(atPath: backupURL.path) {
                // Eliminar el archivo parchado
                try? FileManager.default.removeItem(at: fileURL)
                // Mover el backup al lugar original
                try FileManager.default.moveItem(at: backupURL, to: fileURL)
                log("restored from local backup: \(backupURL.lastPathComponent)")
            } else if !journalEntry.backupR2Key.isEmpty {
                // No hay backup local, intentar descargar desde R2
                let (data, _) = try await service.downloadPatch(patchId: journalEntry.backupR2Key)
                try? FileManager.default.removeItem(at: fileURL)
                try data.write(to: fileURL)
                log("restored from R2 backup: \(journalEntry.backupR2Key)")
            } else {
                // No hay backup en ningún lado — eliminar el archivo parchado
                try? FileManager.default.removeItem(at: fileURL)
                log("no backup available, removed patched file")
            }

            // 4. Limpiar tracking de descarga
            var ids = downloadedIds
            ids.remove(patch.id)
            downloadedIds = ids

            await MainActor.run {
                self.isRestoring = false
            }

            // Notificar que hay cambios
            notifyPatchesChanged()
            log("restore complete for patch \(patch.id)")

        } catch {
            await MainActor.run {
                self.restoreError = error.localizedDescription
                self.isRestoring = false
            }
            log("restore failed: \(error.localizedDescription)")
        }
    }

    /// Verifica si un patch puede ser restaurado a su estado original.
    func canRestoreOriginal(patchId: String) async -> Bool {
        return await PatchJournalService.shared.canRestore(patchId: patchId)
    }

    // MARK: - Verificar si ya está descargado

    func isDownloaded(_ patchId: String) -> Bool {
        return downloadedIds.contains(patchId)
    }

    // MARK: - Eliminar patch local

    func deleteLocalPatch(patchId: String, filename: String) {
        let fileURL = patchesDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: patchesDirectory.appendingPathComponent("\(filename).original"))

        var ids = downloadedIds
        ids.remove(patchId)
        downloadedIds = ids
        log("deleted local patch \(filename)")
        notifyPatchesChanged()
    }

    // MARK: - Forzar recarga de la lista de patches

    func notifyPatchesChanged() {
        NotificationCenter.default.post(name: .patchesDidChange, object: nil)
    }

    // MARK: - SHA-256 Helper

    private func sha256OfFile(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func log(_ message: String) {
        print("[PatchSync] \(message)")
    }
}

// MARK: - Notification para recargar patches

extension Notification.Name {
    static let patchesDidChange = Notification.Name("patchesDidChange")
}

// MARK: - Restore Errors

enum PatchSyncRestoreError: LocalizedError {
    case noJournalEntry
    case noBackupFound
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .noJournalEntry: return "No se encontró registro de aplicación del patch."
        case .noBackupFound: return "No se encontró backup del archivo original."
        case .restoreFailed(let msg): return "Restauración fallida: \(msg)"
        }
    }
}
