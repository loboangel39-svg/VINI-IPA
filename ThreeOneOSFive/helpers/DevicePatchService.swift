import Foundation

enum DevicePatchService {
    static func apply(project: PatchProject) throws -> PatchTransactionReceipt {
        let attemptID = String(UUID().uuidString.prefix(8))
        let started = DispatchTime.now().uptimeNanoseconds
        log("[APPLY-DIAG] attempt.start id=\(attemptID)")
        defer {
            log("[APPLY-DIAG] attempt.finish id=\(attemptID) durationMs=\(elapsedMs(since: started))")
        }
        let bundleIDs = orderedBundleIdentifiers(in: project)
        log("[APPLY-DIAG] project.validated id=\(attemptID) bundleCount=\(bundleIDs.count)")
        do {
            let receipt = try withResolvedContainers(bundleIDs: bundleIDs, attemptID: attemptID) { roots in
                let transactionStarted = DispatchTime.now().uptimeNanoseconds
                log("[APPLY-DIAG] transaction.start id=\(attemptID)")
                do {
                    let result = try PatchTransaction.apply(
                        project: project,
                        backupRoot: try PatchProjectLibrary.backupRootURL(),
                        containerResolver: { bundleID in
                            guard let root = roots[bundleID] else {
                                throw PatchPackageError.targetAppUnavailable(bundleID)
                            }
                            return root
                        }
                    )
                    log("[APPLY-DIAG] transaction.success id=\(attemptID) durationMs=\(elapsedMs(since: transactionStarted))")
                    return result
                } catch {
                    log("[APPLY-DIAG] transaction.failure id=\(attemptID) category=\(errorCategory(error)) durationMs=\(elapsedMs(since: transactionStarted))")
                    throw error
                }
            }
            return receipt
        } catch {
            log("[APPLY-DIAG] attempt.failure id=\(attemptID) category=\(errorCategory(error))")
            throw error
        }
    }

    static func inspectRestore(receipt: PatchTransactionReceipt) throws -> PatchRestoreInspection {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        return try withResolvedContainers(bundleIDs: bundleIDs, attemptID: "restore-inspect") { roots in
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
        try withResolvedContainers(bundleIDs: bundleIDs, attemptID: "restore") { roots in
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
        try withResolvedContainers(bundleIDs: bundleIDs, attemptID: "reset") { roots in
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

    private static func orderedBundleIdentifiers(in project: PatchProject) -> [String] {
        project.allBundleIdentifiers
    }

    private static func withResolvedContainers<T>(
        bundleIDs: [String],
        attemptID: String,
        operation: ([String: URL]) throws -> T
    ) throws -> T {
        var roots: [String: URL] = [:]
        var sessions: [ContainerAccessSession] = []

        for (index, bundleID) in bundleIDs.enumerated() {
            let stageStarted = DispatchTime.now().uptimeNanoseconds
            log("[APPLY-DIAG] bundle.resolve.start id=\(attemptID) index=\(index)")
            guard let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID) else {
                log("[APPLY-DIAG] bundle.resolve.failure id=\(attemptID) index=\(index) category=unresolved durationMs=\(elapsedMs(since: stageStarted))")
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            log("[APPLY-DIAG] bundle.resolve.success id=\(attemptID) index=\(index) durationMs=\(elapsedMs(since: stageStarted))")
            let validationStarted = DispatchTime.now().uptimeNanoseconds
            guard ContainerStore.isApplicationContainerPath(path) else {
                log("[APPLY-DIAG] container.path.validation id=\(attemptID) index=\(index) result=failure durationMs=\(elapsedMs(since: validationStarted))")
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            log("[APPLY-DIAG] container.path.validation id=\(attemptID) index=\(index) result=success durationMs=\(elapsedMs(since: validationStarted))")
            let accessStarted = DispatchTime.now().uptimeNanoseconds
            log("[APPLY-DIAG] access.acquire.start id=\(attemptID) index=\(index)")
            do {
                let session = try ContainerAccessCoordinator.acquire(
                    bundleID: bundleID, containerPath: path, operation: .write
                ).get()
                sessions.append(session)
                log("[APPLY-DIAG] access.acquire.success id=\(attemptID) index=\(index) provider=\(session.provider) durationMs=\(elapsedMs(since: accessStarted))")
            } catch {
                log("patch: shared container access failed \(bundleID): \(error.localizedDescription)")
                log("[APPLY-DIAG] access.acquire.failure id=\(attemptID) index=\(index) category=\(errorCategory(error)) durationMs=\(elapsedMs(since: accessStarted))")
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            roots[bundleID] = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
        }
        return try withExtendedLifetime(sessions) { try operation(roots) }
    }

    private static func elapsedMs(since start: UInt64) -> UInt64 {
        (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private static func errorCategory(_ error: Error) -> String {
        String(describing: type(of: error))
    }
}
