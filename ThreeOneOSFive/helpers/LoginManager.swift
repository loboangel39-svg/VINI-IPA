import Foundation
import UIKit

struct LoginResponse {
    let success: Bool
    let message: String
    let expiresAt: Date?
}

final class LoginManager {
    
    // MARK: - VINI V2 API URL
    private static let workerURL = "https://vini-v2-api.loboangel39.workers.dev"
    
    /// Obtiene el HWID persistente del Keychain.
    /// Este HWID NO cambia al reinstalar la app.
    static func getPersistentHWID() -> String {
        return KeychainManager.shared.getOrCreatePersistentHWID()
    }
    
    /// Inicia sesión validando la licencia contra el Worker V2
    static func login(licenseKey: String, completion: @escaping (Bool, String, Date?) -> Void) {
        let hwid = getPersistentHWID()
        
        print("[LoginManager] Validating license: \(licenseKey)")
        print("[LoginManager] HWID (persistent): \(hwid)")
        
        validateWithWorker(licenseKey: licenseKey, hwid: hwid, completion: completion)
    }
    
    /// Valida licencia contra el Worker V2 API
    private static func validateWithWorker(licenseKey: String, hwid: String, completion: @escaping (Bool, String, Date?) -> Void) {
        guard let url = URL(string: "\(workerURL)/api/app/validate-license") else {
            completion(false, "Configuration error", nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let body: [String: String] = [
            "licenseKey": licenseKey,
            "hwid": hwid
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(false, "Request error", nil)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, "Connection error: \(error.localizedDescription)", nil)
                return
            }
            
            guard let data = data else {
                completion(false, "No response from server", nil)
                return
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(false, "Invalid server response", nil)
                return
            }
            
            let valid = json["valid"] as? Bool ?? false
            let errorMessage = json["error"] as? String
            
            if valid {
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
                var expiresAt: Date? = nil
                if let expiresStr = json["expiresAt"] as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime]
                    expiresAt = formatter.date(from: expiresStr)
                }
                
                completion(true, "Login successful", expiresAt)
            } else {
                completion(false, errorMessage ?? "Invalid license", nil)
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
    static func tryAutoLogin(completion: @escaping (Bool, String?, Date?) -> Void) {
        guard let licenseKey = KeychainManager.shared.loadLicenseKey() else {
            completion(false, nil, nil)
            return
        }
        
        print("[LoginManager] Attempting auto-login with saved license key")
        
        login(licenseKey: licenseKey) { success, message, expiresAt in
            if success {
                print("[LoginManager] Auto-login successful")
                completion(true, licenseKey, expiresAt)
            } else {
                print("[LoginManager] Auto-login failed: \(message)")
                completion(false, nil, nil)
            }
        }
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
