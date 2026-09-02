import SwiftUI

// MARK: - Remote Patches View

/// Displays patches available from the remote server, with download/update actions.
/// Add this as a new tab or section in ContentView.swift.
struct RemotePatchesView: View {
    @StateObject private var viewModel = RemotePatchesViewModel()
    @StateObject private var syncService = PatchSyncService.shared
    @Environment(\.appLanguage) private var language

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading && viewModel.patches.isEmpty {
                    loadingView
                } else if viewModel.patches.isEmpty {
                    emptyView
                } else {
                    patchesList
                }
            }
            .navigationTitle("Patches Remotos")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await viewModel.loadPatches() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                await viewModel.loadPatches()
            }
        }
        .task {
            await viewModel.loadPatches()
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Cargando patches...")
                .foregroundColor(.secondary)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No hay patches disponibles")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Tu cuenta no tiene patches asignados.\nContacta al administrador.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var patchesList: some View {
        List {
            // Updates section
            if !syncService.patchesWithUpdates.isEmpty {
                Section(header: Text("Actualizaciones Disponibles")) {
                    ForEach(syncService.patchesWithUpdates) { patch in
                        patchRow(patch, hasUpdate: true)
                    }
                }
            }

            // New patches section
            if !syncService.newPatches.isEmpty {
                Section(header: Text("Nuevos Patches")) {
                    ForEach(syncService.newPatches) { patch in
                        patchRow(patch, hasUpdate: false)
                    }
                }
            }

            // Already downloaded section
            let downloaded = viewModel.patches.filter { syncService.isDownloaded($0.id) }
            if !downloaded.isEmpty {
                Section(header: Text("Descargados")) {
                    ForEach(downloaded) { patch in
                        patchRow(patch, hasUpdate: false)
                    }
                }
            }

            // Sync info footer
            Section {
                if let lastSync = syncService.lastSyncDate {
                    Text("Última sincronización: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func patchRow(_ patch: RemotePatch, hasUpdate: Bool) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: hasUpdate ? "arrow.down.circle.fill" : "puzzlepiece.extension.fill")
                .font(.title2)
                .foregroundColor(hasUpdate ? .orange : .purple)
                .frame(width: 40, height: 40)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(patch.name)
                        .font(.headline)
                    if hasUpdate {
                        Text("UPDATE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
                Text(patch.bundleId)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("v\(patch.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !patch.description.isEmpty {
                    Text(patch.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Action button
            if viewModel.downloadingPatchId == patch.id {
                ProgressView()
                    .scaleEffect(0.8)
            } else if hasUpdate {
                Button(action: { Task { await viewModel.updatePatch(patch) } }) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                }
            } else if !syncService.isDownloaded(patch.id) {
                Button(action: { Task { await viewModel.downloadPatch(patch) } }) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundColor(.purple)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Remote Patches Dashboard Card

/// A compact card for the Home dashboard showing remote patch status.
struct RemotePatchesDashboardCard: View {
    @ObservedObject var syncService: PatchSyncService
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "cloud.download")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.purple)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Patches Remotos")
                        .font(.headline)
                        .foregroundColor(.primary)
                    HStack(spacing: 8) {
                        if !syncService.newPatches.isEmpty {
                            Label("\(syncService.newPatches.count) nuevos", systemImage: "plus.circle")
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                        if !syncService.patchesWithUpdates.isEmpty {
                            Label("\(syncService.patchesWithUpdates.count) actualizaciones", systemImage: "arrow.up.circle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        if syncService.newPatches.isEmpty && syncService.patchesWithUpdates.isEmpty {
                            Text("Al día")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }
}
