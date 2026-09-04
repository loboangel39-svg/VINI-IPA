import SwiftUI

// MARK: - Config View
// Muestra la configuración remota obtenida del servidor.

struct ConfigView: View {
    @StateObject private var configService = RemoteConfigService.shared
    
    var body: some View {
        NavigationStack {
            List {
                // Status Section
                Section {
                    configRow(
                        icon: "server.rack",
                        title: "Server",
                        value: configService.config.appName,
                        color: .blue
                    )
                    configRow(
                        icon: configService.config.maintenanceMode ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        title: "Maintenance Mode",
                        value: configService.config.maintenanceMode ? "Active" : "Inactive",
                        color: configService.config.maintenanceMode ? .orange : .green
                    )
                } header: {
                    Text("Server Status")
                }
                
                // Features Section
                Section {
                    configRow(
                        icon: "shippingbox.fill",
                        title: "Patches",
                        value: configService.config.patchesEnabled ? "Enabled" : "Disabled",
                        color: configService.config.patchesEnabled ? .green : .red
                    )
                    configRow(
                        icon: "bubble.left.fill",
                        title: "Messages",
                        value: configService.config.messagesEnabled ? "Enabled" : "Disabled",
                        color: configService.config.messagesEnabled ? .green : .red
                    )
                } header: {
                    Text("Features")
                }
                
                // Limits Section
                Section {
                    configRow(
                        icon: "arrow.down.circle.fill",
                        title: "Max Downloads/Day",
                        value: "\(configService.config.maxDownloadsPerDay)",
                        color: .purple
                    )
                    configRow(
                        icon: "tag.fill",
                        title: "Min Version",
                        value: configService.config.minimumVersion,
                        color: .gray
                    )
                } header: {
                    Text("Limits")
                }
                
                // Session Section
                Section {
                    if let username = UserDefaults.standard.string(forKey: "vini.username") {
                        configRow(
                            icon: "person.fill",
                            title: "Logged in as",
                            value: username,
                            color: .blue
                        )
                    }
                    configRow(
                        icon: "key.fill",
                        title: "HWID",
                        value: hwidDisplay,
                        color: .gray
                    )
                } header: {
                    Text("Session")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Config")
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
        return "Simulator"
        #else
        let hwid = UIDevice.current.identifierForVendor?.uuidString ?? "Unknown"
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
