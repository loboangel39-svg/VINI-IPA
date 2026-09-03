import Foundation

// MARK: - Patch Journal Models

/// Representa una entrada en el journal de patches.
/// Cada vez que se aplica o restaura un patch, se crea una entrada.
struct JournalEntry: Codable {
    let id: Int?
    let patchId: String
    let action: String        // "applied", "restored", "failed"
    let targetFile: String
    let originalHash: String
    let patchedHash: String
    let backupR2Key: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, action
        case patchId = "patch_id"
        case targetFile = "target_file"
        case originalHash = "original_hash"
        case patchedHash = "patched_hash"
        case backupR2Key = "backup_r2_key"
        case createdAt = "created_at"
    }
}

struct JournalResponse: Codable {
    let journal: [JournalEntry]
    let applied: [AppliedPatchInfo]
    let restored: [RestoredPatchInfo]
}

struct AppliedPatchInfo: Codable {
    let patchId: String
    let targetFile: String
    let appliedAt: String
}

struct RestoredPatchInfo: Codable {
    let patchId: String
    let targetFile: String
    let restoredAt: String
}

struct RestoreResponse: Codable {
    let success: Bool
    let message: String?
    let journal: JournalEntry?
}

// MARK: - Patch Journal Service

/// Gestiona el journal de patches: registro de aplicaciones y restauraciones.
/// Permite que "Restore Original" funcione sin errores al saber exactamente
/// qué patch fue aplicado, a qué archivo, y cuál es el backup.
final class PatchJournalService {
    static let shared = PatchJournalService()

    private var workerBaseURL: String { "https://vini-patch-worker.loboangel39.workers.dev" }

    private var authToken: String? {
        UserDefaults.standard.string(forKey: "remotePatch.authToken")
    }

    // MARK: - Journal Queries

    /// Registra que un patch fue aplicado exitosamente.
    func logApply(
        patchId: String,
        targetFile: String,
        originalHash: String,
        patchedHash: String,
        backupR2Key: String = "",
        metadata: [String: Any] = [:]
    ) async throws {
        let metadataJSON = String(data: try JSONSerialization.data(withJSONObject: metadata), encoding: .utf8) ?? "{}"
        let body: [String: String] = [
            "patchId": patchId,
            "targetFile": targetFile,
            "originalHash": originalHash,
            "patchedHash": patchedHash,
            "backupR2Key": backupR2Key,
            "metadata": metadataJSON,
        ]
        _ = try await postJournal(endpoint: "/api/app/journal/apply", body: body)
        log("logged apply for patch \(patchId)")
    }

    /// Registra que un patch fue restaurado a su estado original.
    /// Retorna la entrada del journal con la info del backup.
    @discardableResult
    func logRestore(patchId: String) async throws -> JournalEntry? {
        let body = ["patchId": patchId]
        let data = try await postJournal(endpoint: "/api/app/journal/restore", body: body)
        let decoder = JSONDecoder()
        if let resp = try? decoder.decode(RestoreResponse.self, from: data) {
            log("logged restore for patch \(patchId), success=\(resp.success)")
            return resp.journal
        }
        return nil
    }

    /// Obtiene el journal completo del usuario (último estado por patch).
    func fetchJournal() async throws -> [JournalEntry] {
        guard let token = authToken else { return [] }
        guard let url = URL(string: "\(workerBaseURL)/api/app/journal") else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }

        let resp = try JSONDecoder().decode(JournalResponse.self, from: data)
        return resp.journal
    }

    /// Verifica si un patch tiene estado "applied" (se puede restaurar).
    func canRestore(patchId: String) async -> Bool {
        guard let entries = try? await fetchJournal() else { return false }
        return entries.contains { $0.patchId == patchId && $0.action == "applied" }
    }

    /// Obtiene la lista de patches que están actualmente aplicados.
    func getAppliedPatches() async -> [AppliedPatchInfo] {
        guard let token = authToken,
              let url = URL(string: "\(workerBaseURL)/api/app/journal") else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let resp = try? JSONDecoder().decode(JournalResponse.self, from: data) else {
            return []
        }
        return resp.applied
    }

    // MARK: - Helpers

    private func postJournal(endpoint: String, body: [String: String]) async throws -> Data {
        guard let token = authToken else {
            throw RemotePatchError.unauthorized
        }
        guard let url = URL(string: "\(workerBaseURL)\(endpoint)") else {
            throw RemotePatchError.networkError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RemotePatchError.networkError
        }
        return data
    }

    private func log(_ message: String) {
        print("[PatchJournal] \(message)")
    }
}
