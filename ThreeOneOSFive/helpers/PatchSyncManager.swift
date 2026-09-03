import Foundation
import SwiftUI

final class PatchSyncManager: ObservableObject {
    static let shared = PatchSyncManager()

    @Published var availablePatches: [RemotePatchInfo] = []
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var downloadProgress: String?

    private let service = RemotePatchService.shared
    private let storageKey = "remotePatch.downloadedIds"

    private var patchesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("PatchProjects", isDirectory: true)
    }

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

    // Descarga patches y notifica cuando termina
    func syncPatches() async {
        guard !isSyncing else { return }
        isSyncing = true
        downloadProgress = nil

        do {
            let patches = try await service.fetchAvailablePatches()

            await MainActor.run {
                self.availablePatches = patches
                self.lastSyncDate = Date()
            }

            log("remote: downloading \(patches.count) assigned patches")

            // Limpiar directorio antes de descargar (para eliminar patches de sesiones anteriores)
            try? cleanPatchesDirectory()

            // Resetear IDs descargados para esta sesión
            downloadedIds = []

            for patch in patches {
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

            await MainActor.run {
                self.downloadProgress = nil
                self.isSyncing = false
            }

            // Notificar que los archivos cambiaron
            NotificationCenter.default.post(name: .patchesDidChange, object: nil)

            log("remote: sync complete - \(patches.count) patches downloaded")
        } catch {
            await MainActor.run { self.isSyncing = false }
            log("remote: sync failed - \(error.localizedDescription)")
        }
    }

    // Limpiar directorio de patches
    private func cleanPatchesDirectory() throws {
        guard FileManager.default.fileExists(atPath: patchesDirectory.path) else { return }
        
        let files = try FileManager.default.contentsOfDirectory(at: patchesDirectory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension.lowercased() == "3105" {
            try FileManager.default.removeItem(at: file)
            log("remote: cleaned \(file.lastPathComponent)")
        }
    }

    func downloadPatch(_ patch: RemotePatchInfo) async throws {
        let (data, filename) = try await service.downloadPatch(patchId: patch.id)

        try FileManager.default.createDirectory(at: patchesDirectory, withIntermediateDirectories: true)

        let fileURL = patchesDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)

        if let password = patch.password, !password.isEmpty {
            do {
                let summary = try PatchPackageCodec.inspect(data)
                let decoded = try PatchPackageCodec.decode(data, password: password)
                try PatchKeyStore.store(decoded.contentKey, for: summary)
                log("remote: \(filename) decodificado con password y contentKey guardado")
            } catch {
                log("remote: ERROR decodificando \(filename) con password: \(error)")
            }
        }

        var ids = downloadedIds
        ids.insert(patch.id)
        downloadedIds = ids

        log("remote: saved \(filename) to PatchProjects/")
    }

    func isDownloaded(_ patchId: String) -> Bool {
        return downloadedIds.contains(patchId)
    }
}

extension Notification.Name {
    static let patchesDidChange = Notification.Name("patchesDidChange")
}
