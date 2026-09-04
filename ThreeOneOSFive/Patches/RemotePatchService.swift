import Foundation

// MARK: - Remote Patch Service (VINI V2)
// Se comunica con el Worker V2 para obtener lista de patches y configuración.
// La descarga real la hace PatchDownloadService.

final class RemotePatchService {
    static let shared = RemotePatchService()
    
    private let workerURL = "https://vini-v2-api.loboangel39.workers.dev"
    
    // MARK: - Fetch Available Patches
    
    /// GET /api/app/patches — lista de patches disponibles para el usuario
    func fetchAvailablePatches() async throws -> [RemotePatchInfo] {
        let url = URL(string: "\(workerURL)/api/app/patches")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        if let token = KeychainManager.shared.loadAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemotePatchError.networkError
        }
        
        if httpResponse.statusCode == 401 {
            throw RemotePatchError.unauthorized
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RemotePatchError.networkError
        }
        
        let decoded = try JSONDecoder().decode(PatchesResponse.self, from: data)
        return decoded.patches
    }
    
    // MARK: - Fetch Patch Detail
    
    /// GET /api/app/patches/:id — detalle de un patch
    func fetchPatchDetail(patchId: String) async throws -> RemotePatchInfo {
        let url = URL(string: "\(workerURL)/api/app/patches/\(patchId)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        if let token = KeychainManager.shared.loadAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemotePatchError.networkError
        }
        
        if httpResponse.statusCode == 401 {
            throw RemotePatchError.unauthorized
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RemotePatchError.networkError
        }
        
        return try JSONDecoder().decode(RemotePatchInfo.self, from: data)
    }
    
    // MARK: - Clear Auth
    
    func clearAuth() {
        KeychainManager.shared.deleteAuthToken()
    }
}

// MARK: - Models

struct RemotePatchInfo: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let version: String
    let type: String
    let status: String?
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, version, type, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct PatchesResponse: Codable {
    let patches: [RemotePatchInfo]
}

enum RemotePatchError: LocalizedError {
    case networkError
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .networkError: return "Connection error"
        case .unauthorized: return "Session expired. Please login again."
        }
    }
}
