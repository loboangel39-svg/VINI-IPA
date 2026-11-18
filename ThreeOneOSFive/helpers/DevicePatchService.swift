import Foundation
import Darwin

enum DevicePatchService {
    static func apply(project: PatchProject) throws -> PatchTransactionReceipt {
        let bundleIDs = orderedBundleIdentifiers(in: project)
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.apply(
                project: project,
                backupRoot: try PatchProjectLibrary.backupRootURL(),
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func inspectRestore(receipt: PatchTransactionReceipt) throws -> PatchRestoreInspection {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.inspectRestore(
                receipt: receipt,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func restore(
        receipt: PatchTransactionReceipt,
        allowChangedTargets: Bool = false
    ) throws {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.restore(
                receipt: receipt,
                allowChangedTargets: allowChangedTargets,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func resetToAppliedState(
        receipt: PatchTransactionReceipt,
        project: PatchProject
    ) throws {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.resetToAppliedState(
                receipt: receipt,
                fallbackProject: project,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func latestReceipt(projectID: UUID) -> PatchTransactionReceipt? {
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.latestReceipt(projectID: projectID, backupRoot: backupRoot)
    }

    static func inspectInstallation(project: PatchProject) -> PatchInstallationState {
        var roots: [String: URL] = [:]
        var grants: [Int64] = []
        defer { grants.forEach { ContainerStore.releaseContainerAccess($0) } }

        do {
            for bundleID in project.allBundleIdentifiers {
                guard let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID),
                      ContainerStore.isApplicationContainerPath(path) else {
                    return .unknown
                }
                if !ContainerStore.hasAccess(to: path) {
                    let grant = ContainerStore.grantContainerAccess(path)
                    if grant >= 0 { grants.append(grant) }
                }
                guard ContainerStore.hasAccess(to: path) else { return .unknown }
                if let metadata = ContainerStore.readContainerMetadata(containerPath: path),
                   !metadata.bundleID.isEmpty,
                   metadata.bundleID != bundleID {
                    return .unknown
                }
                roots[bundleID] = PatchPathValidator.canonicalFileURL(
                    URL(fileURLWithPath: path, isDirectory: true)
                )
            }

            var observations: [PatchTargetObservation] = []
            for rule in project.rules {
                guard let root = roots[rule.bundleID] else { return .unknown }
                let target = try PatchPathValidator.resolveTargetURL(
                    bundleID: rule.bundleID,
                    relativePath: rule.relativePath,
                    containerRoot: root
                )
                observations.append(inspectFile(target, expected: rule.replacementData))
            }
            for directory in project.directories {
                guard let root = roots[directory.bundleID] else { return .unknown }
                let target = try PatchPathValidator.resolveTargetURL(
                    bundleID: directory.bundleID,
                    relativePath: directory.relativePath,
                    containerRoot: root
                )
                observations.append(inspectDirectory(target))
            }
            return PatchInstallationStateResolver.resolve(
                observations: observations,
                hasVerifiableFiles: !project.rules.isEmpty
            )
        } catch {
            log("patch: installation inspection unavailable project=\(project.id.uuidString) error=\(error)")
            return .unknown
        }
    }

    private static func inspectFile(_ url: URL, expected: Data) -> PatchTargetObservation {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return observationForOpenFailure(errno) }
        defer { close(descriptor) }

        var status = stat()
        guard fstat(descriptor, &status) == 0 else { return .unavailable }
        guard (status.st_mode & S_IFMT) == S_IFREG else { return .differs }
        guard status.st_size == Int64(expected.count) else { return .differs }

        var actual = Data()
        actual.reserveCapacity(expected.count)
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            guard count > 0 else {
                if errno == EINTR { continue }
                return .unavailable
            }
            actual.append(contentsOf: buffer.prefix(count))
        }
        return actual == expected ? .matches : .differs
    }

    private static func inspectDirectory(_ url: URL) -> PatchTargetObservation {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if errno == ENOTDIR { return .differs }
            return observationForOpenFailure(errno)
        }
        close(descriptor)
        return .matches
    }

    private static func observationForOpenFailure(_ code: Int32) -> PatchTargetObservation {
        code == ENOENT ? .missing : .unavailable
    }

    private static func orderedBundleIdentifiers(in project: PatchProject) -> [String] {
        project.allBundleIdentifiers
    }

    private static func withResolvedContainers<T>(
        bundleIDs: [String],
        operation: ([String: URL]) throws -> T
    ) throws -> T {
        var roots: [String: URL] = [:]
        var grants: [Int64] = []
        defer { grants.forEach { ContainerStore.releaseContainerAccess($0) } }

        for bundleID in bundleIDs {
            guard let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID) else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            let hasResolvedTarget = ContainerStore.isApplicationContainerPath(path)
            guard hasResolvedTarget else { throw PatchPackageError.targetAppUnavailable(bundleID) }

            // The original resolver owns the path. The additional provider is
            // only used when that path is not already writable, and the grant
            // is held for the whole transaction.
            if !ContainerStore.hasAccess(to: path, requiringWrite: true) {
                let grant = ContainerStore.grantContainerAccess(path, requiringWrite: true)
                if grant >= 0 { grants.append(grant) }
            }
            let hasWriteAccess = ContainerStore.hasAccess(to: path, requiringWrite: true)
            let metadata = hasWriteAccess
                ? ContainerStore.readContainerMetadata(containerPath: path)
                : nil
            switch PatchTargetValidationResult.classify(
                hasResolvedTarget: hasResolvedTarget,
                hasWriteAccess: hasWriteAccess,
                requestedBundleID: bundleID,
                metadataBundleID: metadata?.bundleID
            ) {
            case .unavailable:
                throw PatchPackageError.targetAppUnavailable(bundleID)
            case .writeAccessDenied:
                log("patch: write access unavailable for \(bundleID)")
                throw PatchPackageError.targetWriteAccessDenied(bundleID)
            case .identityMismatch:
                log(
                    "patch: identity mismatch for \(bundleID) at \(path) " +
                        "metadata=\(metadata?.bundleID ?? "unavailable")"
                )
                throw PatchPackageError.targetIdentityMismatch(bundleID)
            case .available:
                break
            }

            roots[bundleID] = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
        }
        return try operation(roots)
    }
}
