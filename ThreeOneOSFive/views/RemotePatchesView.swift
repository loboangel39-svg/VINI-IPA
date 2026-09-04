import SwiftUI

// MARK: - Remote Patches View
// Muestra los patches remotos disponibles para el usuario.
// Permite descargar, re-descargar y actualizar patches.
// REGLA: Descargar nuevamente SIEMPRE es posible. No se bloquea por descargas anteriores.

struct RemotePatchesView: View {
    @StateObject private var patchManager = PatchManager.shared
    
    var body: some View {
        NavigationStack {
            Group {
                if patchManager.isSyncing && patchManager.availablePatches.isEmpty {
                    ProgressView("Loading patches...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if patchManager.availablePatches.isEmpty {
                    emptyState
                } else {
                    patchesList
                }
            }
            .navigationTitle("Remote Patches")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await patchManager.syncPatches()
            }
            .refreshable {
                await patchManager.syncPatches()
            }
        }
    }
    
    private var patchesList: some View {
        List {
            ForEach(patchManager.availablePatches) { patch in
                PatchRow(patch: patch)
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No patches available")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Patches assigned by the admin will appear here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Patch Row

private struct PatchRow: View {
    let patch: RemotePatchInfo
    @StateObject private var patchManager = PatchManager.shared
    
    var body: some View {
        let isDownloaded = patchManager.isDownloaded(patch.id)
        let hasUpdate = patchManager.hasUpdate(patch)
        let isDownloading = patchManager.downloadingPatchIds.contains(patch.id)
        let progress = patchManager.downloadProgress[patch.id]
        
        HStack(spacing: 12) {
            // Icon
            Image(systemName: isDownloaded ? (hasUpdate ? "arrow.down.circle.fill" : "checkmark.circle.fill") : "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(isDownloaded ? (hasUpdate ? .orange : .green) : .blue)
                .frame(width: 32)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(patch.name)
                        .font(.headline)
                    
                    if hasUpdate {
                        Text("UPDATE")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                
                if !patch.description.isEmpty {
                    Text(patch.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 8) {
                    Text("v\(patch.version)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                    
                    if let localVersion = patchManager.localVersion(patch.id), isDownloaded {
                        Text("Local: v\(localVersion)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    
                    if let type = patch.type as String? {
                        typeBadge(type)
                    }
                }
                
                if isDownloading, let progress = progress {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(progress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Action button
            if !isDownloading {
                Button {
                    Task {
                        await patchManager.forceRedownload(patch)
                    }
                } label: {
                    Image(systemName: isDownloaded ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if isDownloaded {
                Button(role: .destructive) {
                    patchManager.deleteLocalPatch(patch.id)
                } label: {
                    Label("Delete Local Copy", systemImage: "trash")
                }
            }
            Button {
                Task {
                    await patchManager.forceRedownload(patch)
                }
            } label: {
                Label(isDownloaded ? "Re-download" : "Download", systemImage: "arrow.down.circle")
            }
        }
    }
    
    @ViewBuilder
    private func typeBadge(_ type: String) -> some View {
        let (text, color): (String, Color) = {
            switch type {
            case "premium": return ("Premium", .yellow)
            case "exclusive": return ("Exclusive", .red)
            default: return ("Free", .blue)
            }
        }()
        
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
