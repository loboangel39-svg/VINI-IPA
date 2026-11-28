import SwiftUI
import UIKit

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var remotePatchCoordinator = RemotePatchImportCoordinator()
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @AppStorage("sessionExpiresAt") private var sessionExpiresAt: Double = 0
    @AppStorage("licenseExpiresAt") private var licenseExpiresAt: Double = 0
    @AppStorage("licensePlan") private var licensePlan = ""
    @AppStorage("currentLicenseKey") private var currentLicenseKey = ""
    @StateObject private var accessCoordinator = AccessStateCoordinator()
    @State private var isCheckingAutoLogin = true
    @State private var isCheckingSession = false
    @StateObject private var repositoryStore = PackageRepositoryStore()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.spanish.rawValue
    // Temporarily disconnected from navigation; retained for reversible restoration.
    @State private var showOnboarding = false
    @State private var showAttribution = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        setupLogCapture()
        WQIntegratedInitialize()
        log("app: 3105 launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .spanish
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if isCheckingAutoLogin {
                        VINIStartupView()
                    } else if isLoggedIn {
                        authorizedRootContent
                    } else {
                        LoginView { license, expiresAt, licenseExpiration, plan, access in
                            currentLicenseKey = license
                            isLoggedIn = true
                            sessionExpiresAt = expiresAt?.timeIntervalSince1970 ?? 0
                            licenseExpiresAt = licenseExpiration?.timeIntervalSince1970 ?? 0
                            licensePlan = plan ?? ""
                            accessCoordinator.apply(access)
                            if shouldSynchronizeRemotePatches(for: access) { synchronizeRemotePatches() }
                        }
                    }
                }
                .opacity(showOnboarding && isLoggedIn ? 0 : 1)
                .allowsHitTesting(!(showOnboarding && isLoggedIn))

                if showOnboarding && isLoggedIn {
                    OnboardingView {
                        OnboardingStore.markCompleted()
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                            showOnboarding = false
                        }
                        appState.detectSupport()
                        Task { await attemptAutoLogin() }
                    }
                    .environment(\.appLanguage, language)
                    .environment(\.locale, language.locale)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.98))
                    )
                    .zIndex(1)
                }
            }
            .displayIdentityAttribution(isPresented: $showAttribution, enabled: !showOnboarding)
            .sheet(isPresented: $showAttribution) {
                DisplayAttributionSheet()
            }
            .onAppear {
                if !showOnboarding {
                    appState.detectSupport()
                }
            }
            .task { await attemptAutoLogin() }
            .task { await refreshLicenseExpirationLoop() }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, !showOnboarding else { return }
                appState.detectSupport()
                if isLoggedIn, !isCheckingSession {
                    Task { await checkSessionValidityAsync() }
                }
            }
            .onOpenURL { url in
                patchDraftCoordinator.presentImport(url)
            }
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private var authorizedRootContent: some View {
        switch accessCoordinator.status {
        case "maintenance":
            MaintenanceView(accessState: accessCoordinator.state, onRefresh: refreshAccessState)
        case "license_paused":
            PausedLicenseView(accessState: accessCoordinator.state, onRefresh: refreshAccessState)
        default:
            ContentView()
                .environmentObject(appState)
                .environmentObject(patchDraftCoordinator)
                .environmentObject(fileOperationCoordinator)
                .environmentObject(patchStore)
                .environmentObject(repositoryStore)
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
        }
    }

    private func refreshAccessState() {
        Task { await checkSessionValidityAsync() }
    }

    private func attemptAutoLogin() async {
        print("[AUTH-DIAG] attemptAutoLogin begin isLoggedIn=\(isLoggedIn) authTokenPresent=\(KeychainManager.shared.loadAuthToken() != nil) jwtExpiredLocal=\(String(describing: LoginManager.diagnosticStoredTokenIsExpired())) licensePresent=\(KeychainManager.shared.loadLicenseKey() != nil) hwidPresent=\(KeychainManager.shared.loadHWID() != nil) usernamePresent=\(KeychainManager.shared.loadUsername() != nil)")
        if isLoggedIn {
            await checkSessionValidityAsync()
            isCheckingAutoLogin = false
            if isLoggedIn { synchronizeRemotePatches() }
            return
        }
        if KeychainManager.shared.loadAuthToken() != nil {
            print("[AUTH-DIAG] verifyStoredSession begin")
            let storedSessionValid = await withCheckedContinuation { continuation in
                LoginManager.verifyStoredSession { result in
                    switch result {
                    case .valid:
                        print("[AUTH-DIAG] verifyStoredSession result=valid")
                    case .revoked:
                        print("[AUTH-DIAG] verifyStoredSession result=revoked")
                    case .networkError:
                        print("[AUTH-DIAG] verifyStoredSession result=networkError")
                    }
                    if case .revoked = result {
                        print("[AUTH-DIAG] clearActivationCredentials reason=stored-session-revoked")
                        LoginManager.clearActivationCredentials()
                        isLoggedIn = false
                        currentLicenseKey = ""
                        sessionExpiresAt = 0
                        licenseExpiresAt = 0
                        licensePlan = ""
                        accessCoordinator.clear()
                        log("[AUTH] stored session revoked; manual login required")
                    }
                    continuation.resume(returning: result)
                }
            }
            if case .revoked = storedSessionValid {
                isCheckingAutoLogin = false
                return
            }
            if case .networkError = storedSessionValid {
                log("[AUTH] stored session check unavailable; showing login without rebinding")
                isCheckingAutoLogin = false
                return
            }
        }
        print("[AUTH-DIAG] tryAutoLogin begin licensePresent=\(KeychainManager.shared.loadLicenseKey() != nil) hwidPresent=\(KeychainManager.shared.loadHWID() != nil)")
        await withCheckedContinuation { continuation in
            LoginManager.tryAutoLogin { success, license, expiresAt, licenseExpiration, plan, access in
                Task { @MainActor in
                    print("[AUTH-DIAG] tryAutoLogin result success=\(success) licenseReturned=\(license != nil)")
                    if success, let license {
                        currentLicenseKey = license
                        isLoggedIn = true
                        sessionExpiresAt = expiresAt?.timeIntervalSince1970 ?? 0
                        licenseExpiresAt = licenseExpiration?.timeIntervalSince1970 ?? 0
                        licensePlan = plan ?? ""
                        accessCoordinator.apply(access)
                        log("app: auto-login successful")
                        if shouldSynchronizeRemotePatches(for: access) { synchronizeRemotePatches() }
                    } else {
                        log("app: auto-login unavailable; showing original login")
                        print("[AUTH-DIAG] LoginView reason=tryAutoLogin-failed")
                    }
                    isCheckingAutoLogin = false
                    continuation.resume()
                }
            }
        }
    }

    private func synchronizeRemotePatches() {
        Task { await remotePatchCoordinator.sync(into: patchStore) }
    }

    /// Preserve the legacy remote-patch contract when an older Worker does
    /// not return `access`. Only an explicit server-side blocking state may
    /// suppress patch synchronization.
    private func shouldSynchronizeRemotePatches(for access: ServerAccessState?) -> Bool {
        guard let status = access?.status else { return true }
        return status != "maintenance"
            && status != "license_paused"
            && status != "expired"
            && status != "unauthorized"
    }

    private func checkSessionValidityAsync() async {
        guard isLoggedIn, !isCheckingSession else { return }
        isCheckingSession = true
        defer { isCheckingSession = false }
        if sessionExpiresAt > 0, Date() > Date(timeIntervalSince1970: sessionExpiresAt) {
            print("[AUTH-DIAG] LoginView reason=local-session-expired")
            logout()
            log("[AUTH] local expiration rejected session")
            return
        }
        log("[AUTH] session check started")
        let valid = await withCheckedContinuation { continuation in
            LoginManager.verifyStoredSession { result in
                continuation.resume(returning: result)
            }
        }
        switch valid {
        case .valid(let licenseExpiration, let plan, let access):
            if let licenseExpiration {
                licenseExpiresAt = licenseExpiration.timeIntervalSince1970
            }
            licensePlan = plan ?? ""
            accessCoordinator.apply(access)
            log("[AUTH] session access state: \(access?.status ?? "legacy")")
            if access?.status == "expired" || access?.status == "unauthorized" {
                logout()
                return
            }
            log("[AUTH] session check accepted")
            if access?.status == "maintenance" || access?.status == "license_paused" {
                return
            }
            synchronizeRemotePatches()
        case .revoked:
            log("[AUTH] session check revoked; showing login")
            print("[AUTH-DIAG] LoginView reason=session-revoked clearActivationCredentials=via-logout")
            logout()
        case .networkError:
            log("[AUTH] session check unavailable; keeping current session")
        }
    }

    private func refreshLicenseExpirationLoop() async {
        // attemptAutoLogin performs the opening check; this task handles the
        // steady-state poll without creating a second opening request.
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled, isLoggedIn else { continue }
            await checkSessionValidityAsync()
        }
    }

    private func logout() {
        isLoggedIn = false
        sessionExpiresAt = 0
        licenseExpiresAt = 0
        licensePlan = ""
        currentLicenseKey = ""
        accessCoordinator.clear()
        RemotePatchService.shared.clearAuth()
        LoginManager.clearActivationCredentials()
        log("app: session expired or invalidated")
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false

    private var autoRunAttempted = false

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild
        )
    }

    var isSupported: Bool { unsupportedMessage == nil }

    func detectSupport() {
        let v = AppInfo.versionTuple
        let exploitSupported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
        let supported = exploitSupported || WorseQuerySupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild
        )
        guard applicable else { return }

        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }

    private func maybeAutoRunKernelExploit() {
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed,
              !autoRunAttempted else { return }
        autoRunAttempted = true
        log("app: starting kernel exploit automatically")
        runKernelExploitIfNeeded()
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        // iOS < 26: kernel R/W success persists (no sandbox probe)
        // iOS >= 26: verify full sandbox escape is still active
        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: "kexploit")
                    log("app: existing sandbox access is still active; skipping kernel exploit")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded() {
        refreshKernelExploitStatus()
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        log("app: running kernel exploit on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if ok {
                    self.exploitStatus = .success(method: "kexploit")
                    if KernelExploit.requiresSandboxEscape {
                        log("app: kernel exploit success — sandbox access verified")
                    } else {
                        log("app: kernel exploit success — kernel access active")
                    }
                } else {
                    self.exploitStatus = .failed(method: "kexploit", code: -1)
                    log("app: kernel exploit failed — relaunch the app before retrying")
                }
            }
        }
    }
}
