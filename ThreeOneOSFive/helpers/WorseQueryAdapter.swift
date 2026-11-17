import Foundation

/// Keeps the upstream implementation untouched and owns its sandbox extension handle.
enum WorseQueryAdapter {
    static let sourceAppGroup = "group.cc.forcequit.worse-query"

    enum AccessError: Error, CustomStringConvertible {
        case unsupportedOS
        case unavailableAppGroup
        case upstreamCode(Int64)

        var description: String {
            switch self {
            case .unsupportedOS: return "worse_query is not supported on this iOS version"
            case .unavailableAppGroup: return "worse_query App Group is unavailable to this signed app"
            case .upstreamCode(let code): return "worse_query returned \(code)"
            }
        }
    }

    static func acquire(path: String) -> Result<Int64, AccessError> {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard version.majorVersion >= 26 else { return .failure(.unsupportedOS) }
        guard FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: sourceAppGroup
        ) != nil else { return .failure(.unavailableAppGroup) }

        let handle = worse_query(path, sourceAppGroup, true, false)
        guard handle >= 0 else { return .failure(.upstreamCode(handle)) }
        return .success(handle)
    }

    static func release(_ handle: Int64) {
        worse_query_release(handle)
    }
}
