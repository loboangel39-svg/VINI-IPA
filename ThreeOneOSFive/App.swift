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
                        ProgressView("VINI V2")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isLoggedIn {
                        ContentView()
                            .environmentObject(appState)
                            .environmentObject(patchDraftCoordinator)
                            .environmentObject(fileOperationCoordinator)
                            .environmentObject(patchStore)
                            .environmentObject(repositoryStore)
                            .environment(\.appLanguage, language)
                            .environment(\.locale, language.locale)
                    } else {
                        LoginView { license, expiresAt, licenseExpiration, plan in
                            currentLicenseKey = license
                            isLoggedIn = true
                            sessionExpiresAt = expiresAt?.timeIntervalSince1970 ?? 0
                            licenseExpiresAt = licenseExpiration?.timeIntervalSince1970 ?? 0
                            licensePlan = plan ?? ""
                            synchronizeRemotePatches()
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
        }
    }

    private func attemptAutoLogin() async {
        if isLoggedIn {
            await checkSessionValidityAsync()
            isCheckingAutoLogin = false
            if isLoggedIn { synchronizeRemotePatches() }
            return
        }
        if KeychainManager.shared.loadAuthToken() != nil {
            let storedSessionValid = await withCheckedContinuation { continuation in
                LoginManager.verifyStoredSession { result in
                    if case .revoked = result {
                        LoginManager.clearSession()
                        isLoggedIn = false
                        currentLicenseKey = ""
                        sessionExpiresAt = 0
                        licenseExpiresAt = 0
                        licensePlan = ""
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
        await withCheckedContinuation { continuation in
            LoginManager.tryAutoLogin { success, license, expiresAt, licenseExpiration, plan in
                Task { @MainActor in
                    if success, let license {
                        currentLicenseKey = license
                        isLoggedIn = true
                        sessionExpiresAt = expiresAt?.timeIntervalSince1970 ?? 0
                        licenseExpiresAt = licenseExpiration?.timeIntervalSince1970 ?? 0
                        licensePlan = plan ?? ""
                        log("app: auto-login successful")
                        synchronizeRemotePatches()
                    } else {
                        log("app: auto-login unavailable; showing original login")
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

    private func checkSessionValidityAsync() async {
        guard isLoggedIn, !isCheckingSession else { return }
        isCheckingSession = true
        defer { isCheckingSession = false }
        if sessionExpiresAt > 0, Date() > Date(timeIntervalSince1970: sessionExpiresAt) {
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
        case .valid(let licenseExpiration, let plan):
            if let licenseExpiration {
                licenseExpiresAt = licenseExpiration.timeIntervalSince1970
            }
            licensePlan = plan ?? ""
            log("[AUTH] session check accepted")
            synchronizeRemotePatches()
        case .revoked:
            log("[AUTH] session check revoked; showing login")
            logout()
        case .networkError:
            log("[AUTH] session check unavailable; keeping current session")
        }
    }

    private func refreshLicenseExpirationLoop() async {
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
        RemotePatchService.shared.clearAuth()
        LoginManager.clearSession()
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
