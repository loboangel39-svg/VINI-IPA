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
}
