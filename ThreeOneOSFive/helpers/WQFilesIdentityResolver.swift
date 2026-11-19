import Foundation

struct WQFilesResolvedIdentity: Equatable {
    let containerPath: String
    let bundleID: String
    let displayName: String
    let source: String
    let storeSignature: String
}

enum WQFilesIdentityResolver {
    static let diagnosticBuildRevision = "wqfiles-full-integration-v2"
    // This is a local diagnostic switch. It changes presentation only and never
    // changes grants, MHA-C2, signing, or write operations.
    static let enabledDefaultsKey = "wqfiles.identityResolver.enabled"

    private struct Layout {
        let name: String
        let bundleSize: UInt32
        let bundleID: UInt32
        let container: UInt32
        let nameRef: UInt32
        let displayName: UInt32
        let pluginSize: UInt32
        let pluginBundleID: UInt32
        let pluginContainer: UInt32
    }

    private struct StoreSnapshot {
        let signature: String
        let identities: [String: WQFilesResolvedIdentity]
    }

    private struct SourceInventory {
        let stores: [URL]
        let rootsChecked: Int
        let inaccessibleRoots: Int
    }

    private struct ParseOutcome {
        let state: String
        let identities: [String: WQFilesResolvedIdentity]
        let recordsProcessed: Int
        let recordsRejected: Int
    }

    private static let layouts: [Layout] = [
        Layout(name: "27.0", bundleSize: 0x250, bundleID: 0x0c, container: 0x68,
               nameRef: 0x6c, displayName: 0x74, pluginSize: 0x118,
               pluginBundleID: 0x00, pluginContainer: 0x54),
        Layout(name: "27.2", bundleSize: 0x25c, bundleID: 0x0c, container: 0x6c,
               nameRef: 0x70, displayName: 0x78, pluginSize: 0x120,
               pluginBundleID: 0x00, pluginContainer: 0x58),
        Layout(name: "27.2b", bundleSize: 0x25c, bundleID: 0x10, container: 0x6c,
               nameRef: 0x70, displayName: 0x78, pluginSize: 0x120,
               pluginBundleID: 0x04, pluginContainer: 0x58),
        Layout(name: "27.3", bundleSize: 0x25c, bundleID: 0x0c, container: 0x6c,
               nameRef: 0x70, displayName: 0x78, pluginSize: 0x134,
               pluginBundleID: 0x00, pluginContainer: 0x58),
        Layout(name: "27.3d", bundleSize: 0x25c, bundleID: 0x0c, container: 0x6c,
               nameRef: 0x70, displayName: 0x78, pluginSize: 0x0f0,
               pluginBundleID: 0x04, pluginContainer: 0x6c)
    ]

