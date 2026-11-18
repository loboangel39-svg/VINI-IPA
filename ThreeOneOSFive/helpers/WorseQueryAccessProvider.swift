import Darwin
import Foundation

enum WorseQueryAccessError: Error, CustomStringConvertible {
    case invalidPath(String)
    case unsupportedOS(String)
    case unavailableAppGroup
    case upstream(code: Int64, detail: String)
    case verificationFailed(path: String, errno: Int32)

    var description: String {
        switch self {
        case .invalidPath(let path):
            return "invalid path '\(path)'"
        case .unsupportedOS(let version):
            return "worse_query is outside its declared range on iOS \(version)"
        case .unavailableAppGroup:
            return "no signed, reachable App Group is available to worse_query"
        case .upstream(let code, let detail):
            return "worse_query returned \(code) (\(detail))"
        case .verificationFailed(let path, let code):
            return "worse_query grant did not permit the requested operation on \(path) errno=\(code)"
        }
    }
}

/// Additional per-path sandbox access provider.
///
/// This adapter only consumes an already-resolved path. It never enumerates
/// applications, never maps a Bundle ID to a UUID, and never substitutes for
/// MHA-C2 or `bad_query`. The upstream implementation is vendored unmodified;
/// this type owns the extension handle and verifies that the grant actually
/// covers the operation the caller is about to perform.
enum WorseQueryAccessProvider {
    /// worse_query mutates one shared `Library/Caches` symlink inside the App
    /// Group, so calls must not overlap.
    private static let callLock = NSLock()

    /// Entitlements cannot change during a process lifetime, so resolving the
    /// authorized group once avoids repeated Security queries during scans.
    private static let resolvedAppGroup: String? = WQAuthorizedAppGroup()

    static func isCompatibleWithCurrentOS() -> Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return WorseQueryProviderPolicy.isWorseQueryCompatibleOS(
            major: version.majorVersion,
            minor: version.minorVersion,
            patch: version.patchVersion
        )
    }

    static var isAvailable: Bool {
        isCompatibleWithCurrentOS() && authorizedAppGroup() != nil
    }

    static func authorizedAppGroup() -> String? {
        guard let group = resolvedAppGroup, !group.isEmpty else {
            return nil
        }
        return group
    }

    /// Acquires a sandbox extension for `path`.
    ///
    /// - Parameter requiringWrite: when true the grant is only returned if the
    ///   process can actually write to `path` after consuming the extension.
    /// - Returns: a handle owned by the caller; release it with `release(_:)`.
    static func acquire(
        path: String,
        requiringWrite: Bool
    ) -> Result<Int64, WorseQueryAccessError> {
        guard path.hasPrefix("/"), !path.contains("\n"), !path.contains("\0") else {
            return .failure(.invalidPath(path))
        }

        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard WorseQueryProviderPolicy.isWorseQueryCompatibleOS(
            major: version.majorVersion,
            minor: version.minorVersion,
            patch: version.patchVersion
        ) else {
            return .failure(.unsupportedOS(AppInfo.osVersion))
        }

        guard let group = authorizedAppGroup() else {
            return .failure(.unavailableAppGroup)
        }

        callLock.lock()
        defer { callLock.unlock() }

        // Upstream needs the alternate flags for 26.x App Group containers.
        let altFlags = version.majorVersion == 26
        let handle = worse_query(path, group, altFlags, false)
        guard handle >= 0 else {
            return .failure(.upstream(
                code: handle,
                detail: upstreamDetail(for: handle)
            ))
        }

        var required = R_OK | X_OK
        if requiringWrite {
            required |= W_OK
        }
        guard access(path, required) == 0 else {
            let code = errno
            worse_query_release(handle)
            return .failure(.verificationFailed(path: path, errno: code))
        }

        return .success(handle)
    }

    static func release(_ handle: Int64) {
        guard handle >= 0 else { return }
        // worse_query_release and bad_query_release both call the same
        // sandbox_extension_release symbol. Keep the upstream release here for
        // clarity when the handle came from this adapter.
        worse_query_release(handle)
    }

    private static func upstreamDetail(for code: Int64) -> String {
        switch code {
        case -255: return "target does not exist and create_dir is false"
        case -1: return "App Group container unavailable"
        case -2: return "containermanager library or symbols unavailable"
        case -3: return "container query creation failed"
        case -4: return "App Group Caches symlink could not be created"
        case -5: return "container query rejected by containermanagerd"
        case -6: return "containermanagerd returned no sandbox token"
        default: return "sandbox extension was not issued"
        }
    }
}
