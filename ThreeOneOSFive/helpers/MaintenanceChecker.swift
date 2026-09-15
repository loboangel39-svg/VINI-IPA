import Foundation

/// Checks maintenance mode status from the Cloudflare worker
enum MaintenanceChecker {
    /// Worker base URL
    private static let workerBaseURL = "https://vini-v2-api.loboangel39.workers.dev"
    
    struct StatusResponse: Decodable {
        let maintenance: Bool
        let message: String
        let eta: String?
        let timestamp: String
    }
    
    /// Check if the app is in maintenance mode
    /// - Returns: StatusResponse with maintenance flag and message, or nil if check fails
    static func check() async -> StatusResponse? {
        guard let url = URL(string: "\(workerBaseURL)/api/app/status") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode(StatusResponse.self, from: data)
        } catch {
            log("maintenance: check failed - \(error.localizedDescription)")
            return nil
        }
    }
}
