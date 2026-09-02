import Foundation
import Security

// MARK: - Keychain Manager

/// Securely stores license and session data in iOS Keychain.
/// Persists across app reinstalls as long as the device identifierForVendor remains the same.
/// The license is bound to the device's hardware ID, preventing transfer to other devices.
final class KeychainManager {
    static let shared = KeychainManager()

    private let serviceName = "com.vini.license"

    // MARK: - Keys

    private enum Keys {
        static let licenseKey = "license_key"
        static let authToken = "auth_token"
        static let hwid = "device_hwid"
        static let expiresAt = "license_expires_at"
        static let deviceBound = "device_bound"
    }

    // MARK: - Save

    func saveLicense(key: String, token: String, expiresAt: Date) {
        save(key: Keys.licenseKey, value: key)
        save(key: Keys.authToken, value: token)
        save(key: Keys.expiresAt, value: expiresAt.timeIntervalSince1970.description)
        save(key: Keys.deviceBound, value: "true")

        // Store the HWID that was used
        if let hwid = currentHWID {
            save(key: Keys.hwid, value: hwid)
        }

        log("keychain: license saved (bound to device)")
    }

    func saveAuthToken(_ token: String) {
        save(key: Keys.authToken, value: token)
    }

    // MARK: - Load

    func loadLicenseKey() -> String? {
        load(key: Keys.licenseKey)
    }

    func loadAuthToken() -> String? {
        load(key: Keys.authToken)
    }

    func loadExpiresAt() -> Date? {
        guard let str = load(key: Keys.expiresAt),
              let interval = Double(str) else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    func loadBoundHWID() -> String? {
        load(key: Keys.hwid)
    }

    func isDeviceBound() -> Bool {
        load(key: Keys.deviceBound) == "true"
    }

    // MARK: - Validation

    /// Checks if the stored license is still valid (not expired).
    func isLicenseValid() -> Bool {
        guard let expiresAt = loadExpiresAt() else { return false }
        return Date() < expiresAt
    }

    /// Checks if the current device matches the bound HWID.
    func validateDeviceBinding() -> Bool {
        guard let boundHWID = loadBoundHWID() else { return false }
        return boundHWID == currentHWID
    }

    // MARK: - Clear

    func clearAll() {
        delete(key: Keys.licenseKey)
        delete(key: Keys.authToken)
        delete(key: Keys.hwid)
        delete(key: Keys.expiresAt)
        delete(key: Keys.deviceBound)
        log("keychain: all data cleared")
    }

    func clearSession() {
        delete(key: Keys.authToken)
        log("keychain: session cleared")
    }

    // MARK: - Private Methods

    private var currentHWID: String? {
        // Use identifierForVendor which persists across reinstalls
        // as long as no apps from the same vendor remain installed
        return UIDevice.current.identifierForVendor?.uuidString
    }

    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            log("keychain: save failed for \(key) — status \(status)")
        }
    }

    private func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
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
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - License Session Manager

/// Manages the license session lifecycle, combining Keychain storage with remote validation.
final class LicenseSessionManager: ObservableObject {
    static let shared = LicenseSessionManager()

    @Published var isLoggedIn = false
    @Published var licenseKey: String?
    @Published var expiresAt: Date?
    @Published var validationError: String?

    private let keychain = KeychainManager.shared
    private let remoteService = RemotePatchService.shared

    init() {
        restoreSession()
    }

    /// Restores a session from Keychain on app launch.
    func restoreSession() {
        // Check if we have a stored license
        guard let storedKey = keychain.loadLicenseKey() else {
            isLoggedIn = false
            return
        }

        // Validate device binding
        guard keychain.validateDeviceBinding() else {
            log("session: device binding mismatch — clearing session")
            keychain.clearAll()
            isLoggedIn = false
            return
        }

        // Check expiration
        guard keychain.isLicenseValid() else {
            log("session: license expired — clearing session")
            keychain.clearAll()
            isLoggedIn = false
            return
        }

        // Restore session state
        licenseKey = storedKey
        expiresAt = keychain.loadExpiresAt()
        isLoggedIn = true

        // Restore auth token for remote service
        if let token = keychain.loadAuthToken() {
            UserDefaults.standard.set(token, forKey: "remotePatch.authToken")
        }

        log("session: restored from keychain")
    }

    /// Logs in with a license key, validating against the remote server.
    func login(licenseKey: String) async throws {
        let hwid = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"

        // Validate with remote server
        let response = try await remoteService.validateLicense(key: licenseKey)

        guard response.valid else {
            throw LicenseError.invalidLicense(response.error ?? "Unknown error")
        }

        // Parse expiration
        var expiration: Date? = nil
        if let expiresStr = response.expiresAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            expiration = formatter.date(from: expiresStr)
        }

        // Save to Keychain (device-bound)
        if let token = response.token, let exp = expiration {
            keychain.saveLicense(key: licenseKey, token: token, expiresAt: exp)
        }

        // Update state
        await MainActor.run {
            self.licenseKey = licenseKey
            self.expiresAt = expiration
            self.isLoggedIn = true
            self.validationError = nil
        }

        log("session: login successful")
    }

    /// Logs out and clears all session data.
    func logout() {
        keychain.clearAll()
        remoteService.clearSession()

        licenseKey = nil
        expiresAt = nil
        isLoggedIn = false

        log("session: logged out")
    }

    /// Re-validates the session against the remote server.
    func revalidateSession() async {
        guard isLoggedIn else { return }

        let valid = await remoteService.verifySession()
        if !valid {
            await MainActor.run {
                self.logout()
                self.validationError = "Sesión invalidada por el servidor"
            }
            log("session: remote validation failed")
        }
    }
}

// MARK: - Errors

enum LicenseError: LocalizedError {
    case invalidLicense(String)
    case deviceMismatch
    case expired

    var errorDescription: String? {
        switch self {
        case .invalidLicense(let msg): return "Licencia inválida: \(msg)"
        case .deviceMismatch: return "Esta licencia está vinculada a otro dispositivo"
        case .expired: return "La licencia ha expirado"
        }
    }
}
