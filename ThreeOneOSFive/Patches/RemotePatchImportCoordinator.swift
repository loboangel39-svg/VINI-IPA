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
            let download = try await PatchDownloadService.shared.downloadPackageData(patchId: patch.id)
            let summary = try PatchPackageCodec.inspect(download.data)
            if let contentKey = download.contentKey {
                try PatchKeyStore.store(contentKey, for: summary)
            }
            guard store.importPackage(data: download.data) else {
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
            let authorizedPatchIDs = Set(catalog.map(\.id))
            _ = PatchProjectLibrary.migrateLegacyRemoteOrigins()
            patches = catalog.filter {
                let fileKey = $0.fileKey?.split(separator: "?").first.map(String.init)?.lowercased() ?? ""
                let fileName = fileKey.split(separator: "/").last.map(String.init) ?? fileKey
                return fileName.hasSuffix(".3105") || $0.type.lowercased() == "3105" || $0.name.lowercased().hasSuffix(".3105")
            }
            log("[PATCH] catalog result count=\(catalog.count), valid3105=\(patches.count)")
            store.removeRevokedRemotePackages(authorizedPatchIDs: authorizedPatchIDs)
            for patch in patches {
                guard importingID == nil else { break }
                importingID = patch.id
                while store.isBusy {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                log("[PATCH] download started id=\(patch.id)")
                let download = try await PatchDownloadService.shared.downloadPackageData(patchId: patch.id)
                let data = download.data
                log("[PATCH] download completed id=\(patch.id) bytes=\(data.count) contentKey=\(download.contentKey != nil)")
                guard let summary = try? PatchPackageCodec.inspect(data) else {
                    log("[PATCH] package inspection rejected id=\(patch.id)")
                    importingID = nil
                    continue
                }
                log("[PATCH] package inspection accepted id=\(patch.id) package=\(summary.packageID.uuidString)")
                log("[PATCH] import packageID=\(summary.packageID.uuidString) library count before=\(store.items.count)")
                if let contentKey = download.contentKey {
                    do {
                        try PatchKeyStore.store(contentKey, for: summary)
                        log("[PATCH] content key stored for package=\(summary.packageID.uuidString)")
                    } catch {
                        log("[PATCH] content key rejected for package=\(summary.packageID.uuidString)")
                    }
                }
                let existing = PatchProjectLibrary.load().contains { $0.id == summary.packageID }
                if existing {
                    log("[PATCH] duplicate skipped package=\(summary.packageID.uuidString)")
                    _ = PatchProjectLibrary.updateRemoteOrigin(
                        for: summary.packageID,
                        expectedSummary: summary,
                        remotePatchID: patch.id
                    )
                } else if store.importPackage(
                    data: data,
                    origin: PatchPackageOrigin(
                        repositoryName: "VINI Remote",
                        repositoryURL: URL(string: "https://vini-v2-api.loboangel39.workers.dev")!,
                        packageIdentifier: patch.id,
                        remotePatchID: patch.id
                    ),
                    allowTargetOverlap: true,
                    showSuccessAlert: false
                ) {
                    while store.isBusy {
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    store.reload()
                    log("[PATCH] library count after=\(store.items.count) unique packageIDs=\(Set(store.items.map(\.id)).count)")
                    if store.lastImportSucceeded == false {
                        log("[PATCH] import result=failed package=\(summary.packageID.uuidString)")
                    } else if store.passwordRequest != nil {
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
