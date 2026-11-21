import Foundation
import UIKit

struct LoginResponse {
    let success: Bool
    let message: String
    let expiresAt: Date?
    let licenseExpiresAt: Date?
}

struct ServerAccessState {
    let status: String
    let frozenSeconds: Int?
    let serverTime: Date?
    let maintenanceMessage: String?
}

@MainActor
final class AccessStateCoordinator: ObservableObject {
    @Published private(set) var state: ServerAccessState?
    var status: String? { state?.status }
    func apply(_ nextState: ServerAccessState?) { state = nextState }
    func clear() { state = nil }
}

enum LicensePlan: String {
    case basic = "Basic"
    case premium = "Premium"
    case exclusive = "Exclusive"
}

final class LoginManager {
    enum StoredSessionResult {
        case valid(licenseExpiresAt: Date?, licensePlan: String?, accessState: ServerAccessState?)
        case revoked
        case networkError
    }
    
    // MARK: - VINI V2 API URL
    private static let workerURL = "https://vini-v2-api.loboangel39.workers.dev"
    
    /// Obtiene el HWID persistente del Keychain.
    /// Este HWID NO cambia al reinstalar la app.
    static func getPersistentHWID() -> String {
        return KeychainManager.shared.getOrCreatePersistentHWID()
    }
    
    /// Inicia sesión validando la licencia contra el Worker V2
    static func login(licenseKey: String, completion: @escaping (Bool, String, Date?, Date?, String?, ServerAccessState?) -> Void) {
        let hwid = getPersistentHWID()
        
        print("[AUTH] login validation started; hwid present=\(!hwid.isEmpty)")
        
        validateWithWorker(licenseKey: licenseKey, hwid: hwid, completion: completion)
    }
    
    /// Valida licencia contra el Worker V2 API
    private static func validateWithWorker(licenseKey: String, hwid: String, completion: @escaping (Bool, String, Date?, Date?, String?, ServerAccessState?) -> Void) {
        guard let url = URL(string: "\(workerURL)/api/app/validate-license") else {
            completion(false, "Configuration error", nil, nil, nil, nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("license-plan-v1,access-state-v1", forHTTPHeaderField: "X-VINI-Capabilities")
        request.timeoutInterval = 30
        
        let body: [String: String] = [
            "licenseKey": licenseKey,
            "hwid": hwid
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(false, "Request error", nil, nil, nil, nil)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[AUTH] login transport failure: \(error.localizedDescription)")
                completion(false, "Connection error: \(error.localizedDescription)", nil, nil, nil, nil)
                return
            }
            
            guard let data = data else {
                completion(false, "No response from server", nil, nil, nil, nil)
                return
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(false, "Invalid server response", nil, nil, nil, nil)
                return
            }
            
            let valid = json["valid"] as? Bool ?? false
            let errorMessage = json["error"] as? String
            
            if valid {
                print("[AUTH] license validation accepted")
                // Guardar token de sesión en Keychain (sobrevive reinstalaciones)
                if let token = json["token"] as? String {
                    KeychainManager.shared.saveAuthToken(token)
                }
                
                // Guardar username en Keychain
                if let username = json["username"] as? String {
                    KeychainManager.shared.saveUsername(username)
                }
                
                // Guardar license key en Keychain (para auto-login)
                KeychainManager.shared.saveLicenseKey(licenseKey)
                
                // Parsear fecha de expiración
                let expiresAt = parseISO8601Date(json["expiresAt"] as? String)
                let licenseExpiresAt = parseISO8601Date(json["licenseExpiresAt"] as? String)
                let licensePlan = resolvedLicensePlan(from: json)
                
                completion(true, "Login successful", expiresAt, licenseExpiresAt, licensePlan, parseAccessState(from: json))
            } else {
                print("[AUTH] license validation rejected")
                completion(false, errorMessage ?? "Invalid license", nil, nil, nil, nil)
            }
        }.resume()
    }
    
    /// Verifica si una licencia sigue activa (re-validate)
    static func verifyLicense(licenseKey: String, completion: @escaping (Bool) -> Void) {
        let hwid = getPersistentHWID()
        
        guard let url = URL(string: "\(workerURL)/api/app/validate-license") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        
        let body: [String: String] = [
            "licenseKey": licenseKey,
            "hwid": hwid
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(false)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let valid = json["valid"] as? Bool ?? false
                DispatchQueue.main.async { completion(valid) }
            } else {
                DispatchQueue.main.async { completion(false) }
            }
        }.resume()
    }
    
