import Foundation

// MARK: - Message Service
// Consulta mensajes desde el Worker V2 y gestiona ACKs.

final class MessageService: ObservableObject {
    static let shared = MessageService()
    
    @Published var messages: [RemoteMessage] = []
    @Published var isLoading = false
    
    private let workerURL = "https://vini-v2-api.loboangel39.workers.dev"
    
    init() {}
    
    /// GET /api/app/messages — obtener mensajes activos para el usuario
    func fetchMessages() async {
        isLoading = true
        
        let url = URL(string: "\(workerURL)/api/app/messages")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        if let token = KeychainManager.shared.loadAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                await MainActor.run { self.isLoading = false }
                return
            }
            
            let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
            
            await MainActor.run {
                self.messages = decoded.messages
                self.isLoading = false
            }
        } catch {
            print("[MessageService] Error: \(error.localizedDescription)")
            await MainActor.run { self.isLoading = false }
        }
    }
    
    /// POST /api/app/messages/:id/ack — marcar mensaje como leído
    func acknowledgeMessage(_ messageId: String) async {
        let url = URL(string: "\(workerURL)/api/app/messages/\(messageId)/ack")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        
        if let token = KeychainManager.shared.loadAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                print("[MessageService] ACK sent for message \(messageId)")
            }
        } catch {
            print("[MessageService] ACK failed: \(error.localizedDescription)")
        }
    }
    
    /// Número de mensajes no leídos (para badge)
    var unreadCount: Int {
        messages.count
    }
}

// MARK: - Models

struct RemoteMessage: Codable, Identifiable {
    let id: String
    let title: String
    let content: String
    let type: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, type
        case createdAt = "created_at"
    }
    
    var iconName: String {
        switch type {
        case "warning": return "exclamationmark.triangle.fill"
        case "error": return "xmark.octagon.fill"
        case "success": return "checkmark.circle.fill"
        case "update": return "arrow.up.circle.fill"
        default: return "info.circle.fill"
        }
    }
    
    var color: String {
        switch type {
        case "warning": return "orange"
        case "error": return "red"
        case "success": return "green"
        case "update": return "blue"
        default: return "gray"
        }
    }
}

struct MessagesResponse: Codable {
    let messages: [RemoteMessage]
}
