import Foundation

// MARK: - Token Refresh Manager
// Maneja el auto-refresh del token JWT.
// Cuando el servidor detecta que el token está cerca de expirar o expiró
// (pero dentro del período de gracia), lo renueva y lo envía en el header
// X-New-Token de la respuesta.
//
// Este manager lee ese header y actualiza el token en el Keychain
// de forma transparente para el usuario.

final class TokenRefreshManager {
    static let shared = TokenRefreshManager()
    
    private init() {}
    
    /// Procesa la respuesta HTTP y si contiene un nuevo token, lo guarda en el Keychain.
    /// Debe llamarse después de cada request exitoso a la API.
    func handleTokenRefresh(from response: HTTPURLResponse) {
        guard let newToken = response.value(forHTTPHeaderField: "X-New-Token"),
              !newToken.isEmpty else {
            return
        }
        
        // Guardar nuevo token en Keychain
        guard KeychainManager.shared.saveAuthToken(newToken) else { return }
        if let expiration = Self.expirationDate(of: newToken) {
            NotificationCenter.default.post(
                name: .accessTokenDidRefresh,
                object: nil,
                userInfo: ["expiresAt": expiration]
            )
        }
        
        print("[TokenRefresh] Token renovado automáticamente")
    }

    private static func expirationDate(of token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let data = Data(base64Encoded: String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp / 1000)
    }
    
    /// Versión async para usar con URLSession.data()
    func handleTokenRefresh(from response: URLResponse) {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        handleTokenRefresh(from: httpResponse)
    }
}

extension Notification.Name {
    static let accessTokenDidRefresh = Notification.Name("accessTokenDidRefresh")
}
