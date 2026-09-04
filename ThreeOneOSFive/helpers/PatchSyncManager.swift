import Foundation
import SwiftUI
import CommonCrypto

// MARK: - Patch Sync Manager (VINI V2)
// Compatibilidad con el sistema existente de PatchProjectLibrary.
// Usa PatchManager para la lógica de descarga robusta.
// Los patches se guardan en Documents/RemotePatches/ (PatchStorage)
// y también se copian a Application Support/PatchProjects/ para compatibilidad.

final class PatchSyncManager: ObservableObject {
    static let shared = PatchSyncManager()
    
    @Published var availablePatches: [RemotePatchInfo] = []
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var downloadProgress: String?
    
    private let patchManager = PatchManager.shared
    private let workerURL = "https://vini-v2-api.loboangel39.workers.dev"
    
    // Ruta donde PatchProjectLibrary busca los patches (compatibilidad)
    private var patchesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("PatchProjects", isDirectory: true)
    }
    
    init() {}
    
    // MARK: - Sincronizar patches remotos (delegar a PatchManager)
    func syncPatches() async {
        await patchManager.syncPatches()
        
        // Copiar patches de RemotePatches/ a PatchProjects/ para compatibilidad
        await copyPatchesToLegacyLocation()
        
        // Sincronizar estado local
        await MainActor.run {
            self.availablePatches = patchManager.availablePatches
            self.lastSyncDate = patchManager.lastSyncDate
            self.isSyncing = false
        }
    }
    
    // MARK: - Copiar patches a la ubicación legacy
    private func copyPatchesToLegacyLocation() async {
        let localIds = patchManager.localPatchIds()
        
        try? FileManager.default.createDirectory(at: patchesDirectory, withIntermediateDirectories: true)
        
        for patchId in localIds {
            guard let data = patchManager.patchData(patchId) else { continue }
            
            let legacyURL = patchesDirectory.appendingPathComponent("patch-\(patchId).3105")
            
            // Solo escribir si cambió
            if let existingData = try? Data(contentsOf: legacyURL), existingData == data {
                continue
            }
            
            try? data.write(to: legacyURL)
        }
        
        // Notificar cambios
        notifyPatchesChanged()
    }
    
    // MARK: - Verificar si ya está descargado
    func isDownloaded(_ patchId: String) -> Bool {
        return patchManager.isDownloaded(patchId)
    }
    
    // MARK: - Forzar recarga de la lista de patches
    func notifyPatchesChanged() {
        NotificationCenter.default.post(name: .patchesDidChange, object: nil)
    }

    // MARK: - Journal Restore (compatibilidad con sistema existente)
    func journalLogRestore(patchId: String) async -> String? {
        guard let token = UserDefaults.standard.string(forKey: "vini.authToken") else { return nil }
        guard let url = URL(string: "\(workerURL)/api/app/telemetry") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "action": "journal_restore",
            "patchId": patchId,
        ]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                return nil
            }
        } catch {
            print("[PatchSyncManager] journal restore failed: \(error.localizedDescription)")
        }
        return nil
    }
}

// MARK: - Notification para recargar patches
extension Notification.Name {
    static let patchesDidChange = Notification.Name("patchesDidChange")
}
