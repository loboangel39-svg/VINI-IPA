import SwiftUI

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var airLiftCoordinator = AirLiftPairingController()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(patchStore)
                .environmentObject(airLiftCoordinator)
                .onAppear { 
                    appState.initializeExecutionEnvironment(airliftReady: airLiftCoordinator.pairingReady) 
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active && appState.privilegeLevel < .kernelRoot {
                        appState.initializeExecutionEnvironment(airliftReady: airLiftCoordinator.pairingReady)
                    }
                }
        }
    }
}
