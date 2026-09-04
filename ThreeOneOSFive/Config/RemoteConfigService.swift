import Foundation

// MARK: - Remote Config Service
// Obtiene configuración remota desde el Worker V2.
// Permite al admin controlar valores sin modificar la IPA.

final class RemoteConfigService: ObservableObject {
    static let shared = RemoteConfigService()
    
    @Published var config: RemoteConfig = RemoteConfig()
    @Published var isLoading = false
    
    private let workerURL = "https://vini-v2-api.loboangel39.workers.dev"
    
    init() {}
    
    /// GET /api/app/config — obtener configuración remota
    func fetchConfig() async {
        isLoading = true
        
        let url = URL(string: "\(workerURL)/api/app/config")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        if let token = UserDefaults.standard.string(forKey: "vini.authToken") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                await MainActor.run { self.isLoading = false }
                return
            }
            
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            let remoteConfig = RemoteConfig(from: decoded)
            
            await MainActor.run {
                self.config = remoteConfig
                self.isLoading = false
            }
        } catch {
            print("[RemoteConfig] Error: \(error.localizedDescription)")
            await MainActor.run { self.isLoading = false }
        }
    }
    
    /// POST /api/app/telemetry — enviar telemetría al servidor
    func sendTelemetry(action: String, metadata: [String: String] = [:]) async {
        let url = URL(string: "\(workerURL)/api/app/telemetry")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        
        if let token = UserDefaults.standard.string(forKey: "vini.authToken") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        var body: [String: String] = ["action": action]
        body.merge(metadata) { _, new in new }
        
        request.httpBody = try? JSONEncoder().encode(body)
        
        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            print("[RemoteConfig] Telemetry failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Config Model

struct RemoteConfig {
    var appName: String = "VINI V2"
    var maintenanceMode: Bool = false
    var patchesEnabled: Bool = true
    var messagesEnabled: Bool = true
    var maxDownloadsPerDay: Int = 100
    var minimumVersion: String = "1.0.0"
    
    init() {}
    
    init(from dict: [String: String]) {
        appName = dict["app_name"] ?? "VINI V2"
        maintenanceMode = dict["maintenance_mode"] == "1"
        patchesEnabled = dict["patches_enabled"] != "0"
        messagesEnabled = dict["messages_enabled"] != "0"
        maxDownloadsPerDay = Int(dict["max_downloads_per_day"] ?? "100") ?? 100
        minimumVersion = dict["minimum_version"] ?? "1.0.0"
    }
}
