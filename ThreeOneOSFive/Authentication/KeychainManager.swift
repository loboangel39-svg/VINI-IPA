import Foundation
import Security

// MARK: - Keychain Manager
// Guarda credenciales en el Keychain de iOS.
// El Keychain SOBREVIVE a reinstalaciones de la app.
// Esto permite auto-login sin requerir nueva licencia al reinstalar.

final class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.vini.keychain"
    
    // Keys
    private let licenseKeyKey = "vini_license_key"
    private let hwidKey = "vini_hwid"
    private let authTokenKey = "vini_auth_token"
    private let usernameKey = "vini_username"
    
    // MARK: - Save
    
    func saveLicenseKey(_ value: String) {
        save(key: licenseKeyKey, value: value)
    }
    
    func saveHWID(_ value: String) {
        save(key: hwidKey, value: value)
    }
    
    func saveAuthToken(_ value: String) {
        save(key: authTokenKey, value: value)
    }
    
    func saveUsername(_ value: String) {
        save(key: usernameKey, value: value)
    }
    
    // MARK: - Load
    
    func loadLicenseKey() -> String? {
        return load(key: licenseKeyKey)
    }
    
    func loadHWID() -> String? {
        return load(key: hwidKey)
    }
    
    func loadAuthToken() -> String? {
        return load(key: authTokenKey)
    }
    
    func loadUsername() -> String? {
        return load(key: usernameKey)
    }
    
    // MARK: - Delete
    
    func deleteAll() {
        delete(key: licenseKeyKey)
        delete(key: hwidKey)
        delete(key: authTokenKey)
        delete(key: usernameKey)
    }
    
    func deleteAuthToken() {
        delete(key: authTokenKey)
    }
    
    // MARK: - Generate Persistent HWID
    // Genera un UUID y lo guarda en Keychain.
    // Este UUID NO cambia al reinstalar la app.
    
    func getOrCreatePersistentHWID() -> String {
        if let existing = loadHWID() {
            return existing
        }
        
        // Generar nuevo HWID persistente
        let newHWID = UUID().uuidString
        saveHWID(newHWID)
        return newHWID
    }
    
    // MARK: - Check if has saved credentials
    
    func hasSavedCredentials() -> Bool {
        return loadLicenseKey() != nil
    }
    
    // MARK: - Private helpers
    
    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        // Delete existing
        delete(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
