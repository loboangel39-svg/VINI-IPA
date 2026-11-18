import Foundation

/// The two sandbox-access mechanisms VINI knows about.
///
/// This type deliberately says nothing about Bundle ID resolution or container
/// identity. It only chooses which *access* mechanism is attempted first.
enum ContainerAccessProvider: String, Hashable {
    case badQuery = "bad_query"
    case worseQuery = "worse_query"
}

struct ContainerAccessProviderDecision: Equatable {
    /// Provider requested by the version map supplied for this integration.
    let requestedByMap: ContainerAccessProvider
    /// Providers in the order they may be attempted. Always sequential.
    let attemptOrder: [ContainerAccessProvider]
    /// Whether the requested range could be confirmed from a build table that
    /// VINI already ships. `false` means "requested, not device-verified".
    let mapVerified: Bool
    /// Whether upstream worse_query declares support for this OS version.
    let worseQueryCompatible: Bool
    let notes: [String]

    var preferred: ContainerAccessProvider {
        attemptOrder.first ?? .badQuery
    }
}

/// Conservative provider-selection policy.
///
/// The map requested for this integration is:
///   - iOS 26.0 - 26.6.1          -> bad_query
///   - iOS 26.6.2 - 26.7.2        -> worse_query
///   - iOS 27.0 beta 1 - beta 4   -> bad_query
///   - iOS 27.0 beta 5 - 27.3 b1  -> worse_query
///
/// Two facts keep this honest:
///   1. VINI's existing support table only identifies 27.0 beta 1-4 builds.
///   2. Upstream worse_query documents support through 27.2, not 27.3 beta 1.
///
/// When the requested provider cannot be confirmed or is outside upstream's
/// declared range, the existing bad_query order is retained and the reason is
/// recorded. The policy never runs two mechanisms at once; the caller tries
/// them sequentially and stops at the first successful grant.
enum WorseQueryProviderPolicy {
    static let requestedMapDescription =
        "26.0-26.6.1:bad_query; 26.6.2-26.7.2:worse_query; " +
        "27.0b1-b4:bad_query; 27.0b5-27.3b1:worse_query"
    static let upstreamSupportedDescription = "iOS 26.0-26.7.2 and iOS 27.0-27.2"
    static let viniVerifiedDescription = "iOS 26.0-26.6.1 and iOS 27.0 beta 1-4"

    static func decision(
        major: Int,
        minor: Int,
        patch: Int,
        build: String
    ) -> ContainerAccessProviderDecision {
        let requested = requestedProvider(
            major: major,
            minor: minor,
            patch: patch,
            build: build
        )
        let compatible = isWorseQueryCompatibleOS(
            major: major,
            minor: minor,
            patch: patch
        )
        let verified = isRequestedRangeVerified(
            major: major,
            minor: minor,
            patch: patch,
            build: build
        )

        var notes: [String] = []
        if major == 27, minor == 0,
           ExploitSupportPolicy.iOS27BetaNumber(for: build) == nil {
            notes.append(
                "iOS 27.0 build '\(build)' is not in VINI's verified beta table; " +
                "beta 5+ mapping cannot be confirmed"
            )
        }
        if requested == .worseQuery, !compatible {
            notes.append(
                "requested map selects worse_query, but upstream declares support " +
                "only through iOS 27.2; keeping bad_query priority"
            )
        }
        if requested == .badQuery {
            notes.append("existing bad_query priority retained")
        }
        if !compatible {
            notes.append("worse_query will not be attempted on this OS version")
        }

        // Outside upstream's declared range the requested provider must not be
        // attempted at all, even when the map asks for it. Keep the existing
        // provider instead of running an unverified mechanism.
        let order: [ContainerAccessProvider]
        if compatible {
            let fallback: ContainerAccessProvider =
                requested == .badQuery ? .worseQuery : .badQuery
            order = [requested, fallback]
        } else {
            order = [.badQuery]
        }

        return ContainerAccessProviderDecision(
            requestedByMap: requested,
            attemptOrder: order,
            mapVerified: verified,
            worseQueryCompatible: compatible,
            notes: notes
        )
    }

    static func requestedProvider(
        major: Int,
        minor: Int,
        patch: Int,
        build: String
    ) -> ContainerAccessProvider {
        guard minor >= 0, patch >= 0 else { return .badQuery }

        if major == 26 {
            if minor < 6 || (minor == 6 && patch <= 1) {
                return .badQuery
            }
            if minor == 7 && patch <= 2 {
                return .worseQuery
            }
            return .badQuery
        }

        if major == 27 {
            if minor == 0 {
                // The only builds VINI can currently identify are beta 1-4.
                // Anything else is left on the existing provider rather than
                // guessing which beta a build string represents.
                if let beta = ExploitSupportPolicy.iOS27BetaNumber(for: build) {
                    return beta <= 4 ? .badQuery : .worseQuery
                }
                return .badQuery
            }
            if minor == 1 || minor == 2 {
                return .worseQuery
            }
            if minor == 3 {
                // Requested by the integration map, but outside upstream's
                // declared 27.2 ceiling. The decision carries a note and the
                // compatibility gate below prevents its use.
                return .worseQuery
            }
            return .badQuery
        }

        return .badQuery
    }

    /// Upstream README: iOS 26.0 - 26.7.2 and iOS 27.2.
    /// Patch-level ceilings are interpreted conservatively.
    static func isWorseQueryCompatibleOS(
        major: Int,
        minor: Int,
        patch: Int
    ) -> Bool {
        guard minor >= 0, patch >= 0 else { return false }
        if major == 26 {
            return minor < 7 || (minor == 7 && patch <= 2)
        }
        if major == 27 {
            return minor <= 2
        }
        return false
    }

    static func isRequestedRangeVerified(
        major: Int,
        minor: Int,
        patch: Int,
        build: String
    ) -> Bool {
        if major == 26 {
            return minor < 6 || (minor == 6 && patch <= 1)
        }
        if major == 27, minor == 0 {
            return ExploitSupportPolicy.iOS27BetaNumber(for: build) != nil
        }
        return false
    }
}
