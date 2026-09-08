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
        KeychainManager.shared.saveAuthToken(newToken)
        
        print("[TokenRefresh] Token renovado automáticamente")
    }
    
    /// Versión async para usar con URLSession.data()
    func handleTokenRefresh(from response: URLResponse) {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        handleTokenRefresh(from: httpResponse)
    }
}
