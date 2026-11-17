import Foundation

/// Runs the original Files discovery sequence for both Files and Patches.
final class SharedApplicationDiscoveryService {
    static let shared = SharedApplicationDiscoveryService()

    enum Stage {
        case preliminary
        case progress
        case completed
    }

    struct Update {
        let stage: Stage
        let apps: [InstalledApp]
    }

    private let lock = NSLock()
    private var running = false
    private var observers: [(Update) -> Void] = []

    private init() {}

    func discover(
        requester: String,
        forceRefresh: Bool,
        onUpdate: @escaping (Update) -> Void
    ) {
        lock.lock()
        if running {
            observers.append(onUpdate)
            lock.unlock()
            log("[VINI][Discovery] \(requester) joined active scan")
            return
        }

        running = true
        observers = [onUpdate]
        lock.unlock()
        log("[VINI][Discovery] \(requester) started full scan")
        DispatchQueue.main.async {
            DiscoveredAppCatalog.shared.clear()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            self.runOriginalFilesDiscovery()
        }
    }

    private func emit(_ stage: Stage, apps: [InstalledApp]) {
        lock.lock()
        let currentObservers = observers
        if case .completed = stage {
            running = false
            observers = []
        }
        // Queue publication before another request can begin a new scan.
        DispatchQueue.main.async {
            DiscoveredAppCatalog.shared.publish(apps)
            currentObservers.forEach { $0(Update(stage: stage, apps: apps)) }
        }
        lock.unlock()
    }

    private func runOriginalFilesDiscovery() {
        let bundleMetadata = ContainerStore.applicationBundleMetadataCatalog()
        let apiApps = ContainerStore.applyingBundleMetadata(
            to: ContainerStore.installedAppsFromAPI(),
            catalog: bundleMetadata
        )
        if apiApps.isEmpty {
            log("browser: installed-app API unavailable; trying MCM class-2 enumeration...")
        }
        let dynamicIdentifiers = ContainerStore.dynamicAppIdentifiers()
        let mcmApps = ContainerStore.installedAppsFromMCM(
            identifiers: dynamicIdentifiers,
            bundleMetadata: bundleMetadata
        )
        let filesystemApps = ContainerStore.containersFromFilesystem()
        let baseIdentifiedApps = mcmApps + apiApps
        var result = ContainerDiscoveryMerger.merge(
            enumerated: filesystemApps,
            identified: baseIdentifiedApps,
            path: { $0.containerPath }
        )
        log("browser: merged api=\(apiApps.count), MCM=\(mcmApps.count), filesystem=\(filesystemApps.count) -> \(result.count)")
        result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        let preliminary = result.filter {
            ContainerPresentationPolicy.shouldShow(bundleID: $0.bundleID)
        }
        emit(.preliminary, apps: preliminary)

        let launchServicesIdentifiers = ContainerStore.launchServicesStoreIdentifiers()
        let mhaIdentifiers = MHAIdentifierCatalog.identifiers(
            dynamic: dynamicIdentifiers,
            installed: apiApps.map(\.bundleID),
            research: ContainerStore.researchAppIdentifiers,
            custom: bundleMetadata.keys.sorted(),
            launchServices: launchServicesIdentifiers
        )
        log(
            "browser: MHA catalog dynamic=\(dynamicIdentifiers.count), " +
            "installed=\(apiApps.count), research=\(ContainerStore.researchAppIdentifiers.count), " +
            "LaunchServices=\(launchServicesIdentifiers.count) -> \(mhaIdentifiers.count) candidates"
        )
        let mhaApps = ContainerStore.installedAppsFromMHACandidates(
            identifiers: mhaIdentifiers,
            bundleMetadata: bundleMetadata
        ) { discoveredApps in
            var progressiveResult = AppDataCatalogMerger.merge(
                identified: discoveredApps + baseIdentifiedApps,
                fallback: [],
                identifier: { $0.bundleID },
                path: { $0.containerPath }
            )
            progressiveResult = progressiveResult.filter {
                ContainerPresentationPolicy.shouldShow(bundleID: $0.bundleID)
            }
            progressiveResult.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            self.emit(.progress, apps: progressiveResult)
        }

        let allKnownApps = mhaApps + baseIdentifiedApps
        let identifiedPaths = Set(allKnownApps.map {
            ContainerDiscoveryMerger.canonicalPath($0.containerPath)
        })
        let unmatchedFilesystemApps = filesystemApps.filter {
            !identifiedPaths.contains(
                ContainerDiscoveryMerger.canonicalPath($0.containerPath)
            )
        }
        let inferredFilesystemApps = ContainerStore.inferUnidentifiedApps(
            in: unmatchedFilesystemApps,
            knownApps: allKnownApps,
            launchServicesIdentifiers: Set(launchServicesIdentifiers)
        ).filter {
            ContainerPresentationPolicy.shouldShow(bundleID: $0.bundleID)
        }
        result = AppDataCatalogMerger.merge(
            identified: allKnownApps,
            fallback: inferredFilesystemApps,
            identifier: { $0.bundleID },
            path: { $0.containerPath }
        )
        result = result.filter {
            ContainerPresentationPolicy.shouldShow(bundleID: $0.bundleID)
        }
        result.sort {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        log("[VINI][Discovery] complete api=\(apiApps.count) mcm=\(mcmApps.count) filesystem=\(filesystemApps.count) launchServices=\(launchServicesIdentifiers.count) mha=\(mhaApps.count) final=\(result.count)")
        emit(.completed, apps: result)
    }
}
