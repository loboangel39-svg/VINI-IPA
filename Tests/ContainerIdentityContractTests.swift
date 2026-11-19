import Darwin
import Foundation

@main
struct ContainerIdentityContractTests {
    private static var failures = 0

    static func main() {
        testAccessFailureIsNotSuccess()
        testMetadataStates()
        testReinstallUsesCurrentPath()
        testAPIStalePathPrefersCurrentMCMPath()
        testMissingMetadataDoesNotBecomeUninstalled()
        testCanonicalPathsAndMergeOrder()
        testUUIDsAreNotPresentedAsApps()
        testUnknownContainerIsNotAnAppIdentity()

        if failures == 0 {
            print("PASS: all ContainerIdentity contract tests")
            exit(0)
        } else {
            print("FAIL: \(failures) assertion(s)")
            exit(1)
        }
    }

    private static func testAccessFailureIsNotSuccess() {
        var metadataLoaded = false
        let result = ContainerIdentityResolver.resolve(
            containerPath: "/private/var/mobile/Containers/Data/Application/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            grantAccess: { _ in -3 },
            releaseAccess: { _ in },
            loadMetadata: { _ in
                metadataLoaded = true
                return ContainerMetadata(bundleID: "com.example.app", displayName: "Example")
            }
        )
        require(result == .accessFailed(-3), "A denied grant must remain a failure")
        require(!metadataLoaded, "Metadata must not be read without a grant")
        print("PASS: denied access is not converted into a positive result")
    }

    private static func testMetadataStates() {
        let missing = ContainerIdentityResolver.resolve(
            containerPath: "/private/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555",
            grantAccess: { _ in 7 },
            releaseAccess: { _ in },
            loadMetadata: { _ in nil }
        )
        require(missing == .metadataUnavailable, "Missing metadata must stay unavailable")

        let systemGroup = ContainerIdentityResolver.resolve(
            containerPath: "/private/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555",
            grantAccess: { _ in 7 },
            releaseAccess: { _ in },
            loadMetadata: { _ in
                ContainerMetadata(bundleID: "systemgroup.com.apple.example", displayName: "")
            }
        )
        require(
            systemGroup == .unsupportedIdentifier("systemgroup.com.apple.example"),
            "System groups must not become app identities"
        )

        let resolved = ContainerIdentityResolver.resolve(
            containerPath: "/private/var/mobile/Containers/Data/Application/11111111-2222-3333-4444-555555555555",
            grantAccess: { _ in 7 },
            releaseAccess: { _ in },
            loadMetadata: { _ in
                ContainerMetadata(bundleID: "com.example.app", displayName: "Example")
            }
        )
        require(
            resolved == .resolved(ContainerMetadata(bundleID: "com.example.app", displayName: "Example")),
            "A matching metadata identity must resolve"
        )
        print("PASS: identity resolver keeps failure and unsupported states distinct")
    }

    private static func testReinstallUsesCurrentPath() {
        var currentPath = "/private/var/mobile/Containers/Data/Application/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        var currentMetadata = ContainerMetadata(bundleID: "com.example.reinstalled", displayName: "Reinstalled")
        var released: [Int64] = []

        func resolveCurrent() -> ContainerResolution {
            ContainerIdentityResolver.resolve(
                containerPath: currentPath,
                grantAccess: { _ in 42 },
                releaseAccess: { released.append($0) },
                loadMetadata: { _ in currentMetadata }
            )
        }

        let first = resolveCurrent()
        // Simulate a reinstall: same Bundle ID, a different current UUID.
        currentPath = "/private/var/mobile/Containers/Data/Application/BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        currentMetadata = ContainerMetadata(bundleID: "com.example.reinstalled", displayName: "Reinstalled")
        let second = resolveCurrent()

        require(
            first == .resolved(ContainerMetadata(bundleID: "com.example.reinstalled", displayName: "Reinstalled")),
            "First installation must resolve"
        )
        require(
            second == .resolved(ContainerMetadata(bundleID: "com.example.reinstalled", displayName: "Reinstalled")),
            "Second installation must resolve through the current path"
        )
        require(released == [42, 42], "Every grant must be released")
        print("PASS: reinstall re-resolves the current UUID instead of caching the old one")
    }

