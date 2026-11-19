import Foundation

/// WQHealth-equivalent orchestration for the identification path. It records
/// authorization outcomes from the providers already present in 3105; it does
/// not issue tokens or add a sandbox escape implementation.
struct WQIdentityHealthSummary {
    let appGroup: String
    let containersDiscovered: Int
    let sampledContainers: Int
    let containersOpened: Int
    let accessProviders: [String: Int]
    let sourceAuthorization: String
    let sourceOperation: String
    let alternative: String
}

enum WQIdentityHealth {
    /// Reads a source only after an existing 3105 provider has granted and
    /// verified access to its parent. This is an adapter, not a new grant path.
    static func readAuthorizedSource(at path: String) -> Data? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let parent = (path as NSString).deletingLastPathComponent
        guard case .success(let session) = ContainerAccessCoordinator.acquire(
            bundleID: nil,
            containerPath: parent,
            operation: .read
        ) else { return nil }
        _ = session
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    static func run(
        containers: [String],
        sourceReport: [String: Any]
    ) -> WQIdentityHealthSummary {
        let groupID = "group.pigtjing.top"
        let groupUsable = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) != nil
        emit(
            stage: "appgroup",
            component: "WQHealth/AppGroup",
            operation: "containerURL",
            requirement: "signed entitlement and usable shared container",
            resource: "experimental app group",
            result: groupUsable ? "usable" : "unusable",
            alternative: groupUsable ? "none" : "reinstall with the requested entitlement"
        )

        let validContainers = containers.filter { ContainerStore.isApplicationContainerPath($0) }
        emit(
            stage: "containers",
            component: "WQHealth/WQAccess",
            operation: "enumerate application containers",
            requirement: "App Group plus an authorized enumeration provider",
            resource: "application data container roots",
            result: "discovered=\(validContainers.count)",
            alternative: "MCM/API metadata can identify only containers it returns"
        )

        let sample = samplePaths(validContainers, limit: 8)
        var opened = 0
        var providers: [String: Int] = [:]
        for path in sample {
            let outcome = ContainerAccessCoordinator.acquire(
                bundleID: nil,
                containerPath: path,
                operation: .read
            )
            switch outcome {
            case .success(let session):
                opened += 1
                providers[session.provider, default: 0] += 1
                emit(
                    stage: "effective_access",
                    component: "ContainerAccessCoordinator",
                    operation: "list sampled container",
                    requirement: "provider grants access and FileManager can open it",
                    resource: "sampled application container",
                    result: "success provider=\(session.provider)",
                    alternative: "none"
                )
            case .failure(let error):
                emit(
                    stage: "effective_access",
                    component: "ContainerAccessCoordinator",
                    operation: "list sampled container",
                    requirement: "MHA-C2, bad_query, or worse_query plus effective read",
                    resource: "sampled application container",
                    result: "failed \(classify(error))",
                    alternative: "retain UUID and do not infer authorization from identity"
                )
            }
        }

        let sourceState = sourceReport["sourceState"] as? String ?? "unavailable"
        let sourcePath = sourceReport["sourcePath"] as? String
        let sourceOutcome = sourceAccess(state: sourceState, path: sourcePath)
        emit(
            stage: "source_access",
            component: "WQLaunchServices/WQAccess adapter",
            operation: sourceOutcome.operation,
            requirement: "a located CSStore2 path that can be read completely and stably",
            resource: "LaunchServices CSStore2 source",
            result: sourceOutcome.result,
            alternative: sourceOutcome.alternative
        )

        return WQIdentityHealthSummary(
            appGroup: groupUsable ? "usable" : "unusable",
            containersDiscovered: validContainers.count,
            sampledContainers: sample.count,
            containersOpened: opened,
            accessProviders: providers,
            sourceAuthorization: sourceOutcome.result,
            sourceOperation: sourceOutcome.operation,
            alternative: sourceOutcome.alternative
        )
    }

    private static func sourceAccess(
        state: String,
        path: String?
    ) -> (operation: String, result: String, alternative: String) {
        guard state == "valid" || state == "readable" || state == "located_unreadable" else {
            return (
                "locate and open CSStore2",
                "not_attempted state=\(state)",
                "refresh discovery; no authorized source was located"
            )
        }
        guard let path, !path.isEmpty else {
            return (
                "locate CSStore2 path",
                "failed missing_path",
                "persisted location is not evidence of availability"
            )
        }
        let parent = (path as NSString).deletingLastPathComponent
        guard FileManager.default.fileExists(atPath: path) else {
            return (
                "stat CSStore2",
                "failed source_missing",
                "rerun source discovery; do not parse a remembered path"
            )
        }

        // A direct read is already proof of effective access. If it failed,
        // retry only through the access providers that 3105 already exposes.
        if state == "valid" || state == "readable" {
            return (
                "stable read CSStore2",
                "success direct_read",
                "none"
            )
        }
        let outcome = ContainerAccessCoordinator.acquire(
            bundleID: nil,
            containerPath: parent,
            operation: .read
        )
        switch outcome {
        case .success(let session):
            let readable = readAuthorizedSource(at: path) != nil
            return (
                "retry stable read CSStore2",
                readable ? "success provider=\(session.provider)" : "failed provider_open_but_file_read_failed",
                readable ? "none" : "provider authorization did not make the source readable"
            )
        case .failure(let error):
            return (
                "authorize CSStore2 parent",
                "failed \(classify(error))",
                "MHA-C2, bad_query, and worse_query all failed effective access"
            )
        }
    }

    private static func samplePaths(_ paths: [String], limit: Int) -> [String] {
        guard paths.count > limit else { return paths }
        return (0..<limit).map { paths[($0 * paths.count) / limit] }
    }

    private static func classify(_ error: Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain) code=\(nsError.code)"
    }

    private static func emit(
        stage: String,
        component: String,
        operation: String,
        requirement: String,
        resource: String,
        result: String,
        alternative: String
    ) {
        log("wq.identity.stage=\(stage) component=\(component) operation=\(operation) requirement=\(requirement) resource=\(resource) result=\(result) alternative=\(alternative)")
    }
}
