import SwiftUI

// MARK: - Messages View
// Muestra mensajes del servidor (info, warnings, updates, etc.)

struct MessagesView: View {
    @StateObject private var messageService = MessageService.shared
    
    var body: some View {
        NavigationStack {
            Group {
                if messageService.isLoading && messageService.messages.isEmpty {
                    ProgressView("Loading messages...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if messageService.messages.isEmpty {
                    emptyState
                } else {
                    messagesList
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await messageService.fetchMessages()
            }
            .refreshable {
                await messageService.fetchMessages()
            }
        }
    }
    
    private var messagesList: some View {
        List {
            ForEach(messageService.messages) { message in
                MessageRow(message: message)
                    .onAppear {
                        Task {
                            await messageService.acknowledgeMessage(message.id)
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No messages")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Messages from the admin will appear here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Message Row

private struct MessageRow: View {
    let message: RemoteMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(message.title)
                    .font(.headline)
                
                Text(message.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !message.createdAt.isEmpty {
                    Text(formatDate(message.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var iconColor: Color {
        switch message.type {
        case "warning": return .orange
        case "error": return .red
        case "success": return .green
        case "update": return .blue
        default: return .gray
        }
    }
    
    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: isoString) else { return isoString }
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}
