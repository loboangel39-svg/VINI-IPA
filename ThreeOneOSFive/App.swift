import SwiftUI
import UIKit

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var syncManager = PatchSyncManager.shared
    @StateObject private var patchStore = PatchProjectStore()  // ⭐ AGREGAR ESTA LINEA
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var showOnboarding = OnboardingStore.shouldShow()
    @State private var showAttribution = false
    @State private var updateOffer: AppUpdateChecker.Offer?
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @AppStorage("sessionExpiresAt") private var sessionExpiresAt: Double = 0
    @AppStorage("currentLicenseKey") private var currentLicenseKey: String = ""
    @Environment(\.scenePhase) private var scenePhase

    init() {
        setupLogCapture()
        log("app: 3105 launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
        checkSessionValidity()
    }
    
    private func checkSessionValidity() {
        guard isLoggedIn else { return }
        
        if sessionExpiresAt > 0 {
            let expirationDate = Date(timeIntervalSince1970: sessionExpiresAt)
            if Date() > expirationDate {
                logout()
                log("app: session expired locally")
                return
            }
        }
        
        if !currentLicenseKey.isEmpty {
            LoginManager.verifyLicense(licenseKey: currentLicenseKey) { isValid in
                if !isValid {
                    self.logout()
                    log("app: license invalidated on server")
                }
            }
        }
    }
    
    private func logout() {
        isLoggedIn = false
        sessionExpiresAt = 0
        currentLicenseKey = ""
        RemotePatchService.shared.clearAuth()
        log("app: user logged out")
    }
    
    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isLoggedIn {
                    mainContent
                } else {
                    LoginView(onLoginSuccess: { license, expiresAt in
                        currentLicenseKey = license
                        isLoggedIn = true
                        if let expiresAt = expiresAt {
                            sessionExpiresAt = expiresAt.timeIntervalSince1970
                        } else {
                            sessionExpiresAt = 0
                        }
                        
                        // ⭐ AGREGAR ESTAS 2 LINEAS:
                        Task {
                            await patchStore.loadAssignedPatches()
                            await syncManager.syncPatches()
                        }
                    })
                }
            }
            .task {
                if isLoggedIn {
                    await patchStore.loadAssignedPatches()  // ⭐ AGREGAR
                    await syncManager.syncPatches()
                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            ContentView()
                .environmentObject(appState)
                .environmentObject(patchDraftCoordinator)
                .environmentObject(fileOperationCoordinator)
                .environmentObject(patchStore)  // ⭐ AGREGAR ESTA LINEA
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
                .opacity(showOnboarding ? 0 : 1)
                .allowsHitTesting(!showOnboarding)

            if showOnboarding {
                OnboardingView {
                    OnboardingStore.markCompleted()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showOnboarding = false
                    }
                }
                .transition(.opacity)
            }
        }
        .task {
            checkForUpdate()
        }
        .sheet(isPresented: $showAttribution) {
            AttributionView()
        }
        .sheet(item: $updateOffer) { offer in
            AppUpdateView(offer: offer)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                checkSessionValidity()
                checkForUpdate()
            }
        }
    }
}
