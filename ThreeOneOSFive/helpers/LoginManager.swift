import Foundation
import UIKit

struct LoginResponse: Codable {
    let success: Bool
    let message: String
    let expires_at: String?
}

final class LoginManager {

    private static let supabaseURL = "https://nahytmsteytjbhpexrpo.supabase.co"
    private static let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5haHl0bXN0ZXl0amJocGV4cnBvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgwOTgzNjgsImV4cCI6MjEwMzY3NDM2OH0.1cs_3ye8q1xhmGiuED4DjpO5nhftb3f5--dB_v3uoDU"

    static func login(licenseKey: String, completion: @escaping (Bool, String, Date?) -> Void) {
        let endpoint = "\(supabaseURL)/rest/v1/rpc/validate_license"
        
        guard let url = URL(string: endpoint) else {
            completion(false, "Error de configuración", nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        
        // Obtener HWID del dispositivo
        let hwid = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        
        let body: [String: Any] = [
            "p_license_key": licenseKey,
            "p_hwid": hwid
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(false, "Error al procesar la solicitud", nil)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(false, "Error de conexión: \(error.localizedDescription)", nil)
                return
            }
            
            guard let data = data else {
                completion(false, "No se recibió respuesta del servidor", nil)
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let loginResponse = try decoder.decode(LoginResponse.self, from: data)
                
                var expiresAt: Date? = nil
                if let expiresAtString = loginResponse.expires_at {
                    let formatter = ISO8601DateFormatter()
                    expiresAt = formatter.date(from: expiresAtString)
                }
                
                completion(loginResponse.success, loginResponse.message, expiresAt)
            } catch {
                completion(false, "Error al procesar la respuesta", nil)
            }
        }.resume()
    }

    /// Verifica si una licencia sigue activa en Supabase
    static func verifyLicense(licenseKey: String, completion: @escaping (Bool) -> Void) {
        let endpoint = "\(supabaseURL)/rest/v1/rpc/validate_license"
        
        guard let url = URL(string: endpoint) else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 10
        
        // Obtener HWID del dispositivo
        let hwid = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        
        let body: [String: Any] = [
            "p_license_key": licenseKey,
            "p_hwid": hwid
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
            
            do {
                let decoded = try JSONDecoder().decode(LoginResponse.self, from: data)
                DispatchQueue.main.async { completion(decoded.success) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }.resume()
    }
}
