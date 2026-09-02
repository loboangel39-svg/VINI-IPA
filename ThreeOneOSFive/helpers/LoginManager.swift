import Foundation
import UIKit

struct LoginResponse {
    let success: Bool
    let message: String
    let expiresAt: Date?
}

final class LoginManager {
    
    private static let projectId = "vini-ios-7f93a"
    private static let apiKey = "AIzaSyD0OAaWFuEjkihtnLyzYsQC9kB9J_K8YgM"
    private static let baseURL = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents"
    
    // URL del Worker API para validación de licencias remotas
    private static let workerURL = "https://vini-patch-worker.loboangel39.workers.dev"
    
    /// Inicia sesión validando la licencia
    /// Primero intenta con el Worker API (Cloudflare), si falla usa Firebase
    static func login(licenseKey: String, completion: @escaping (Bool, String, Date?) -> Void) {
        let hwid = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        
        // Primero intentar con el Worker API
        validateWithWorker(licenseKey: licenseKey, hwid: hwid) { success, message, expiresAt in
            if success {
                completion(success, message, expiresAt)
            } else {
                // Si falla, intentar con Firebase (fallback)
                validateWithFirebase(licenseKey: licenseKey, hwid: hwid, completion: completion)
            }
        }
    }
    
    /// Valida licencia contra el Worker API de Cloudflare
    private static func validateWithWorker(licenseKey: String, hwid: String, completion: @escaping (Bool, String, Date?) -> Void) {
        guard let url = URL(string: "\(workerURL)/api/app/validate-license") else {
            completion(false, "Error de configuración", nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        
        let body: [String: String] = [
            "licenseKey": licenseKey,
            "hwid": hwid
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(false, "Error al procesar la solicitud", nil)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                log("Worker validation error: \(error.localizedDescription)")
                completion(false, "Error de conexión", nil)
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(false, "Respuesta inválida", nil)
                return
            }
            
            let valid = json["valid"] as? Bool ?? false
            let errorMessage = json["error"] as? String
            
            if valid {
                // Guardar token si viene
                if let token = json["token"] as? String {
                    UserDefaults.standard.set(token, forKey: "remotePatch.authToken")
                }
                
                // Parsear fecha de expiración
                var expiresAt: Date? = nil
                if let expiresStr = json["expiresAt"] as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime]
                    expiresAt = formatter.date(from: expiresStr)
                }
                
                log("Worker: license validated successfully")
                completion(true, "Inicio de sesión exitoso", expiresAt)
            } else {
                log("Worker: license invalid - \(errorMessage ?? "unknown")")
                completion(false, errorMessage ?? "Licencia inválida", nil)
            }
        }.resume()
    }
    
    /// Valida licencia contra Firebase (fallback)
    private static func validateWithFirebase(licenseKey: String, hwid: String, completion: @escaping (Bool, String, Date?) -> Void) {
        log("Falling back to Firebase validation")
        
        // Primero, buscar la licencia por clave
        let queryURL = "\(baseURL):runQuery?key=\(apiKey)"
        
        guard let url = URL(string: queryURL) else {
            completion(false, "Error de configuración", nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let query: [String: Any] = [
            "structuredQuery": [
                "from": [
                    ["collectionId": "licenses"]
                ],
                "where": [
                    "fieldFilter": [
                        "field": ["fieldPath": "key"],
                        "op": "EQUAL",
                        "value": ["stringValue": licenseKey]
                    ]
                ],
                "limit": 1
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: query)
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
                if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstResult = jsonArray.first,
                   let document = firstResult["document"] as? [String: Any],
                   let fields = document["fields"] as? [String: Any] {
                    
                    let documentName = document["name"] as? String ?? ""
                    
                    // Verificar si la licencia está activa
                    if let activeField = fields["active"] as? [String: Any],
                       let isActive = activeField["booleanValue"] as? Bool,
                       !isActive {
                        completion(false, "Licencia desactivada", nil)
                        return
                    }
                    
                    // Verificar expiración
                    var expirationDate: Date? = nil
                    if let expiresAtField = fields["expiresAt"] as? [String: Any],
                       let timestampString = expiresAtField["timestampValue"] as? String {
                        
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        
                        if let expDate = formatter.date(from: timestampString) {
                            expirationDate = expDate
                            if Date() > expDate {
                                completion(false, "Licencia expirada", nil)
                                return
                            }
                        }
                    }
                    
                    // Verificar HWID
                    if let hwidField = fields["hwid"] as? [String: Any],
                       let registeredHwid = hwidField["stringValue"] as? String,
                       !registeredHwid.isEmpty {
                        
                        // La licencia ya tiene HWID registrado
                        if registeredHwid == hwid {
                            // HWID coincide - Login exitoso
                            updateLastLogin(documentName: documentName)
                            completion(true, "Inicio de sesión exitoso", expirationDate)
                        } else {
                            // HWID no coincide
                            completion(false, "Esta licencia ya está vinculada a otro dispositivo", nil)
                        }
                    } else {
                        // La licencia NO tiene HWID registrado - Registrar el HWID actual
                        registerHwid(documentName: documentName, hwid: hwid) { success in
                            if success {
                                updateLastLogin(documentName: documentName)
                                completion(true, "Licencia activada para este dispositivo", expirationDate)
                            } else {
                                completion(false, "Error al registrar el dispositivo", nil)
                            }
                        }
                    }
                } else {
                    completion(false, "Licencia inválida", nil)
                }
            } catch {
                completion(false, "Error al procesar la respuesta", nil)
            }
        }.resume()
    }
    
    /// Verifica si una licencia sigue activa en Firestore
    static func verifyLicense(licenseKey: String, completion: @escaping (Bool) -> Void) {
        let hwid = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        
        let queryURL = "\(baseURL):runQuery?key=\(apiKey)"
        
        guard let url = URL(string: queryURL) else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        
        let query: [String: Any] = [
            "structuredQuery": [
                "from": [
                    ["collectionId": "licenses"]
                ],
                "where": [
                    "compositeFilter": [
                        "op": "AND",
                        "filters": [
                            [
                                "fieldFilter": [
                                    "field": ["fieldPath": "key"],
                                    "op": "EQUAL",
                                    "value": ["stringValue": licenseKey]
                                ]
                            ],
                            [
                                "fieldFilter": [
                                    "field": ["fieldPath": "hwid"],
                                    "op": "EQUAL",
                                    "value": ["stringValue": hwid]
                                ]
                            ],
                            [
                                "fieldFilter": [
                                    "field": ["fieldPath": "active"],
                                    "op": "EQUAL",
                                    "value": ["booleanValue": true]
                                ]
                            ]
                        ]
                    ]
                ],
                "limit": 1
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: query)
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
                if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstResult = jsonArray.first,
                   let document = firstResult["document"] as? [String: Any],
                   let fields = document["fields"] as? [String: Any] {
                    
                    // Verificar expiración
                    if let expiresAtField = fields["expiresAt"] as? [String: Any],
                       let timestampString = expiresAtField["timestampValue"] as? String {
                        
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        
                        if let expirationDate = formatter.date(from: timestampString) {
                            DispatchQueue.main.async { completion(Date() <= expirationDate) }
                        } else {
                            DispatchQueue.main.async { completion(false) }
                        }
                    } else {
                        DispatchQueue.main.async { completion(true) }
                    }
                } else {
                    DispatchQueue.main.async { completion(false) }
                }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }.resume()
    }
    
    /// Registra el HWID en la licencia (primera vez que se usa)
    private static func registerHwid(documentName: String, hwid: String, completion: @escaping (Bool) -> Void) {
        guard !documentName.isEmpty else {
            completion(false)
            return
        }
        
        // Codificar "(default)" en la URL del documento
        let encodedPath = documentName.replacingOccurrences(of: "/databases/(default)/",
                                                             with: "/databases/%28default%29/")
        let updateURL = "https://firestore.googleapis.com/v1/\(encodedPath)?updateMask.fieldPaths=hwid&key=\(apiKey)"
        
        guard let url = URL(string: updateURL) else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let updateData: [String: Any] = [
            "fields": [
                "hwid": [
                    "stringValue": hwid
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: updateData)
        } catch {
            completion(false)
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error registrando HWID: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                completion(true)
            } else {
                completion(false)
            }
        }.resume()
    }
    
    /// Actualiza el último login del usuario
    private static func updateLastLogin(documentName: String) {
        guard !documentName.isEmpty else { return }
        
        // Codificar "(default)" en la URL del documento
        let encodedPath = documentName.replacingOccurrences(of: "/databases/(default)/",
                                                             with: "/databases/%28default%29/")
        let updateURL = "https://firestore.googleapis.com/v1/\(encodedPath)?updateMask.fieldPaths=lastLogin&key=\(apiKey)"
        
        guard let url = URL(string: updateURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let nowString = formatter.string(from: Date())
        
        let updateData: [String: Any] = [
            "fields": [
                "lastLogin": [
                    "timestampValue": nowString
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: updateData)
        } catch {
            return
        }
        
        URLSession.shared.dataTask(with: request) { _, _, _ in
            // No necesitamos hacer nada con la respuesta
        }.resume()
    }
}
