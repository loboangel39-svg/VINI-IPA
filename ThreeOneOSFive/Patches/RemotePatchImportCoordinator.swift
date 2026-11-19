import Foundation

@MainActor
final class RemotePatchImportCoordinator: ObservableObject {
    @Published private(set) var patches: [RemotePatchInfo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var importingID: String?
    @Published var errorMessage: String?

    func loadCatalog() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            patches = try await RemotePatchService.shared.fetchAvailablePatches()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importPatch(_ patch: RemotePatchInfo, into store: PatchProjectStore) async {
        guard importingID == nil else { return }
        importingID = patch.id
        defer { importingID = nil }
        do {
            let data = try await PatchDownloadService.shared.downloadPackageData(patchId: patch.id)
            guard store.importPackage(data: data) else {
                throw RemotePatchError.networkError
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Synchronizes only valid .3105 packages through the original importer.
    /// A failed catalog/download never removes or replaces local projects.
    func sync(into store: PatchProjectStore) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let catalog = try await RemotePatchService.shared.fetchAvailablePatches()
            patches = catalog.filter { $0.type.lowercased() == "3105" || $0.name.lowercased().hasSuffix(".3105") }
            for patch in patches {
                guard importingID == nil else { break }
                importingID = patch.id
                let data = try await PatchDownloadService.shared.downloadPackageData(patchId: patch.id)
                guard let summary = try? PatchPackageCodec.inspect(data) else {
                    importingID = nil
                    continue
                }
                let existing = PatchProjectLibrary.load().contains { $0.id == summary.packageID }
                if !existing { _ = store.importPackage(data: data) }
                importingID = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
