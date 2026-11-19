import SwiftUI

struct RemotePatchImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PatchProjectStore
    @StateObject private var coordinator = RemotePatchImportCoordinator()
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.isLoading && coordinator.patches.isEmpty {
                    ProgressView()
                } else if coordinator.patches.isEmpty {
                    ContentUnavailableView("No patches available", systemImage: "shippingbox")
                } else {
                    List(coordinator.patches) { patch in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(patch.name).font(.headline)
                                Text("v\(patch.version)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await coordinator.importPatch(patch, into: store) }
                            } label: {
                                if coordinator.importingID == patch.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                }
                            }
                            .disabled(coordinator.importingID != nil || store.isBusy)
                        }
                    }
                }
            }
            .navigationTitle("Remote Patches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await coordinator.loadCatalog() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(coordinator.isLoading)
                }
            }
            .task {
                if KeychainManager.shared.loadAuthToken() == nil { showLogin = true }
                else { await coordinator.loadCatalog() }
            }
            .sheet(isPresented: $showLogin) {
                LoginView { _, _ in
                    showLogin = false
                    Task { await coordinator.loadCatalog() }
                }
            }
            .alert("Remote import failed", isPresented: Binding(
                get: { coordinator.errorMessage != nil },
                set: { if !$0 { coordinator.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { coordinator.errorMessage = nil }
            } message: {
                Text(coordinator.errorMessage ?? "Unknown error")
            }
        }
    }
}
