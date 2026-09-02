import Foundation
import SwiftUI

// MARK: - Patch Sync Service

/// Manages synchronization between remote patches (from Worker API) and local patch storage.
/// Handles downloading, version tracking, and auto-update of patches.
final class PatchSyncService: ObservableObject {
    static let shared = PatchSyncService()

    @Published var remotePatches: [RemotePatch] = []
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    /// Tracks which remote patches have been downloaded locally.
    /// Key: remote patch ID, Value: local version string
    private var downloadedVersions: [String: String] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "patchSync.downloadedVersions"),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: "patchSync.downloadedVersions")
            }
        }
    }

    /// Patches that have updates available.
    var patchesWithUpdates: [RemotePatch] {
        let downloaded = downloadedVersions
        return remotePatches.filter { remote in
            if let localVersion = downloaded[remote.id] {
                return AppUpdateChecker.isNewer(remote.version, than: localVersion)
            }
            return false
        }
    }

    /// Patches not yet downloaded.
    var newPatches: [RemotePatch] {
        let downloaded = downloadedVersions
        return remotePatches.filter { !downloaded.keys.contains($0.id) }
    }

    // MARK: - Sync

    /// Performs a full sync: fetches remote patches, checks for updates.
    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil

        do {
            let patches = try await RemotePatchService.shared.fetchAssignedPatches()
            await MainActor.run {
                self.remotePatches = patches
                self.lastSyncDate = Date()
                self.isSyncing = false
            }
            log("sync: completed — \(patches.count) remote patches")
        } catch {
            await MainActor.run {
                self.syncError = error.localizedDescription
                self.isSyncing = false
            }
            log("sync: failed — \(error.localizedDescription)")
        }
    }

    /// Downloads a specific patch and saves it locally.
    func downloadPatch(_ patch: RemotePatch) async throws -> URL {
        log("sync: downloading patch \(patch.name) v\(patch.version)")

        let (data, filename) = try await RemotePatchService.shared.downloadPatch(patchId: patch.id)

        // Save to the app's Documents/RemotePatches directory
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let remotePatchesDir = documentsDir.appendingPathComponent("RemotePatches", isDirectory: true)
        try FileManager.default.createDirectory(at: remotePatchesDir, withIntermediateDirectories: true)

        let fileURL = remotePatchesDir.appendingPathComponent(filename)
        try data.write(to: fileURL)

        // Track the downloaded version
        var versions = downloadedVersions
        versions[patch.id] = patch.version
        downloadedVersions = versions

        log("sync: saved patch to \(fileURL.lastPathComponent)")
        return fileURL
    }

    /// Downloads all new or updated patches.
    func downloadAllUpdates() async {
        let toDownload = newPatches + patchesWithUpdates
        guard !toDownload.isEmpty else {
            log("sync: no patches to download")
            return
        }

        log("sync: downloading \(toDownload.count) patches")
        for patch in toDownload {
            do {
                _ = try await downloadPatch(patch)
            } catch {
                log("sync: failed to download \(patch.name) — \(error.localizedDescription)")
            }
        }
    }

    /// Checks if a remote patch has been downloaded.
    func isDownloaded(_ patchId: String) -> Bool {
        downloadedVersions.keys.contains(patchId)
    }

    /// Gets the local version of a downloaded patch.
    func localVersion(of patchId: String) -> String? {
        downloadedVersions[patchId]
    }

    /// Removes a downloaded patch from local storage.
    func removeLocalPatch(patchId: String) {
        var versions = downloadedVersions
        versions.removeValue(forKey: patchId)
        downloadedVersions = versions
        log("sync: removed local patch \(patchId)")
    }
}

// MARK: - Remote Patches View Model

@MainActor
final class RemotePatchesViewModel: ObservableObject {
    @Published var patches: [RemotePatch] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var downloadingPatchId: String?

    private let syncService = PatchSyncService.shared
    private let remoteService = RemotePatchService.shared

    func loadPatches() async {
        isLoading = true
        errorMessage = nil

        await syncService.sync()

        await MainActor.run {
            self.patches = syncService.remotePatches
            self.isLoading = false
            self.errorMessage = syncService.syncError
        }
    }

    func downloadPatch(_ patch: RemotePatch) async {
        downloadingPatchId = patch.id
        do {
            let fileURL = try await syncService.downloadPatch(patch)
            log("remote: patch saved at \(fileURL.path)")

            // Auto-import into the patch project library
            await importPatchFromFile(fileURL, patch: patch)
        } catch {
            errorMessage = error.localizedDescription
            log("remote: download failed — \(error.localizedDescription)")
        }
        downloadingPatchId = nil
    }

    func updatePatch(_ patch: RemotePatch) async {
        await downloadPatch(patch)
    }

    private func importPatchFromFile(_ fileURL: URL, patch: RemotePatch) async {
        // The patch file is now in Documents/RemotePatches/
        // The user can import it via the existing PatchProjectsView import flow,
        // or we can auto-import it programmatically.
        log("remote: patch \(patch.name) ready for import at \(fileURL.path)")

        // Trigger a notification or UI update to let the user know
        await MainActor.run {
            // Refresh the patches list to show updated download status
            self.patches = syncService.remotePatches
        }
    }

    func hasUpdate(for patch: RemotePatch) -> Bool {
        syncService.patchesWithUpdates.contains(where: { $0.id == patch.id })
    }

    func isDownloaded(_ patch: RemotePatch) -> Bool {
        syncService.isDownloaded(patch.id)
    }
}