    private static var snapshot: StoreSnapshot?
    private static let lock = NSLock()

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true
    }

    static func logExperimentalAppGroupStatus() {
        let requested = "group.pigtjing.top"
        let entitled = WQAuthorizedAppGroup() ?? ""
        let hasEntitlement = entitled == requested
        let usable = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: requested
        ) != nil
        log("appgroup: requested=\(requested)")
        log("appgroup: entitled=\(entitled)")
        log("appgroup: usable=\(usable) effective_requested=\(hasEntitlement)")
    }

    static func resolve(containerPaths: [String]) -> [String: WQFilesResolvedIdentity] {
        log("wqfiles: invocation build=\(diagnosticBuildRevision) enabled=\(isEnabled) paths=\(containerPaths.count) os=\(AppInfo.osVersion) buildOS=\(AppInfo.osBuild)")
        guard isEnabled else {
            log("wqfiles: identity resolver disabled by local diagnostic setting")
            return [:]
        }

        if #available(iOS 26.0, *) {
            let identities = WQIntegratedIdentities(containerPaths)
            var result: [String: WQFilesResolvedIdentity] = [:]
            for (rawPath, fields) in identities {
                guard let path = applicationContainerPath(rawPath),
                      let bundleID = fields["bundleID"], isValidBundleID(bundleID) else { continue }
                result[path] = WQFilesResolvedIdentity(containerPath: path, bundleID: bundleID,
                    displayName: fields["displayName"] ?? bundleID,
                    source: "WQAccess/LaunchServices", storeSignature: "WQFiles-runtime")
            }
            return result
        }

        let requested = Set(containerPaths.compactMap(applicationContainerPath))
        guard !requested.isEmpty else {
            log("wqfiles: completion state=no_valid_requested_paths input=\(containerPaths.count) valid=0")
            return [:]
        }
        guard let current = loadSnapshot() else {
            log("wqfiles: completion state=source_or_parse_failure valid=\(requested.count) matches=0")
            return [:]
        }

        let result = current.identities.filter { requested.contains($0.key) }
        log("wqfiles: CSStore2 verified \(result.count)/\(requested.count) application identities")
        log("wqfiles: completion state=success valid=\(requested.count) matches=\(result.count)")
        return result
    }

    // Diagnostic-only entry point used by the Phase 1 A/B comparison. The
    // caller supplies the exact bytes read by the LaunchServices module, so
    // both readers process the same CSStore2 snapshot.
    static func resolve(data: Data, containerPaths: [String]) -> [String: WQFilesResolvedIdentity] {
        let requested = Set(containerPaths.compactMap(applicationContainerPath))
        guard !requested.isEmpty else { return [:] }
        let parsed = parse(data: data)
        guard !parsed.identities.isEmpty else { return [:] }
        return parsed.identities.filter { requested.contains($0.key) }
    }

    static func resetForDiagnostics() {
        lock.lock()
        snapshot = nil
        lock.unlock()
    }

    private static func applicationContainerPath(_ raw: String) -> String? {
        let path = ContainerDiscoveryMerger.canonicalPath(raw)
        let root = ContainerDiscoveryMerger.canonicalPath(ContainerStore.appDataRoot)
        guard path.hasPrefix(root + "/") else { return nil }
        let uuid = (path as NSString).lastPathComponent
        guard UUID(uuidString: uuid) != nil else { return nil }
        return path
    }

    private static func loadSnapshot() -> StoreSnapshot? {
        let inventory = storeCandidates()
        guard !inventory.stores.isEmpty else {
            let state = inventory.inaccessibleRoots > 0 ? "access_denied" : "source_not_found"
            log("wqfiles: diagnostic state=\(state) roots=\(inventory.rootsChecked) inaccessible=\(inventory.inaccessibleRoots) candidates=0 records=0 rejected=0 matches=0; preserving original list")
            return nil
        }

        var lastState = "read_failed"
        var lastRecords = 0
        var lastRejected = 0
        for url in inventory.stores {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.uint64Value,
                  size >= 4 * 1024, size <= 64 * 1024 * 1024 else {
                log("wqfiles: read attempted=\(url.lastPathComponent) read status=unavailable category=access_denied")
                lastState = "access_denied"
                continue
            }
            log("wqfiles: read attempted=\(url.lastPathComponent) read status=started")
            guard let before = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let after = try? FileManager.default.attributesOfItem(atPath: url.path),
                  sameFile(before, after) else {
                log("wqfiles: read attempted=\(url.lastPathComponent) read status=failed category=read_failed")
                lastState = "read_failed"
                continue
            }

            log("wqfiles: read status=success bytes=\(data.count)")
            log("wqfiles: parser started source=CSStore2")
            let parsed = parse(data: data)
            log("wqfiles: parser completed state=\(parsed.state) records=\(parsed.recordsProcessed) rejected=\(parsed.recordsRejected) matches=\(parsed.identities.count)")
            lastState = parsed.state
            lastRecords = parsed.recordsProcessed
            lastRejected = parsed.recordsRejected
            guard !parsed.identities.isEmpty else {
                log("wqfiles: diagnostic state=\(parsed.state) store=\(url.lastPathComponent) candidates=\(inventory.stores.count) records=\(parsed.recordsProcessed) rejected=\(parsed.recordsRejected) matches=0")
                continue
            }

            let signature = fileSignature(after)
            lock.lock()
            if let cached = snapshot, cached.signature == signature {
                lock.unlock()
                return cached
            }
            let stamped = parsed.identities.mapValues {
                WQFilesResolvedIdentity(
                    containerPath: $0.containerPath,
                    bundleID: $0.bundleID,
                    displayName: $0.displayName,
                    source: $0.source,
                    storeSignature: signature
                )
            }
            let result = StoreSnapshot(signature: signature, identities: stamped)
            snapshot = result
            lock.unlock()
            log("wqfiles: diagnostic state=success store=\(url.lastPathComponent) candidates=\(inventory.stores.count) records=\(parsed.recordsProcessed) rejected=\(parsed.recordsRejected) matches=\(stamped.count)")
            return result
        }
        log("wqfiles: diagnostic state=\(lastState) candidates=\(inventory.stores.count) records=\(lastRecords) rejected=\(lastRejected) matches=0; preserving original list")
        return nil
    }

    private static func storeCandidates() -> SourceInventory {
        var cacheRoots: [String] = []
        var seen = Set<String>()
        func add(_ raw: String) {
            let path = ContainerDiscoveryMerger.canonicalPath(raw)
            if seen.insert(path).inserted { cacheRoots.append(path) }
        }

        var directStores: [URL] = []
        var error: NSString?
        if let lsd = MCMActivateContainerPath(10, "com.apple.lsd", false, &error) {
            add((lsd as NSString).appendingPathComponent("Library/Caches"))
            log("wqfiles: source origin=mcm_lsd_container status=available")
        } else {
            log("wqfiles: source origin=mcm_lsd_container status=unavailable category=access_denied")
        }
        // WQFiles remembers the exact store after locating it. Reuse only that
        // path if it is already available to this process; do not discover or
        // read anything through a new privilege mechanism.
        if let remembered = UserDefaults.standard.string(forKey: "WQLaunchServicesStore"),
           remembered.hasSuffix(".csstore") {
            directStores.append(URL(fileURLWithPath: ContainerDiscoveryMerger.canonicalPath(remembered)))
            log("wqfiles: source origin=persisted_store status=configured")
        } else {
            log("wqfiles: source origin=persisted_store status=not_configured")
        }
        add("/var/db/lsd")
        add("/var/mobile/Library/Caches")

        var result: [URL] = []
        var inaccessibleRoots = 0
        for root in cacheRoots {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else {
                inaccessibleRoots += 1
                log("wqfiles: source origin=cache_root status=inaccessible category=access_denied")
                continue
            }
            log("wqfiles: source origin=cache_root status=readable entries=\(names.count)")
            // WQFiles accepts every LaunchServices CSStore suffix. The
            // suffix is not stable across iOS 27 point releases.
            for name in names where name.hasPrefix("com.apple.LaunchServices-") && name.hasSuffix(".csstore") {
                result.append(URL(fileURLWithPath: (root as NSString).appendingPathComponent(name)))
            }
        }
        result.append(contentsOf: directStores)
        var unique: [URL] = []
        var paths = Set<String>()
        for url in result where paths.insert(url.path).inserted { unique.append(url) }
        log("wqfiles: source status=inventory roots=\(cacheRoots.count) inaccessible=\(inaccessibleRoots) candidates=\(unique.count)")
        return SourceInventory(stores: unique.sorted { $0.path < $1.path }, rootsChecked: cacheRoots.count, inaccessibleRoots: inaccessibleRoots)
    }

    private static func parse(data: Data) -> ParseOutcome {
        guard data.count >= 4, data.prefix(4) == Data("bdsl".utf8) else {
            return ParseOutcome(state: "invalid_header", identities: [:], recordsProcessed: 0, recordsRejected: 0)
        }
        let bytes = [UInt8](data)
        let strings = stringTable(bytes)
        guard !strings.isEmpty else {
            return ParseOutcome(state: "parse_failed", identities: [:], recordsProcessed: 0, recordsRejected: 0)
        }

        var choices: [[String: WQFilesResolvedIdentity]] = []
        var totalRecords = 0
        var totalRejected = 0
        for layout in layouts {
            var map: [String: WQFilesResolvedIdentity] = [:]
            var conflicts = Set<String>()
            guard bytes.count > Int(layout.bundleSize) + 8 else { continue }

            var offset = 0
            while offset + 8 + Int(layout.bundleSize) <= bytes.count {
                let size = read32(bytes, offset + 4)
                let body = offset + 8
                if size == layout.bundleSize {
                    totalRecords += 1
                    let bid = strings[read32(bytes, body + Int(layout.bundleID)) >> 2]
                    let path = strings[read32(bytes, body + Int(layout.container)) >> 2]
                    let name = strings[read32(bytes, body + Int(layout.displayName)) >> 2]
                        ?? strings[read32(bytes, body + Int(layout.nameRef)) >> 2]
                    if let bid, let path,
                       let canonical = applicationContainerPath(path),
                       isValidBundleID(bid),
                       let display = safeDisplayName(name, bundleID: bid) {
                        let identity = WQFilesResolvedIdentity(
                            containerPath: canonical,
                            bundleID: bid,
                            displayName: display,
                            source: "CSStore2/\(layout.name)",
                            storeSignature: "pending"
                        )
                        if let previous = map[canonical], previous.bundleID != bid {
                            conflicts.insert(canonical)
                        } else {
                            map[canonical] = identity
                        }
                    } else {
                        totalRejected += 1
                    }
                }
                offset += 4
            }
            for conflict in conflicts { map.removeValue(forKey: conflict) }
            if !map.isEmpty { choices.append(map) }
        }

        guard let best = choices.max(by: { $0.count < $1.count }) else {
            let state = totalRecords == 0 ? "unsupported_layout" : "no_matching_records"
            return ParseOutcome(state: state, identities: [:], recordsProcessed: totalRecords, recordsRejected: totalRejected)
        }
        // A known layout must produce a meaningful set. One accidental record is
        // not enough evidence to replace a UUID in the UI.
        guard best.count >= 2 else {
            return ParseOutcome(state: "validation_rejected", identities: [:], recordsProcessed: totalRecords, recordsRejected: totalRejected + best.count)
        }
        return ParseOutcome(state: "success", identities: best, recordsProcessed: totalRecords, recordsRejected: totalRejected)
    }

    private static func stringTable(_ bytes: [UInt8]) -> [UInt32: String] {
        var values: [UInt32: String] = [:]
        var ambiguous = Set<UInt32>()
        guard bytes.count >= 8 else { return [:] }
        var offset = 0
        while offset + 8 <= bytes.count {
            let id = read32(bytes, offset)
            let length = Int(read32(bytes, offset + 4))
            guard id > 0, id < 1_000_000, length > 0, length < 0x800,
                  offset + 8 + length <= bytes.count,
                  let value = String(bytes: bytes[(offset + 8)..<(offset + 8 + length)], encoding: .utf8),
                  !value.contains("\0") else {
                offset += 4
                continue
            }
            if let previous = values[id], previous != value { ambiguous.insert(id) }
            else if !ambiguous.contains(id) { values[id] = value }
            offset += 4
        }
        for id in ambiguous { values.removeValue(forKey: id) }
        return values
    }

    private static func read32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
            UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private static func isValidBundleID(_ value: String) -> Bool {
        ContainerBundleCandidateResolver.isValidBundleIdentifier(value) &&
            !value.hasPrefix("group.") && !value.hasPrefix("systemgroup.")
    }

    private static func safeDisplayName(_ value: String?, bundleID: String) -> String? {
        guard let value else { return bundleID }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.utf8.count <= 256,
              clean.rangeOfCharacter(from: .controlCharacters) == nil,
              UUID(uuidString: clean) == nil else { return bundleID }
        return clean
    }

    private static func sameFile(_ lhs: [FileAttributeKey: Any], _ rhs: [FileAttributeKey: Any]) -> Bool {
        lhs[.size] as? NSNumber == rhs[.size] as? NSNumber &&
            lhs[.modificationDate] as? Date == rhs[.modificationDate] as? Date &&
            lhs[.systemFileNumber] as? NSNumber == rhs[.systemFileNumber] as? NSNumber
    }

    private static func fileSignature(_ attributes: [FileAttributeKey: Any]) -> String {
        "\((attributes[.systemNumber] as? NSNumber)?.int64Value ?? 0):\((attributes[.systemFileNumber] as? NSNumber)?.int64Value ?? 0):\((attributes[.size] as? NSNumber)?.int64Value ?? 0):\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
    }
}
