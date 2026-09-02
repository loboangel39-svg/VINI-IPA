import Foundation
import UIKit

// MARK: - Remote Patch Models

struct RemotePatch: Identifiable, Codable {
    let id: String
    let name: String
    let bundleId: String
    let version: String
    let description: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, version, description
        case bundleId = "bundle_id"
        case createdAt = "created_at"
    }
}

struct RemotePatchList: Codable {
    let patches: [RemotePatch]
}

struct LicenseValidationResponse: Codable {
    let valid: Bool
    let token: String?
    let expiresAt: String?
    let error: String?
}

struct AppUpdateResponse: Codable {
    let updateAvailable: Bool
    let latestVersion: String?
    let releaseNotes: String?
    let downloadUrl: String?
}

// MARK: - Remote Patch Service

/// Communicates with the VINI Patch Worker API for remote patch management.
/// Replaces the Firebase-based license validation with a self-hosted Cloudflare Worker.
final class RemotePatchService {
    static let shared = RemotePatchService()

    /// Base URL of the Cloudflare Worker. Change this to your deployed worker URL.
    var baseURL: String {
        get { UserDefaults.standard.string(forKey: "remotePatch.baseURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "remotePatch.baseURL") }
    }

    var authToken: String? {
        get { UserDefaults.standard.string(forKey: "remotePatch.authToken") }
        set { UserDefaults.standard.set(newValue, forKey: "remotePatch.authToken") }
    }

    private var licenseKey: String? {
        get { UserDefaults.standard.string(forKey: "remotePatch.licenseKey") }
        set { UserDefaults.standard.set(newValue, forKey: "remotePatch.licenseKey") }
    }

    // MARK: - License Validation

    /// Validates a license key against the Worker API, replacing Firebase validation.
    func validateLicense(key: String) async throws -> LicenseValidationResponse {
        let hwid = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"

        var request = URLRequest(url: URL(string: "\(baseURL)/api/app/validate-license")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "licenseKey": key,
            "hwid": hwid,
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RemotePatchError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(LicenseValidationResponse.self, from: data)

        if decoded.valid, let token = decoded.token {
            self.authToken = token
            self.licenseKey = key
            log("remote: license validated, token received")
        }

        return decoded
    }

    /// Re-checks the current session validity.
    func verifySession() async -> Bool {
        guard let token = authToken else { return false }

        var request = URLRequest(url: URL(string: "\(baseURL)/api/app/patches")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    // MARK: - Remote Patches

    /// Fetches the list of patches assigned to the current user.
    func fetchAssignedPatches() async throws -> [RemotePatch] {
        guard let token = authToken else {
            throw RemotePatchError.unauthorized
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/api/app/patches")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw RemotePatchError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(RemotePatchList.self, from: data)
        log("remote: fetched \(decoded.patches.count) assigned patches")
        return decoded.patches
    }

    /// Downloads a patch file (.3105) from the remote server.
    func downloadPatch(patchId: String) async throws -> (Data, String) {
        guard let token = authToken else {
            throw RemotePatchError.unauthorized
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/api/app/patches/\(patchId)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw RemotePatchError.downloadFailed
        }

        // Extract filename from Content-Disposition header
        let disposition = http.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        let filename: String
        if let match = disposition.range(of: "filename=\"") {
            let start = match.upperBound
            if let end = disposition[start...].firstIndex(of: "\"") {
                filename = String(disposition[start..<end])
            } else {
                filename = "patch_\(patchId).3105"
            }
        } else {
            filename = "patch_\(patchId).3105"
        }

        log("remote: downloaded patch \(filename) (\(data.count) bytes)")
        return (data, filename)
    }

    // MARK: - App Updates

    /// Checks for app updates via the Worker API (falls back to GitHub).
    func checkAppUpdate() async -> AppUpdateResponse? {
        let currentVersion = AppUpdateChecker.currentVersion
        var request = URLRequest(
            url: URL(string: "\(baseURL)/api/app/check-updates?currentVersion=\(currentVersion)")!
        )
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(AppUpdateResponse.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Cleanup

    func clearSession() {
        authToken = nil
        licenseKey = nil
        log("remote: session cleared")
    }
}

// MARK: - Errors

enum RemotePatchError: LocalizedError {
    case unauthorized
    case invalidResponse
    case downloadFailed
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Sesión no válida. Inicia sesión de nuevo."
        case .invalidResponse: return "Respuesta inválida del servidor."
        case .downloadFailed: return "Error al descargar el patch."
        case .networkError(let msg): return "Error de red: \(msg)"
        }
    }
}
