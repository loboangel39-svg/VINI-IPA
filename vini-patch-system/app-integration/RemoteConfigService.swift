import Foundation
import SwiftUI
import Combine

// MARK: - Remote Config Models

struct RemoteConfig: Codable {
    var featureFlags: [String: Bool]
    var settings: [String: String]
    var messages: [RemoteMessage]
    var timestamp: String?

    init(featureFlags: [String: Bool] = [:], settings: [String: String] = [:], messages: [RemoteMessage] = [], timestamp: String? = nil) {
        self.featureFlags = featureFlags
        self.settings = settings
        self.messages = messages
        self.timestamp = timestamp
    }
}

struct RemoteMessage: Identifiable, Codable {
    let id: String
    let title: String
    let content: String
    let type: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, content, type
        case createdAt = "created_at"
    }

    var messageType: MessageType {
        MessageType(rawValue: type) ?? .info
    }

    enum MessageType: String {
        case info
        case warning
        case error
        case success
        case update
    }
}

// MARK: - Remote Config Service

/// Fetches and caches remote configuration from the Worker API.
/// Provides feature flags, app settings, and broadcast messages.
/// Polls periodically to keep config fresh without requiring app reinstall.
final class RemoteConfigService: ObservableObject {
    static let shared = RemoteConfigService()

    @Published var config = RemoteConfig()
    @Published var unreadMessages: [RemoteMessage] = []
    @Published var lastFetchDate: Date?
    @Published var isFetching = false

    private var timer: Timer?
    private let fetchInterval: TimeInterval = 300 // 5 minutes

    init() {
        loadCachedConfig()
        startAutoFetch()
    }

    // MARK: - Feature Flags

    func isFeatureEnabled(_ flag: String) -> Bool {
        config.featureFlags[flag] ?? false
    }

    func featureValue<T>(_ flag: String, default: T) -> T {
        // For simple bool flags
        if let boolVal = config.featureFlags[flag] as? T {
            return boolVal
        }
        return `default`
    }

    // MARK: - Settings

    func settingValue(_ key: String) -> String? {
        config.settings[key]
    }

    func settingValue<T>(_ key: String, default: T) -> T {
        if let strVal = config.settings[key] {
            // Try to convert string to requested type
            if T.self == Int.self, let intVal = Int(strVal) as? T {
                return intVal
            }
            if T.self == Double.self, let doubleVal = Double(strVal) as? T {
                return doubleVal
            }
            if T.self == Bool.self, let boolVal = Bool(strVal) as? T {
                return boolVal
            }
            if T.self == String.self {
                return strVal as! T
            }
        }
        return `default`
    }

    // MARK: - Messages

    func hasUnreadMessages() -> Bool {
        !unreadMessages.isEmpty
    }

    func acknowledgeMessage(_ message: RemoteMessage) {
        Task {
            do {
                let token = RemotePatchService.shared.authToken
                guard let token = token else { return }

                var request = URLRequest(url: URL(string: "\(RemotePatchService.shared.baseURL)/api/app/messages/\(message.id)/ack")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    await MainActor.run {
                        self.unreadMessages.removeAll { $0.id == message.id }
                    }
                }
            } catch {
                log("config: failed to ack message — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Fetch

    func fetchConfig() async {
        guard !isFetching else { return }
        isFetching = true

        do {
            let token = RemotePatchService.shared.authToken
            guard let token = token else {
                isFetching = false
                return
            }

            var request = URLRequest(url: URL(string: "\(RemotePatchService.shared.baseURL)/api/app/config")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                isFetching = false
                return
            }

            let newConfig = try JSONDecoder().decode(RemoteConfig.self, from: data)

            await MainActor.run {
                self.config = newConfig
                self.unreadMessages = newConfig.messages
                self.lastFetchDate = Date()
                self.isFetching = false
            }

            // Cache to disk
            cacheConfig(newConfig)

            log("config: fetched — \(newConfig.featureFlags.count) flags, \(newConfig.messages.count) messages")
        } catch {
            await MainActor.run {
                self.isFetching = false
            }
            log("config: fetch failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Telemetry

    func sendTelemetry(eventType: String, eventData: [String: Any] = [:]) {
        Task {
            do {
                let token = RemotePatchService.shared.authToken
                guard let token = token else { return }

                var request = URLRequest(url: URL(string: "\(RemotePatchService.shared.baseURL)/api/app/telemetry")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                    "eventType": eventType,
                    "eventData": eventData,
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let _ = try await URLSession.shared.data(for: request)
            } catch {
                // Silently fail — telemetry is best-effort
            }
        }
    }

    // MARK: - Auto-fetch

    private func startAutoFetch() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: fetchInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchConfig()
            }
        }
    }

    func stopAutoFetch() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Cache

    private func cacheConfig(_ config: RemoteConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "remoteConfig.cached")
        }
    }

    private func loadCachedConfig() {
        if let data = UserDefaults.standard.data(forKey: "remoteConfig.cached"),
           let cached = try? JSONDecoder().decode(RemoteConfig.self, from: data) {
            config = cached
        }
    }
}

// MARK: - Remote Message Banner View

/// Displays a banner for unread remote messages.
struct RemoteMessageBanner: View {
    let message: RemoteMessage
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.headline)
                Text(message.content)
                    .font(.subheadline)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    private var iconName: String {
        switch message.messageType {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .success: return "checkmark.circle.fill"
        case .update: return "arrow.up.circle.fill"
        }
    }

    private var iconColor: Color {
        switch message.messageType {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        case .update: return .purple
        }
    }

    private var backgroundColor: Color {
        switch message.messageType {
        case .info: return Color.blue.opacity(0.1)
        case .warning: return Color.orange.opacity(0.1)
        case .error: return Color.red.opacity(0.1)
        case .success: return Color.green.opacity(0.1)
        case .update: return Color.purple.opacity(0.1)
        }
    }
}

// MARK: - Feature Flag View Modifier

/// Conditionally shows/hides views based on remote feature flags.
struct FeatureFlagModifier: ViewModifier {
    let flag: String
    @ObservedObject var configService = RemoteConfigService.shared

    func body(content: Content) -> some View {
        if configService.isFeatureEnabled(flag) {
            content
        }
    }
}

extension View {
    func featureFlag(_ flag: String) -> some View {
        modifier(FeatureFlagModifier(flag: flag))
    }
}
