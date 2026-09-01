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
    
    /// Inicia sesión validando la licencia y registrando HWID si es la primera vez
    static func login(licenseKey: String, completion: @escaping (Bool, String, Date?) -> Void) {
        let hwid = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        
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
        
        let updateURL = "\(documentName)?key=\(apiKey)"
        
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
            ],
            "updateMask": [
                "fieldPaths": ["hwid"]
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
        
        let updateURL = "\(documentName)?key=\(apiKey)"
        
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
            ],
            "updateMask": [
                "fieldPaths": ["lastLogin"]
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
