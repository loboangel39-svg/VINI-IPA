import Foundation
import SwiftUI

struct PatchStoreAlert: Identifiable {
    let id = UUID()
    let titleKey: String
    let messageKey: String
    var messageArgument: String?

    init(titleKey: String, messageKey: String, messageArgument: String? = nil) {
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.messageArgument = messageArgument
    }

    func message(language: AppLanguage) -> String {
        if let messageArgument {
            return language.text(messageKey, messageArgument)
        }
        return language.text(messageKey)
    }
}

@MainActor
final class PatchProjectStore: ObservableObject {
    @Published private(set) var items: [PatchLibraryItem] = []
    @Published private(set) var isBusy = false
    @Published var passwordRequest: PatchPasswordRequest?
    @Published var alert: PatchStoreAlert?
    @Published var unlockErrorKey: String?

    @Published private(set) var assignedPatchIDs: Set<UUID> = []
    @Published private(set) var hasLoadedFromRemote = false

    private struct PendingUnlock {
        let data: Data
        let summary: PatchPackageSummary
        let existingURL: URL?
    }

    private var pendingUnlock: PendingUnlock?

    init() {
        NotificationCenter.default.addObserver(
            forName: .patchesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }

        NotificationCenter.default.addObserver(
            forName: .assignedPatchesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let ids = notification.userInfo?["patchIDs"] as? Set<UUID> {
                Task { @MainActor in
                    self?.assignedPatchIDs = ids
                    self?.hasLoadedFromRemote = true
                    self?.reload()
                }
            }
        }

        log("patch: store initialized, waiting for remote patches")
    }

    func loadAssignedPatches() async {
        do {
            let remotePatches = try await RemotePatchService.shared.fetchAvailablePatches()
            let ids = Set(remotePatches.compactMap { patch -> UUID? in
                UUID(uuidString: patch.id)
            })

            await MainActor.run {
                self.assignedPatchIDs = ids
                self.hasLoadedFromRemote = true
                self.reload()
            }

            log("remote: loaded \(ids.count) assigned patch IDs from worker")
        } catch {
            log("remote: failed to load assigned patches - \(error.localizedDescription)")
            await MainActor.run {
                self.assignedPatchIDs = []
                self.hasLoadedFromRemote = true
                self.items = []
            }
        }
    }

    func reload() {
        items = PatchProjectLibrary.load(allowedPatchIDs: assignedPatchIDs)
        log("patch: reloaded \(items.count) items from \(assignedPatchIDs.count) assigned")
    }

    func create(project: PatchProject, password: String?) {
        runOperation(successMessageKey: "patch.created_message") {
            let encoded = try PatchPackageCodec.encodeNew(project: project, password: password)
            let summary = try PatchPackageCodec.inspect(encoded.data)
            let workspace = try PatchWorkspaceService.createWorkspace(for: project)
            do {
                if summary.isPasswordProtected {
                    try PatchKeyStore.store(encoded.contentKey, for: summary)
                }
                _ = try PatchProjectLibrary.save(data: encoded.data, projectName: project.name)
            } catch {
                try? FileManager.default.removeItem(at: workspace)
                try? PatchKeyStore.delete(for: summary)
                throw error
            }
        }
    }

    func update(project: PatchProject) {
        guard let item = items.first(where: { $0.id == project.id }),
              let contentKey = item.contentKey else {
            present(.invalidProject)
            return
        }
        runOperation(successMessageKey: "patch.updated_message") {
            let original = try PatchProjectLibrary.readPackage(at: item.packageURL)
            let updated = try PatchPackageCodec.update(
                original,
                project: project,
                contentKey: contentKey
            )
            _ = try PatchProjectLibrary.save(
                data: updated,
                projectName: project.name,
                existingURL: item.packageURL
            )
        }
    }

    func importPackage(at sourceURL: URL) {
        guard !isBusy else { return }
        isBusy = true
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        Task.detached(priority: .userInitiated) { [weak self] in
            defer {
                if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try PatchProjectLibrary.readPackage(at: sourceURL)
                let summary = try PatchPackageCodec.inspect(data)
                let existingURL = await self?.existingPackageURL(for: summary.packageID)
                if let pending = try Self.persistImportedPackage(
                    data: data,
                    summary: summary,
                    existingURL: existingURL
                ) {
                    await self?.requestPassword(pending: pending)
                } else {
                    await self?.finishOperation(successMessageKey: "patch.imported_message")
                }
            } catch {
                await self?.present(.importFailed)
            }
            await MainActor.run { self?.isBusy = false }
        }
    }

