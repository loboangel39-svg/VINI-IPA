import Foundation
import Combine

struct DiscoveredAppIdentity: Identifiable, Equatable {
    enum Status: String {
        case discovered
        case resolved
        case accessible
        case unavailable
    }

    let bundleID: String
    let displayName: String
    var status: Status
    var id: String { bundleID }
}

/// Files publishes its existing discovery results here; no second enumeration runs.
final class DiscoveredAppCatalog: ObservableObject {
    static let shared = DiscoveredAppCatalog()
    @Published private(set) var identities: [DiscoveredAppIdentity] = []

    private init() {}

    func clear() {
        updateOnMain { self.identities = [] }
    }

    func publish(_ apps: [InstalledApp]) {
        var seen = Set<String>()
        let current = apps.compactMap { app -> DiscoveredAppIdentity? in
            guard ContainerBundleCandidateResolver.isValidBundleIdentifier(app.bundleID),
                  seen.insert(app.bundleID).inserted else { return nil }
            return DiscoveredAppIdentity(
                bundleID: app.bundleID,
                displayName: app.displayName,
                status: .discovered
            )
        }
        updateOnMain {
            let previous = Dictionary(
                self.identities.map { ($0.bundleID, $0.status) },
                uniquingKeysWith: { first, _ in first }
            )
            self.identities = current.map { identity in
                var value = identity
                value.status = previous[identity.bundleID] ?? .discovered
                return value
            }
        }
    }

    func mark(_ bundleID: String, status: DiscoveredAppIdentity.Status) {
        updateOnMain {
            guard let index = self.identities.firstIndex(where: { $0.bundleID == bundleID }) else {
                return
            }
            self.identities[index].status = status
        }
    }

    private func updateOnMain(_ update: @escaping () -> Void) {
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }
}
