import Foundation

// MARK: - Remote Patch Service (Simple)
// Se comunica con el Worker de Cloudflare para descargar patches remotos
// NO toca Firebase - funciona independientemente

final class RemotePatchService {
    static let shared = RemotePatchService()
    
    // URL de tu Worker (cámbiala si es diferente)
    private let workerURL = "https://vini-patch-worker.loboangel39.workers.dev"
    
    // MARK: - Descargar lista de patches disponibles
    func fetchAvailablePatches() async throws -> [RemotePatchInfo] {
        let url = URL(string: "\(workerURL)/api/app/patches")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        // Incluir token JWT si existe
        if let token = UserDefaults.standard.string(forKey: "remotePatch.authToken") {
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
    
    // MARK: - Descargar archivo de patch
    func downloadPatch(patchId: String) async throws -> (Data, String) {
        let url = URL(string: "\(workerURL)/api/app/patches/\(patchId)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        
        // Incluir token JWT si existe
        if let token = UserDefaults.standard.string(forKey: "remotePatch.authToken") {
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
            throw RemotePatchError.downloadFailed
        }
        
        // Extraer nombre del archivo del header
        let filename = httpResponse.value(forHTTPHeaderField: "Content-Disposition")?
            .components(separatedBy: "filename=").last?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            ?? "patch_\(patchId).3105"
        
        return (data, filename)
    }
    
    // MARK: - Limpiar token de autenticación
    func clearAuth() {
        UserDefaults.standard.removeObject(forKey: "remotePatch.authToken")
    }
}

// MARK: - Models
struct RemotePatchInfo: Codable, Identifiable {
    let id: String
    let name: String
    let bundleId: String
    let version: String
    let description: String
    let password: String?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, version, description, password
        case bundleId = "bundle_id"
        case createdAt = "created_at"
    }
}

struct PatchesResponse: Codable {
    let patches: [RemotePatchInfo]
}

enum RemotePatchError: LocalizedError {
    case networkError
    case downloadFailed
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .networkError: return "Error de conexión"
        case .downloadFailed: return "Error al descargar el patch"
        case .unauthorized: return "No autorizado"
        }
    }
}
