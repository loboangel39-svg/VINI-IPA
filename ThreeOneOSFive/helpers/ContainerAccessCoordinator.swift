import Foundation

enum ContainerAccessOperation: Equatable { case read, write }

final class ContainerAccessSession {
    let path: String
    let provider: String
    let diagnostic: String
    private let handle: Int64

    fileprivate init(path: String, provider: String, diagnostic: String, handle: Int64) {
        self.path = path; self.provider = provider; self.diagnostic = diagnostic; self.handle = handle
    }

    deinit {
        if handle >= 0 && provider == "bad_query" { bad_query_release(handle) }
        if handle >= 0 && provider == "worse_query" { WQAccessProviderRelease(handle) }
    }
}

enum ContainerAccessCoordinator {
    static func acquire(bundleID: String?, containerPath: String, operation: ContainerAccessOperation) -> Result<ContainerAccessSession, Error> {
        let expected = ContainerDiscoveryMerger.canonicalPath(containerPath)
        guard expected.hasPrefix("/") else {
            return .failure(NSError(domain: "ContainerAccess", code: 1, userInfo: [NSLocalizedDescriptionKey: "container does not exist: \(containerPath)"]))
        }
        if #available(iOS 26.0, *), wq_grant(expected),
           verifyEffectiveAccess(at: expected, operation: operation) {
            return .success(ContainerAccessSession(path: expected, provider: "WQAccess", diagnostic: "effective access verified; grant held by WQAccess LRU", handle: -1))
        }
        if let bundleID, let resolved = resolveMHA(bundleID), ContainerDiscoveryMerger.canonicalPath(resolved) == expected {
            if verifyEffectiveAccess(at: expected, operation: operation) {
                return .success(ContainerAccessSession(path: expected, provider: "MHA-C2", diagnostic: "effective access verified", handle: -1))
            }
        }

        var cPath = expected.utf8CString.map { Int8($0) }
        let badHandle = bad_query(&cPath, false, nil, false)
        if badHandle >= 0 {
            if verifyEffectiveAccess(at: expected, operation: operation) {
                return .success(ContainerAccessSession(path: expected, provider: "bad_query", diagnostic: "sandbox extension and effective access verified", handle: badHandle))
            }
            bad_query_release(badHandle)
        }

        var detail: NSString?
        let worseHandle = WQAccessProviderAcquire(expected, &detail)
        if worseHandle >= 0 {
            if verifyEffectiveAccess(at: expected, operation: operation) {
                return .success(ContainerAccessSession(path: expected, provider: "worse_query", diagnostic: "sandbox extension and effective access verified", handle: worseHandle))
            }
            WQAccessProviderRelease(worseHandle)
        }
        let mode = operation == .write ? "write" : "read"
        let message = "no provider granted effective \(mode) access; bad_query=\(badHandle), worse_query=\(detail.map(String.init) ?? "unavailable")"
        log("access: \(message) path=\(expected)")
        return .failure(NSError(domain: "ContainerAccess", code: 2, userInfo: [NSLocalizedDescriptionKey: message]))
    }

    static func withAccess<T>(bundleID: String?, containerPath: String, operation: ContainerAccessOperation, _ body: () throws -> T) throws -> T {
        let session = try acquire(bundleID: bundleID, containerPath: containerPath, operation: operation).get()
        return try withExtendedLifetime(session) { try body() }
    }

    private static func resolveMHA(_ bundleID: String) -> String? {
        var error: NSString?
        return MCMActivateContainerPath(2, bundleID, false, &error)
    }

    private static func verifyEffectiveAccess(at path: String, operation: ContainerAccessOperation) -> Bool {
        let files = FileManager.default
        switch operation {
        case .read:
            return (try? files.contentsOfDirectory(atPath: path)) != nil
        case .write:
            let probe = (path as NSString).appendingPathComponent(".3105-access-probe-\(UUID().uuidString)")
            guard files.createFile(atPath: probe, contents: Data(), attributes: nil) else { return false }
            try? files.removeItem(atPath: probe)
            return true
        }
    }
}
