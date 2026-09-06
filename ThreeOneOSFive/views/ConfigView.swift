import SwiftUI

// MARK: - Config View
// Muestra la configuración remota obtenida del servidor.

struct ConfigView: View {
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @StateObject private var configService = RemoteConfigService.shared
    
    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .english }
    
    var body: some View {
        NavigationStack {
            List {
                // Status Section
                Section {
                    configRow(
                        icon: "server.rack",
                        title: language.text("config.server"),
                        value: configService.config.appName,
                        color: .blue
                    )
                    configRow(
                        icon: configService.config.maintenanceMode ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        title: language.text("config.maintenance_mode"),
                        value: configService.config.maintenanceMode ? language.text("config.active") : language.text("config.inactive"),
                        color: configService.config.maintenanceMode ? .orange : .green
                    )
                } header: {
                    Text(language.text("config.server_status"))
                }
                
                // Features Section
                Section {
                    configRow(
                        icon: "shippingbox.fill",
                        title: language.text("config.patches"),
                        value: configService.config.patchesEnabled ? language.text("config.enabled") : language.text("config.disabled"),
                        color: configService.config.patchesEnabled ? .green : .red
                    )
                    configRow(
                        icon: "bubble.left.fill",
                        title: language.text("config.messages"),
                        value: configService.config.messagesEnabled ? language.text("config.enabled") : language.text("config.disabled"),
                        color: configService.config.messagesEnabled ? .green : .red
                    )
                } header: {
                    Text(language.text("config.features"))
                }
                
                // Limits Section
                Section {
                    configRow(
                        icon: "arrow.down.circle.fill",
                        title: language.text("config.max_downloads"),
                        value: "\(configService.config.maxDownloadsPerDay)",
                        color: .purple
                    )
                    configRow(
                        icon: "tag.fill",
                        title: language.text("config.min_version"),
                        value: configService.config.minimumVersion,
                        color: .gray
                    )
                } header: {
                    Text(language.text("config.limits"))
                }
                
                // Session Section
                Section {
                    if let username = UserDefaults.standard.string(forKey: "vini.username") {
                        configRow(
                            icon: "person.fill",
                            title: language.text("config.logged_in_as"),
                            value: username,
                            color: .blue
                        )
                    }
                    configRow(
                        icon: "key.fill",
                        title: language.text("config.hwid"),
                        value: hwidDisplay,
                        color: .gray
                    )
                } header: {
                    Text(language.text("config.session"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(language.text("config.title"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await configService.fetchConfig()
            }
            .refreshable {
                await configService.fetchConfig()
            }
        }
    }
    
    private var hwidDisplay: String {
        #if targetEnvironment(simulator)
        return language.text("config.simulator")
        #else
        let hwid = UIDevice.current.identifierForVendor?.uuidString ?? language.text("config.unknown")
        // Mostrar solo los primeros 8 caracteres
        return String(hwid.prefix(8)) + "..."
        #endif
    }
    
    @ViewBuilder
    private func configRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(title)
                .font(.body)
            
            Spacer()
            
            Text(value)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
