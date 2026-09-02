import Foundation
import UIKit

struct LoginResponse {
    let success: Bool
    let message: String
    let expiresAt: Date?
}

final class LoginManager {
    
    // URL del Worker API para validación de licencias
    private static let workerURL = "https://vini-patch-worker.loboangel39.workers.dev"
    
    /// Inicia sesión validando la licencia contra el Worker
    static func login(licenseKey: String, completion: @escaping (Bool, String, Date?) -> Void) {
        let hwid = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        
        print("🔑 Validando licencia: \(licenseKey)")
        print("📱 HWID: \(hwid)")
        
        validateWithWorker(licenseKey: licenseKey, hwid: hwid, completion: completion)
    }
    
    /// Valida licencia contra el Worker API de Cloudflare
    private static func validateWithWorker(licenseKey: String, hwid: String, completion: @escaping (Bool, String, Date?) -> Void) {
        guard let url = URL(string: "\(workerURL)/api/app/validate-license") else {
            print("❌ Error: URL inválida")
            completion(false, "Error de configuración", nil)
            return
        }
        
        print("🌐 URL: \(url.absoluteString)")
        
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
            print("📤 Body: \(String(data: request.httpBody!, encoding: .utf8) ?? "")")
        } catch {
            print("❌ Error serializando body: \(error)")
            completion(false, "Error al procesar la solicitud", nil)
            return
        }
        
        print("⏳ Enviando request...")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Error de red: \(error.localizedDescription)")
                completion(false, "Error de conexión: \(error.localizedDescription)", nil)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Status code: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                print("❌ No se recibió data")
                completion(false, "No se recibió respuesta del servidor", nil)
                return
            }
            
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("📥 Respuesta raw: \(rawResponse)")
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Error parseando JSON")
                completion(false, "Respuesta inválida del servidor", nil)
                return
            }
            
            let valid = json["valid"] as? Bool ?? false
            let errorMessage = json["error"] as? String
            
            print("✅ Valid: \(valid)")
            if let error = errorMessage {
                print("❌ Error: \(error)")
            }
            
            if valid {
                // Guardar token si viene
                if let token = json["token"] as? String {
                    UserDefaults.standard.set(token, forKey: "remotePatch.authToken")
                    print("💾 Token guardado")
                }
                
                // Parsear fecha de expiración
                var expiresAt: Date? = nil
                if let expiresStr = json["expiresAt"] as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime]
                    expiresAt = formatter.date(from: expiresStr)
                    print("📅 Expires: \(expiresAt ?? Date())")
                }
                
                print("✅ Licencia validada exitosamente")
                completion(true, "Inicio de sesión exitoso", expiresAt)
            } else {
                print("❌ Licencia inválida: \(errorMessage ?? "unknown")")
                completion(false, errorMessage ?? "Licencia inválida", nil)
            }
        }.resume()
    }
    
    /// Verifica si una licencia sigue activa
    static func verifyLicense(licenseKey: String, completion: @escaping (Bool) -> Void) {
        let hwid = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        
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
}
