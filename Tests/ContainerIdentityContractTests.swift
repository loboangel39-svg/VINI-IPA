import Darwin
import Foundation

@main
struct ContainerIdentityContractTests {
    private static var failures = 0

    static func main() {
        testAccessFailureIsNotSuccess()
        testFileListingAndGrantStates()
        testMetadataStates()
        testReinstallUsesCurrentPath()
        testCanonicalPathsAndMergeOrder()
        testFilesTabReinstallState()
        testPatchValidationPresentationStates()
        testPatchInstallationStates()
        testReceiptRejectsDifferentInstallation()
        testUUIDsAreNotPresentedAsApps()

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

    private enum SyntheticReadError: Error {
        case denied
    }

    private static func testFileListingAndGrantStates() {
        let empty = FileListingResult<Int>.capture { [] }
        let failed = FileListingResult<Int>.capture { throw SyntheticReadError.denied }
        require(empty == .success([]), "An empty directory must remain a successful listing")
        require(failed == .failure, "A failed directory read must not become an empty listing")

        var grantState = FileAccessGrantState()
        require(grantState.shouldAttemptGrant, "The first load must attempt a grant")
        grantState.record(grantHandle: -1, listingSucceeded: false)
        require(grantState.shouldAttemptGrant, "A failed grant and listing must remain retryable")
        grantState.record(grantHandle: 42, listingSucceeded: false)
        require(!grantState.shouldAttemptGrant, "A confirmed grant must not be requested repeatedly")
        print("PASS: empty, failed, and retryable Files states remain distinct")
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

        let duplicateAB = AppDataCatalogMerger.merge(
            identified: [enumerated[0], enumerated[1]],
            fallback: [],
            identifier: { _ in "com.example.same" },
            path: { $0.path }
        )
        let duplicateBA = AppDataCatalogMerger.merge(
            identified: [enumerated[1], enumerated[0]],
            fallback: [],
            identifier: { _ in "com.example.same" },
            path: { $0.path }
        )
        require(duplicateAB.map(\.path) == [enumerated[0].path], "[A, B] must preserve current first-wins priority")
        require(duplicateBA.map(\.path) == [enumerated[1].path], "[B, A] must preserve current first-wins priority")
        print("PASS: canonical path and merge order are preserved")
    }

    private static func testFilesTabReinstallState() {
        let bundleID = "com.example.reinstalled"
        let pathA = "/private/var/mobile/Containers/Data/Application/A"
        let pathB = "/private/var/mobile/Containers/Data/Application/B"
        let destinationA = FileBrowserDestination(
            containerPath: pathA,
            startPath: pathA,
            title: "Example A",
            bundleID: bundleID
        )
        let destinationB = FileBrowserDestination(
            containerPath: pathB,
            startPath: pathB,
            title: "Example B",
            bundleID: bundleID
        )
        var session = FilesTabSession()
        session.setActiveNavigationPath([destinationA])

        session.reconcileAppDestinations([destinationA])
        require(session.activeTab?.destinationStatus == .current, "Stable installation A must remain current")

        session.reconcileAppDestinations([])
        require(session.activeTab?.destinationStatus == .unavailable, "A must be marked unavailable while absent")
        require(session.activeTab?.navigationPath.first == destinationA, "An absent app must not silently rewrite the tab")

        session.reconcileAppDestinations([destinationB])
        require(session.activeTab?.destinationStatus == .replaced(destinationB), "Reinstalled B must mark the A tab stale")
        require(session.activeTab?.navigationPath.first == destinationA, "A stale tab must stay on A until user confirmation")

        let tabID = session.selectedTabID
        session.openCurrentInstallation(in: tabID)
        require(session.activeTab?.destinationStatus == .current, "Explicit open must clear the stale state")
        require(session.activeTab?.navigationPath == [destinationB], "Explicit open must navigate to current B")
        print("PASS: A -> absent -> B keeps A stale until B is explicitly opened")
    }

    private static func testPatchValidationPresentationStates() {
        let bundleID = "com.example.app"
        require(
            PatchTargetValidationResult.classify(
                hasResolvedTarget: false,
                hasWriteAccess: false,
                requestedBundleID: bundleID,
                metadataBundleID: nil
            ) == .unavailable,
            "Missing targets must remain unavailable"
        )
        require(
            PatchTargetValidationResult.classify(
                hasResolvedTarget: true,
                hasWriteAccess: false,
                requestedBundleID: bundleID,
                metadataBundleID: nil
            ) == .writeAccessDenied,
            "Write denial must not be presented as an uninstall"
        )
        require(
            PatchTargetValidationResult.classify(
                hasResolvedTarget: true,
                hasWriteAccess: true,
                requestedBundleID: bundleID,
                metadataBundleID: "com.example.other"
            ) == .identityMismatch,
            "Readable mismatched metadata must remain an identity mismatch"
        )
        require(
            PatchTargetValidationResult.classify(
                hasResolvedTarget: true,
                hasWriteAccess: true,
                requestedBundleID: bundleID,
                metadataBundleID: bundleID
            ) == .available,
            "A stable writable installation with matching identity must remain available"
        )
        require(
            PatchTargetValidationResult.classify(
                hasResolvedTarget: true,
                hasWriteAccess: true,
                requestedBundleID: bundleID,
                metadataBundleID: nil
            ) == .available,
            "Unavailable metadata must preserve the existing accepted state"
        )
        require(
            PatchPackageError.targetAppUnavailable(bundleID).localizationKey == "patch.error.app_unavailable"
                && PatchPackageError.targetWriteAccessDenied(bundleID).localizationKey == "patch.error.write_access_denied"
                && PatchPackageError.targetIdentityMismatch(bundleID).localizationKey == "patch.error.identity_mismatch",
            "Unavailable, denied, and mismatched targets must use distinct UI messages"
        )
        print("PASS: patch validation states remain distinct without weakening blocking")
    }

    private static func testPatchInstallationStates() {
        require(
            PatchInstallationStateResolver.resolve(
                observations: [.matches, .matches],
                hasVerifiableFiles: true
            ) == .installed,
            "Matching file content must be installed"
        )
        require(
            PatchInstallationStateResolver.resolve(
                observations: [.missing, .missing],
                hasVerifiableFiles: true
            ) == .notInstalled,
            "Confirmed missing targets must be not installed"
        )
        require(
            PatchInstallationStateResolver.resolve(
                observations: [.matches, .differs],
                hasVerifiableFiles: true
            ) == .modified,
            "Mixed or different target content must be modified"
        )
        require(
            PatchInstallationStateResolver.resolve(
                observations: [.missing, .unavailable],
                hasVerifiableFiles: true
            ) == .unknown,
            "An access failure must make the result unknown, not absent"
        )
        require(
            PatchInstallationStateResolver.resolve(
                observations: [.matches],
                hasVerifiableFiles: false
            ) == .unknown,
            "Directory presence alone must not prove patch installation"
        )
        print("PASS: installed, absent, modified, and unknown patch states remain distinct")
    }

    private static func testReceiptRejectsDifferentInstallation() {
        let fingerprintA = Data("/private/var/mobile/Containers/Data/Application/A".utf8)
        let fingerprintB = Data("/private/var/mobile/Containers/Data/Application/B".utf8)
        do {
            try PatchReceiptContainerValidator.validate(
                bundleID: "com.example.reinstalled",
                expectedFingerprint: fingerprintA,
                currentFingerprint: fingerprintB
            )
            require(false, "A receipt for A must not be accepted on B")
        } catch let error as PatchPackageError {
            require(
                error == .targetContainerChanged("com.example.reinstalled"),
                "A receipt for A must report container changed on B"
            )
        } catch {
            require(false, "A receipt mismatch must use the patch error taxonomy")
        }
        print("PASS: receipt fingerprint mismatch blocks B as a changed container")
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

    private static func require(_ condition: Bool, _ message: String) {
        if condition {
            return
        }
        failures += 1
        print("FAIL: \(message)")
    }
}
