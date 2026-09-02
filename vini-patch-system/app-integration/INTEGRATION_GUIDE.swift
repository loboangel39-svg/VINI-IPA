// ============================================================
// INTEGRATION GUIDE - Changes needed in existing files
// ============================================================
//
// This file contains the exact code changes to integrate
// the remote patch system into your existing VINI app.
//
// FILES TO MODIFY:
// 1. App.swift
// 2. ContentView.swift
// 3. LoginView.swift
//
// FILES TO ADD (from this package):
// - RemotePatchService.swift  → helpers/
// - PatchSyncService.swift    → helpers/
// - RemotePatchesView.swift   → views/
// ============================================================

// ============================================================
// 1. App.swift - MODIFICATIONS
// ============================================================
//
// ADD these imports/state properties at the top of ThreeOneOSFiveApp:
//
//     @StateObject private var remotePatchesVM = RemotePatchesViewModel()
//     @StateObject private var patchSyncService = PatchSyncService.shared
//     @State private var showRemotePatches = false
//
//
// REPLACE the checkSessionValidity() method with:
//
//     private func checkSessionValidity() {
//         guard isLoggedIn else { return }
//
//         // Check local expiration
//         if sessionExpiresAt > 0 {
//             let expirationDate = Date(timeIntervalSince1970: sessionExpiresAt)
//             if Date() > expirationDate {
//                 logout()
//                 log("app: session expired locally")
//                 return
//             }
//         }
//
//         // Verify against remote Worker API (preferred) or Firebase fallback
//         let workerURL = RemotePatchService.shared.baseURL
//         if !workerURL.isEmpty {
//             Task {
//                 let valid = await RemotePatchService.shared.verifySession()
//                 if !valid {
//                     await MainActor.run { self.logout() }
//                     log("app: remote session invalidated")
//                 }
//             }
//         } else if !currentLicenseKey.isEmpty {
//             // Fallback to Firebase if Worker URL not configured
//             LoginManager.verifyLicense(licenseKey: currentLicenseKey) { isValid in
//                 if !isValid {
//                     self.logout()
//                     log("app: license invalidated on server")
//                 }
//             }
//         }
//     }
//
//
// REPLACE the logout() method with:
//
//     private func logout() {
//         isLoggedIn = false
//         sessionExpiresAt = 0
//         currentLicenseKey = ""
//         RemotePatchService.shared.clearSession()
//         log("app: user logged out")
//     }
//
//
// ADD to the mainContent ZStack, after the updateOffer alert:
//
//     .sheet(isPresented: $showRemotePatches) {
//         RemotePatchesView()
//             .environmentObject(patchSyncService)
//     }
//
//
// ADD to the onAppear block:
//
//     // Sync remote patches after login
//     if isLoggedIn {
//         Task { await patchSyncService.sync() }
//     }
//
//
// ADD to the onChange(of: scenePhase) block, inside the .active guard:
//
//     // Auto-sync remote patches periodically
//     Task { await patchSyncService.sync() }
//

// ============================================================
// 2. ContentView.swift - MODIFICATIONS
// ============================================================
//
// ADD the Remote Patches card to the Home tab.
// Find the Home tab content and add this card:
//
//     RemotePatchesDashboardCard(syncService: patchSyncService) {
//         showRemotePatches = true
//     }
//     .padding(.horizontal)
//
// You'll need to pass the environment objects down:
//
//     @EnvironmentObject var patchSyncService: PatchSyncService
//     @State private var showRemotePatches = false

// ============================================================
// 3. LoginView.swift - MODIFICATIONS
// ============================================================
//
// The existing LoginView uses Firebase. To add Worker API support,
// modify the login action to try the Worker API first:
//
// REPLACE the login button action with:
//
//     Button(action: {
//         isLoading = true
//         errorMessage = ""
//
//         let workerURL = RemotePatchService.shared.baseURL
//         if !workerURL.isEmpty {
//             // Try Worker API first
//             Task {
//                 do {
//                     let response = try await RemotePatchService.shared.validateLicense(key: licenseKey)
//                     await MainActor.run {
//                         if response.valid {
//                             // Parse expiration date
//                             var expiresAt: Date? = nil
//                             if let expiresStr = response.expiresAt {
//                                 let formatter = ISO8601DateFormatter()
//                                 formatter.formatOptions = [.withInternetDateTime]
//                                 expiresAt = formatter.date(from: expiresStr)
//                             }
//                             onLoginSuccess(licenseKey, expiresAt)
//                         } else {
//                             errorMessage = response.error ?? "Licencia inválida"
//                         }
//                         isLoading = false
//                     }
//                 } catch {
//                     // Fallback to Firebase
//                     performFirebaseLogin()
//                 }
//             }
//         } else {
//             performFirebaseLogin()
//         }
//     }) {
//         // ... existing button content
//     }
//
// ADD the Firebase fallback method:
//
//     private func performFirebaseLogin() {
//         LoginManager.login(licenseKey: licenseKey) { success, message, expiresAt in
//             DispatchQueue.main.async {
//                 isLoading = false
//                 if success {
//                     onLoginSuccess(licenseKey, expiresAt)
//                 } else {
//                     errorMessage = message
//                 }
//             }
//         }
//     }
