import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var patchStore: PatchProjectStore
    @EnvironmentObject var airLift: AirLiftPairingController
    @State private var selectedTab: Int = 0
    @State private var showSettings: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Estado", systemImage: "cpu") }
                .tag(0)
            
            PatchesListView()
                .tabItem { Label("Parches", systemImage: "doc.text.magnifyingglass") }
                .tag(1)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showSettings = true }) { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) { PublicSettingsView() }
    }
}

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var airLift: AirLiftPairingController
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Diagnostico del Sistema")) {
                    HStack {
                        Text("Vector Operativo Activo")
                        Spacer()
                        Text(privilegeLabel).bold().foregroundColor(privilegeColor)
                    }
                }
                Section(header: Text("Consola Global"), footer: Text(appState.exploitStatusMessage)) {
                    Button(action: { appState.initializeExecutionEnvironment(airliftReady: airLift.pairingReady) }) {
                        Label("Re-evaluar Entorno Fisico", systemImage: "arrow.clockwise")
                    }
                }
            }
            .navigationTitle("Consola 3105")
        }
    }
    
    private var privilegeLabel: String {
        switch appState.privilegeLevel {
        case .kernelRoot: return "Kernel Root (Directo)"
        case .airlift: return "Airlift Sandbox Escape"
        case .jailed: return "Restringido (Jailed)"
        }
    }
    
    private var privilegeColor: Color {
        switch appState.privilegeLevel {
        case .kernelRoot: return .purple
        case .airlift: return .blue
        case .jailed: return .red
        }
    }
}

struct PatchesListView: View {
    @EnvironmentObject var patchStore: PatchProjectStore
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Workspace del Inyector"), footer: Text(patchStore.operationErrorMessage ?? "")) {
                    ForEach(patchStore.availablePatches) { patch in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(patch.name).font(.headline)
                                Text(patch.description).font(.subheadline).foregroundColor(.gray)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { patch.isEnabled },
                                set: { _ in _ = patchStore.applyPatchAdaptive(id: patch.id, currentPrivilege: appState.privilegeLevel) }
                            ))
                            .disabled(appState.privilegeLevel == .jailed)
                        }
                    }
                }
                if appState.privilegeLevel > .jailed {
                    Section {
                        Button(action: { NeoSpring.shared.triggerInterfaceReload(currentPrivilege: appState.privilegeLevel) }) {
                            Label("Aplicar Cambios (NeoSpring)", systemImage: "sparkles")
                        }.foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Parches Estaticos")
        }
    }
}

struct PublicSettingsView: View {
    @EnvironmentObject var airLift: AirLiftPairingController
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Tunnel de Red Local")) {
                    HStack {
                        Text("Estado de Interfaz")
                        Spacer()
                        Text(airLift.isTunnelConnected ? "Conectado" : "Buscando Sockets...").foregroundColor(airLift.isTunnelConnected ? .green : .orange)
                    }
                    HStack {
                        Text("Bypass de Sincronizacion")
                        Spacer()
                        Text(airLift.pairingReady ? "Listo (Canal Abierto)" : "Falta Archivo").foregroundColor(airLift.pairingReady ? .blue : .gray)
                    }
                }
                Section {
                    Button(action: {
                        if let dummyURL = URL(string: "file:///mock.mobiledevicepairing") {
                            _ = airLift.importPairingRecord(from: dummyURL)
                        }
                    }) { Label("Importar .mobiledevicepairing", systemImage: "doc.badge.plus") }
                }
            }
            .navigationTitle("Airlift Config")
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Cerrar") { dismiss() } } }
        }
    }
}
