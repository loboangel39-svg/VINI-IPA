import Foundation

// MARK: - Patch Download Service
// Descarga patches desde el Worker V2 con flujo robusto:
// 1. Descargar a archivo temporal
// 2. Verificar integridad (tamaño > 0)
// 3. Entregar URL temporal para que PatchStorage haga el reemplazo atómico
//
// REGLA: Cada descarga es independiente. No se bloquea por descargas anteriores.

final class PatchDownloadService {
    static let shared = PatchDownloadService()
    
    private let workerURL = "https://vini-v2-api.loboangel39.workers.dev"
    private let maxRetries = 3
    private let downloadTimeout: TimeInterval = 120
    
    // MARK: - Download
    
    /// Descarga un patch y retorna la URL del archivo temporal + metadata del response.
    /// El caller (PatchManager) es responsable de mover el archivo a su ubicación final via PatchStorage.
    func downloadPatch(patchId: String) async throws -> PatchDownloadResult {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            print("[PatchDownload] Attempt \(attempt)/\(maxRetries) for patch \(patchId)")
            
            let url = URL(string: "\(workerURL)/api/app/patches/\(patchId)/download")!
            var request = URLRequest(url: url)
            request.timeoutInterval = downloadTimeout
            
            if let token = KeychainManager.shared.loadAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw PatchDownloadError.invalidResponse
                }
                
                // 401 → token inválido
                if httpResponse.statusCode == 401 {
                    throw PatchDownloadError.unauthorized
                }
                
                // 404 → patch no encontrado o sin acceso
                if httpResponse.statusCode == 404 {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw PatchDownloadError.notFound(body)
                }
                
                // Otros errores HTTP
                guard (200..<300).contains(httpResponse.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw PatchDownloadError.httpError(statusCode: httpResponse.statusCode, body: body)
                }
                
                // Verificar que recibimos datos
                guard !data.isEmpty else {
                    throw PatchDownloadError.emptyResponse
                }
                
                // Extraer metadata de los headers
                let version = httpResponse.value(forHTTPHeaderField: "X-Patch-Version") ?? "unknown"
                let name = httpResponse.value(forHTTPHeaderField: "X-Patch-Name") ?? "unknown"
                
                // Escribir a archivo temporal
                let tempURL = PatchStorage.shared.tempFileURL(patchId: patchId)
                try data.write(to: tempURL)
                
                // Verificar que el archivo temporal tiene datos
                let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int ?? 0
                guard fileSize > 0 else {
                    try? FileManager.default.removeItem(at: tempURL)
                    throw PatchDownloadError.emptyResponse
                }
                
                print("[PatchDownload] Success: \(fileSize) bytes, version \(version)")
                
                return PatchDownloadResult(
                    tempURL: tempURL,
                    patchId: patchId,
                    version: version,
                    name: name,
                    fileSize: fileSize
                )
                
            } catch let error as PatchDownloadError {
                // Errores definitivos — no reintentar
                switch error {
                case .unauthorized, .notFound:
                    throw error
                default:
                    lastError = error
                }
            } catch {
                lastError = error
            }
            
            // Exponential backoff: 2s, 4s
            if attempt < maxRetries {
                let delay = UInt64(attempt) * 2_000_000_000
                print("[PatchDownload] Retrying in \(delay / 1_000_000_000)s...")
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        
        throw lastError ?? PatchDownloadError.unknown
    }
    
    /// Limpia archivos temporales de descargas fallidas
    func cleanup() {
        PatchStorage.shared.cleanupTempFiles()
    }
}

// MARK: - Models

struct PatchDownloadResult {
    let tempURL: URL
    let patchId: String
    let version: String
    let name: String
    let fileSize: Int
}

enum PatchDownloadError: LocalizedError {
    case invalidResponse
    case unauthorized
    case notFound(String)
    case httpError(statusCode: Int, body: String)
    case emptyResponse
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .unauthorized: return "Session expired. Please login again."
        case .notFound(let msg): return "Patch not found: \(msg)"
        case .httpError(let code, let body): return "HTTP error \(code): \(body)"
        case .emptyResponse: return "Empty response from server"
        case .unknown: return "Unknown download error"
        }
    }
}