    private static func testAPIStalePathPrefersCurrentMCMPath() {
        let oldPath = "/private/var/mobile/Containers/Data/Application/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        let newPath = "/private/var/mobile/Containers/Data/Application/BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        let selected = CurrentContainerPathResolver.select(
            bundleID: "com.example.reinstalled",
            apiPath: oldPath,
            mcmPath: newPath,
            pathExists: { $0 == oldPath || $0 == newPath }
        )
        require(selected == newPath, "A current MCM path must replace a stale API UUID")
        print("PASS: stale API UUID is replaced by current MCM path")
    }

    private static func testMissingMetadataDoesNotBecomeUninstalled() {
        let path = "/private/var/mobile/Containers/Data/Application/CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        let selected = CurrentContainerPathResolver.select(
            bundleID: "com.example.pending",
            apiPath: path,
            mcmPath: nil,
            pathExists: { _ in true }
        )
        require(selected == path, "A valid container remains present while metadata is temporarily unavailable")
        print("PASS: temporary identity metadata loss is not treated as uninstallation")
    }

    private static func testCanonicalPathsAndMergeOrder() {
        require(
            ContainerDiscoveryMerger.canonicalPath("/var/mobile/Containers/Data/Application/X/")
                == "/private/var/mobile/Containers/Data/Application/X",
            "Canonical path must map /var and remove the trailing slash"
        )

        struct Item: Equatable {
            let id: String
            let path: String
        }

        let enumerated = [
            Item(id: "fallback-a", path: "/var/mobile/Containers/Data/Application/A"),
            Item(id: "fallback-b", path: "/var/mobile/Containers/Data/Application/B")
        ]
        let identified = [
            Item(id: "com.example.b", path: "/private/var/mobile/Containers/Data/Application/B")
        ]
        let merged = ContainerDiscoveryMerger.merge(
            enumerated: enumerated,
            identified: identified,
            path: { $0.path }
        )
        require(merged.map(\.path) == [
            "/var/mobile/Containers/Data/Application/A",
            "/private/var/mobile/Containers/Data/Application/B"
        ], "Merge must preserve order and replace the identified path in place")
        require(merged.map(\.id) == ["fallback-a", "com.example.b"], "Identified metadata must win")
        print("PASS: canonical path and merge order are preserved")
    }

    private static func testUUIDsAreNotPresentedAsApps() {
        require(
            !ContainerPresentationPolicy.shouldShow(
                bundleID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
            ),
            "A raw UUID must not be presented as an app identity"
        )
        require(
            ContainerPresentationPolicy.shouldShow(bundleID: "com.example.app"),
            "A real Bundle ID must remain visible"
        )
        require(
            AppDisplayNamePolicy.resolve(
                bundleID: "com.example.app",
                candidates: ["AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"]
            ) == "com.example.app",
            "A UUID must not become a display name"
        )
        print("PASS: UUIDs are not presented as app identities")
    }

    private static func testUnknownContainerIsNotAnAppIdentity() {
        let unknown = UnidentifiedContainer(
            containerPath: "/private/var/mobile/Containers/Data/Application/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            source: "filesystem/inode",
            reason: "identity_unresolved"
        )
        require(UUID(uuidString: unknown.uuid) != nil, "Unknown container keeps its UUID")
        require(!ContainerPresentationPolicy.shouldShow(bundleID: unknown.uuid),
                "Unknown UUID must not be presented as a Bundle ID")
        require(unknown.reason == "identity_unresolved", "Unknown reason remains explicit")
        print("PASS: unknown containers remain diagnostic-only")
    }

    private static func require(_ condition: Bool, _ message: String) {
        if condition {
            return
        }
        failures += 1
        print("FAIL: \(message)")
    }
}