    /// Intenta auto-login con credenciales guardadas en Keychain.
    /// Retorna true si hay credenciales y se puede intentar login.
    static func tryAutoLogin(completion: @escaping (Bool, String?, Date?, Date?, String?, ServerAccessState?) -> Void) {
        guard let licenseKey = KeychainManager.shared.loadLicenseKey() else {
            completion(false, nil, nil, nil, nil, nil)
            return
        }
        
        print("[AUTH] auto-login started with saved credentials")
        
        login(licenseKey: licenseKey) { success, message, expiresAt, licenseExpiresAt, licensePlan, accessState in
            if success {
                print("[AUTH] auto-login accepted by server")
                completion(true, licenseKey, expiresAt, licenseExpiresAt, licensePlan, accessState)
            } else {
                print("[AUTH] auto-login rejected: \(message)")
                completion(false, nil, nil, nil, nil, nil)
            }
        }
    }

    private static func parseISO8601Date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// Verifies an existing JWT before considering the saved license for autologin.
    /// A revoked token must stop the automatic re-binding path.
    static func verifyStoredSession(completion: @escaping (StoredSessionResult) -> Void) {
        guard let token = KeychainManager.shared.loadAuthToken(),
              let url = URL(string: "\(workerURL)/api/app/session") else {
            completion(.revoked)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("license-plan-v1,access-state-v1", forHTTPHeaderField: "X-VINI-Capabilities")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if error != nil || data == nil {
                DispatchQueue.main.async { completion(.networkError) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[AUTH] session response status=\(status)")
            if status == 401 || status == 403 {
                // A paused license may be rejected by an older session route
                // even though the license contract can still authenticate it.
                // Revalidate through the license endpoint before treating the
                // JWT as revoked, preserving the paused-access screen.
                guard KeychainManager.shared.loadLicenseKey() != nil else {
                    DispatchQueue.main.async { completion(.revoked) }
                    return
                }
                tryRevalidateStoredLicense { result in
                    DispatchQueue.main.async { completion(result) }
                }
                return
            }
            let licenseExpiresAt: Date?
            let licensePlan: String?
            let accessState: ServerAccessState?
            guard status == 200,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    completion(status == 401 ? .revoked : .networkError)
                }
                return
            }
            if status == 200 {
                licenseExpiresAt = parseISO8601Date(json["licenseExpiresAt"] as? String)
                licensePlan = resolvedLicensePlan(from: json)
                accessState = parseAccessState(from: json)
            } else {
                licenseExpiresAt = nil
                licensePlan = nil
                accessState = nil
            }
            if let licenseExpiresAt, Date() >= licenseExpiresAt {
                DispatchQueue.main.async { completion(.revoked) }
                return
            }
            DispatchQueue.main.async {
                let reportedAccess = (json["access"] as? [String: Any])?["status"] as? String ?? "legacy"
                print("[AUTH] session access state=\(reportedAccess)")
                completion(.valid(licenseExpiresAt: licenseExpiresAt, licensePlan: licensePlan, accessState: accessState))
            }
        }.resume()
    }

    private static func tryRevalidateStoredLicense(completion: @escaping (StoredSessionResult) -> Void) {
        guard let licenseKey = KeychainManager.shared.loadLicenseKey() else {
            completion(.revoked)
            return
        }
        login(licenseKey: licenseKey) { success, _, expiresAt, licenseExpiresAt, plan, access in
            guard success else {
                completion(.revoked)
                return
            }
            completion(.valid(licenseExpiresAt: licenseExpiresAt, licensePlan: plan, accessState: access))
        }
    }

    private static func resolvedLicensePlan(from json: [String: Any]) -> String? {
        if let rawPlan = json["licensePlan"] as? String,
           let plan = LicensePlan(rawValue: rawPlan) {
            return plan.rawValue
        }
        return nil
    }

    private static func parseAccessState(from json: [String: Any]) -> ServerAccessState? {
        guard let access = json["access"] as? [String: Any],
              let status = access["status"] as? String else { return nil }
        return ServerAccessState(
            status: status,
            frozenSeconds: access["frozenSeconds"] as? Int,
            serverTime: parseISO8601Date(access["serverTime"] as? String),
            maintenanceMessage: access["maintenanceMessage"] as? String
        )
    }
    
    /// Limpia la sesión del usuario (pero NO borra el license key del Keychain para permitir re-login)
    static func clearSession() {
        KeychainManager.shared.deleteAuthToken()
        UserDefaults.standard.removeObject(forKey: "vini.authToken")
        UserDefaults.standard.removeObject(forKey: "vini.username")
    }
    
    /// Limpia TODAS las credenciales (logout completo, requiere nueva licencia)
    static func clearAllCredentials() {
        KeychainManager.shared.deleteAll()
        clearSession()
    }
}
