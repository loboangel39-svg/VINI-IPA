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
            log("[PATCH] catalog request")
            let catalog = try await RemotePatchService.shared.fetchAvailablePatches()
            patches = catalog.filter { $0.type.lowercased() == "3105" || $0.name.lowercased().hasSuffix(".3105") }
            log("[PATCH] catalog result count=\(catalog.count), valid3105=\(patches.count)")
            for patch in patches {
                guard importingID == nil else { break }
                importingID = patch.id
                while store.isBusy {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                log("[PATCH] download started id=\(patch.id)")
                let data = try await PatchDownloadService.shared.downloadPackageData(patchId: patch.id)
                log("[PATCH] download completed id=\(patch.id) bytes=\(data.count)")
                guard let summary = try? PatchPackageCodec.inspect(data) else {
                    log("[PATCH] package inspection rejected id=\(patch.id)")
                    importingID = nil
                    continue
                }
                log("[PATCH] package inspection accepted id=\(patch.id) package=\(summary.packageID.uuidString)")
                let existing = PatchProjectLibrary.load().contains { $0.id == summary.packageID }
                if existing {
                    log("[PATCH] duplicate skipped package=\(summary.packageID.uuidString)")
                } else if store.importPackage(data: data) {
                    while store.isBusy {
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    store.reload()
                    if store.passwordRequest != nil {
                        log("[PATCH] import pending password package=\(summary.packageID.uuidString)")
                    } else {
                        log("[PATCH] import completed package=\(summary.packageID.uuidString) installedCount=\(store.items.count)")
                    }
                } else {
                    log("[PATCH] import not started package=\(summary.packageID.uuidString)")
                }
                importingID = nil
            }
            errorMessage = nil
        } catch {
            log("[PATCH] synchronization failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}
