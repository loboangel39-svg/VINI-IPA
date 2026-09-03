import Foundation

// MARK: - Remote Patch Service (v3)
// Se comunica con el Worker de Cloudflare para descargar patches remotos.
// v3: Reintentos con backoff, Range requests (resume), timeout mejorado.

final class RemotePatchService {
    static let shared = RemotePatchService()

    // URL de tu Worker
    private let workerURL = "https://vini-patch-worker.loboangel39.workers.dev"

    /// Número máximo de reintentos para descargas.
    private let maxRetries = 3

    /// Timeout para descargas (segundos).
    private let downloadTimeout: TimeInterval = 60

    // MARK: - Descargar lista de patches disponibles

    func fetchAvailablePatches() async throws -> [RemotePatchInfo] {
        let url = URL(string: "\(workerURL)/api/app/patches")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

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

    // MARK: - Descargar archivo de patch (con reintentos y Range)

    func downloadPatch(patchId: String) async throws -> (Data, String) {
        var lastError: Error?

        for attempt in 1...maxRetries {
            log("download attempt \(attempt)/\(maxRetries) for patch \(patchId)")

            let url = URL(string: "\(workerURL)/api/app/patches/\(patchId)")!
            var request = URLRequest(url: url)
            request.timeoutInterval = downloadTimeout

            if let token = UserDefaults.standard.string(forKey: "remotePatch.authToken") {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            // Soporte Range: si tenemos datos parciales, pedir desde donde quedamos
            let partialURL = partialFileURL(for: patchId)
            var existingData = Data()
            if let partialData = try? Data(contentsOf: partialURL), !partialData.isEmpty {
                existingData = partialData
                request.setValue("bytes=\(existingData.count)-", forHTTPHeaderField: "Range")
                log("resuming from byte \(existingData.count)")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw RemotePatchError.networkError
                }

                if httpResponse.statusCode == 200 {
                    // Descarga completa nueva
                    let filename = extractFilename(from: httpResponse) ?? "patch_\(patchId).3105"
                    try? FileManager.default.removeItem(at: partialURL)
                    log("download complete: \(filename) (\(data.count) bytes)")
                    return (data, filename)

                } else if httpResponse.statusCode == 206 {
                    // Partial content — combinar con datos existentes
                    var combined = existingData
                    combined.append(data)
                    let filename = extractFilename(from: httpResponse) ?? "patch_\(patchId).3105"
                    try? FileManager.default.removeItem(at: partialURL)
                    log("resume complete: \(filename) (\(combined.count) bytes total)")
                    return (combined, filename)

                } else if httpResponse.statusCode == 401 {
                    throw RemotePatchError.unauthorized

                } else {
                    let errorBody = String(data: data, encoding: .utf8) ?? "(sin body)"
                    throw RemotePatchError.downloadFailed(statusCode: httpResponse.statusCode, body: errorBody)
                }

            } catch let error as RemotePatchError {
                // Si es un error definitivo, no reintentar
                switch error {
                case .unauthorized:
                    throw error
                default:
                    lastError = error
                }
            } catch {
                lastError = error
            }

            // Exponential backoff antes del reintento: 2s, 4s
            if attempt < maxRetries {
                let delay = UInt64(attempt) * 2_000_000_000
                log("retrying in \(delay / 1_000_000_000)s...")
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        throw lastError ?? RemotePatchError.networkError
    }

    // MARK: - Limpiar token de autenticación

    func clearAuth() {
        UserDefaults.standard.removeObject(forKey: "remotePatch.authToken")
    }

    // MARK: - Helpers

    /// URL temporal para datos parciales de una descarga interrumpida.
    private func partialFileURL(for patchId: String) -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        return tmpDir.appendingPathComponent("vini_partial_\(patchId).3105")
    }

    /// Extrae el filename del header Content-Disposition.
    private func extractFilename(from response: HTTPURLResponse) -> String? {
        guard let disposition = response.value(forHTTPHeaderField: "Content-Disposition") else { return nil }
        if let range = disposition.range(of: "filename=\"") {
            let filename = disposition[range.upperBound...]
            if let endRange = filename.range(of: "\"") {
                return String(filename[..<endRange.lowerBound])
            }
        }
        // Fallback sin comillas
        if let range = disposition.range(of: "filename=") {
            return String(disposition[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func log(_ message: String) {
        print("[RemotePatch] \(message)")
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
    case downloadFailed(statusCode: Int, body: String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .networkError: return "Error de conexión"
        case .downloadFailed(let code, let body):
            return "Error de descarga (\(code)): \(body)"
        case .unauthorized: return "Sesión no autorizada. Inicia sesión de nuevo."
        }
    }
}