    func delete(_ item: PatchLibraryItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        runOperation(successMessageKey: "patch.deleted_message") {
            try PatchProjectLibrary.delete(item)
        }
    }

    func requestUnlock(summary: PatchPackageSummary, password: String) {
        guard !isBusy else { return }
        isBusy = true
        Task.detached(priority: .userInitiated) { [weak self] in
            defer { Task { @MainActor in self?.isBusy = false } }
            do {
                let existingURL = await self?.existingPackageURL(for: summary.packageID)
                guard let url = existingURL else {
                    await self?.present(.invalidProject)
                    return
                }
                let data = try PatchProjectLibrary.readPackage(at: url)
                let decoded = try PatchPackageCodec.decode(data, password: password)
                try PatchKeyStore.store(decoded.contentKey, for: summary)
                let project = decoded.project
                if decoded.project.schemaVersion >= 2 {
                    _ = try? PatchWorkspaceService.ensureWorkspace(for: project)
                }
                await self?.finishOperation(successMessageKey: "patch.unlocked_message")
            } catch {
                await self?.present(.unlockFailed)
            }
        }
    }

    private func runOperation(successMessageKey: String, _ body: () throws -> Void) {
        isBusy = true
        defer { isBusy = false }
        do {
            try body()
            reload()
            alert = PatchStoreAlert(titleKey: "patch.success_title", messageKey: successMessageKey)
        } catch let error as PatchPackageError {
            present(error)
        } catch {
            present(.invalidProject)
        }
    }

    private func present(_ error: PatchPackageError) {
        switch error {
        case .invalidProject:
            alert = PatchStoreAlert(titleKey: "patch.error_title", messageKey: "patch.error_invalid")
        case .invalidPassword:
            alert = PatchStoreAlert(titleKey: "patch.error_title", messageKey: "patch.error_password")
        case .targetAppUnavailable:
            alert = PatchStoreAlert(titleKey: "patch.error_title", messageKey: "patch.error_targetUnavailable")
        case .duplicateTarget:
            alert = PatchStoreAlert(titleKey: "patch.error_title", messageKey: "patch.error_duplicate")
        case .unsupportedVersion:
            alert = PatchStoreAlert(titleKey: "patch.error_title", messageKey: "patch.error_unsupported")
        }
    }

    private func present(_ alertKey: PatchAlertKey) {
        switch alertKey {
        case .importFailed:
            alert = PatchStoreAlert(titleKey: "patch.error_title", messageKey: "patch.error_import")
        case .unlockFailed:
            alert = PatchStoreAlert(titleKey: "patch.error_title", messageKey: "patch.error_unlock")
        }
    }

    private enum PatchAlertKey {
        case importFailed
        case unlockFailed
    }

    private func finishOperation(successMessageKey: String) {
        reload()
        alert = PatchStoreAlert(titleKey: "patch.success_title", messageKey: successMessageKey)
    }

    private func requestPassword(pending: PendingUnlock) {
        pendingUnlock = pending
        passwordRequest = PatchPasswordRequest(summary: pending.summary)
        isBusy = false
    }

    func cancelPasswordRequest() {
        pendingUnlock = nil
        passwordRequest = nil
    }

    private static func persistImportedPackage(
        data: Data,
        summary: PatchPackageSummary,
        existingURL: URL?
    ) throws -> PendingUnlock? {
        let savedURL = try PatchProjectLibrary.save(
            data: data,
            projectName: summary.packageID.uuidString,
            existingURL: existingURL
        )
        if summary.isPasswordProtected {
            return PendingUnlock(data: data, summary: summary, existingURL: savedURL)
        }
        let decoded = try PatchPackageCodec.decode(data, password: nil)
        try PatchKeyStore.store(decoded.contentKey, for: summary)
        if summary.schemaVersion >= 2 {
            _ = try? PatchWorkspaceService.ensureWorkspace(for: decoded.project)
        }
        return nil
    }

    private func existingPackageURL(for packageID: UUID) -> URL? {
        items.first(where: { $0.id == packageID })?.packageURL
    }
}
