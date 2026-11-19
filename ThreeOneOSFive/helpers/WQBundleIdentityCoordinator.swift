import Foundation

struct WQBundleIdentityComparison {
    let sourceState: String
    let sourceFound: Bool
    let sourceReadable: Bool
    let storeBytes: Int
    let layout: String
    let records: Int
    let bundleIDs: Int
    let verifiedNames: Int
    let matchedUUID: Int
    let matching: Int
    let conflicts: Int
    let additionalApps: [InstalledApp]
}

enum WQBundleIdentityCoordinator {
    static func evaluate(
        containerPaths: [String],
        original: [String: WQFilesResolvedIdentity]
    ) -> WQBundleIdentityComparison {
        let usesOriginalRuntime = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
        let report = usesOriginalRuntime
            ? WQIntegratedRuntimeReport()
            : ((wq_phase1_identity_report() as? [String: Any]) ?? [:])
        let sourceState = report["sourceState"] as? String ?? "unavailable"
        let sourceFound = report["sourceFound"] as? Bool ?? false
        let sourceReadable = report["sourceReadable"] as? Bool ?? false
        let reportBytes = (report["storeBytes"] as? NSNumber)?.intValue ?? 0
        let reportRecords = (report["records"] as? NSNumber)?.intValue ?? 0
        let reportBundleIDs = (report["bundleIDs"] as? NSNumber)?.intValue ?? 0
        let reportNames = (report["verifiedNames"] as? NSNumber)?.intValue ?? 0
        let health = WQIdentityHealth.run(
            containers: containerPaths,
            sourceReport: report
        )
        log("wq.identity: effective_access sampled=\(health.sampledContainers) opened=\(health.containersOpened) providers=\(health.accessProviders)")

        let sourceData: Data?
        let parsedReport: [String: Any]?
        if usesOriginalRuntime {
            sourceData = nil
            parsedReport = sourceReadable ? report : nil
        } else {
            if sourceState == "valid" {
                sourceData = wq_phase1_read_available_store()
                    ?? (report["sourcePath"] as? String).flatMap { WQIdentityHealth.readAuthorizedSource(at: $0) }
            } else if let path = report["sourcePath"] as? String {
                sourceData = WQIdentityHealth.readAuthorizedSource(at: path)
            } else {
                sourceData = nil
            }
            parsedReport = sourceData.flatMap { wq_phase1_parse_store_data($0) as? [String: Any] }
        }
        guard let parsed = parsedReport else {
            return WQBundleIdentityComparison(
                sourceState: sourceState,
                sourceFound: sourceFound,
                sourceReadable: sourceReadable,
                storeBytes: reportBytes,
                layout: report["layout"] as? String ?? "unknown",
                records: reportRecords,
                bundleIDs: reportBundleIDs,
                verifiedNames: reportNames,
                matchedUUID: 0,
                matching: 0,
                conflicts: 0,
                additionalApps: []
            )
        }

        let rawContainers = (parsed["containers"] as? [String: Any]) ?? [:]
        let wqMap = rawContainers.compactMapValues { value -> String? in
            guard let bundleID = value as? String else { return nil }
            return Self.validBundleID(bundleID) ? bundleID : nil
        }
        let display = (parsed["display"] as? [String: String]) ?? [:]
        let bundleNames = (parsed["bundleNames"] as? [String: String]) ?? [:]
        let originalMap = original.mapValues(\.bundleID)
        let sharedPaths = Set(originalMap.keys).intersection(wqMap.keys)
        let matching = sharedPaths.filter { originalMap[$0] == wqMap[$0] }.count
        let conflicts = sharedPaths.count - matching
        let canonicalCandidates = Set(containerPaths.map(ContainerDiscoveryMerger.canonicalPath))
        let matchedUUID = wqMap.keys.filter {
            canonicalCandidates.contains($0) && Self.isApplicationDataContainer($0)
        }.count
        let additional = wqMap.keys
            .filter { canonicalCandidates.contains($0) && originalMap[$0] == nil }
            .filter { Self.isApplicationDataContainer($0) }
            .compactMap { path -> InstalledApp? in
                guard let bundleID = wqMap[path] else { return nil }
                guard let name = display[bundleID] ?? bundleNames[bundleID], !name.isEmpty else {
                    return nil
                }
                return InstalledApp(
                    bundleID: bundleID,
                    name: name,
                    containerPath: path,
                    version: "",
                    icon: nil
                )
            }

        return WQBundleIdentityComparison(
            sourceState: sourceState == "valid" ? "valid" : "valid_after_existing_provider",
            sourceFound: true,
            sourceReadable: true,
            storeBytes: sourceData?.count ?? reportBytes,
            layout: report["layout"] as? String ?? "unknown",
            records: (parsed["records"] as? NSNumber)?.intValue ?? reportRecords,
            bundleIDs: Set(wqMap.values).count,
            verifiedNames: display.count,
            matchedUUID: matchedUUID,
            matching: matching,
            conflicts: conflicts,
            additionalApps: additional
        )
    }

    static func emitDiagnostics(_ comparison: WQBundleIdentityComparison, containerCount: Int) {
        let groupUsable = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.pigtjing.top"
        ) != nil
        log("wq.identity: appgroup=\(groupUsable ? "usable" : "unusable")")
        log("wq.identity: containers_discovered=\(containerCount)")
        log("wq.identity: source_found=\(comparison.sourceFound)")
        log("wq.identity: source_readable=\(comparison.sourceReadable)")
        log("wq.identity: store_bytes=\(comparison.storeBytes)")
        log("wq.identity: layout=\(comparison.layout)")
        log("wq.identity: records=\(comparison.records < 0 ? "see_original_parser_log" : String(comparison.records))")
        log("wq.identity: bundle_ids=\(comparison.bundleIDs)")
        log("wq.identity: matched_uuid=\(comparison.matchedUUID)")
        log("wq.identity: verified_names=\(comparison.verifiedNames)")
        log("wq.identity: source_state=\(comparison.sourceState)")
        log("wq.identity: resolver_matching=\(comparison.matching) conflicts=\(comparison.conflicts) additional=\(comparison.additionalApps.count)")
    }

    private static func validBundleID(_ value: String) -> Bool {
        guard value.count > 2, value.contains(".") else { return false }
        guard !value.hasPrefix("."), !value.hasPrefix("group."), !value.hasPrefix("systemgroup.") else { return false }
        let punctuation = CharacterSet(charactersIn: ".-_")
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || punctuation.contains($0)
        }
    }

    private static func isApplicationDataContainer(_ path: String) -> Bool {
        let prefix = "/private/var/mobile/Containers/Data/Application/"
        guard path.hasPrefix(prefix), path.count == prefix.count + 36 else { return false }
        return UUID(uuidString: String(path.dropFirst(prefix.count))) != nil
    }
}
