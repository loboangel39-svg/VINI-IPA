import Foundation
import Combine

struct PatchProject: Identifiable, Codable {
    let id: UUID
    let name: String
    let targetDirectory: String
    let description: String
    var isEnabled: Bool
}

class PatchProjectStore: ObservableObject {
    @Published var availablePatches: [PatchProject] = []
    @Published var operationErrorMessage: String? = nil
    
    init() { loadStoredPatches() }
    
    func loadStoredPatches() {
        self.availablePatches = [
            PatchProject(id: UUID(), name: "Custom Lockscreen Dialer", targetDirectory: "/var/mobile/Library/Caches/com.apple.TelephonyUI", description: "Modifica el aspecto estatico del teclado de llamadas.", isEnabled: false),
            PatchProject(id: UUID(), name: "Apple Pay Card Theme", targetDirectory: "/var/mobile/Library/Caches/com.apple.Passbook", description: "Sobreescribe las plantillas visuales de Passbook.", isEnabled: false)
        ]
    }
    
    func applyPatchAdaptive(id: UUID, currentPrivilege: ExecutionPrivilegeLevel) -> Bool {
        guard let index = availablePatches.firstIndex(where: { $0.id == id }) else { return false }
        let patch = availablePatches[index]
        
        if patch.isEnabled {
            if PatchBackupManager.shared.restoreOriginalFile(at: patch.targetDirectory, privilege: currentPrivilege) {
                availablePatches[index].isEnabled = false
                self.operationErrorMessage = "Parche removido. Estado original restaurado."
                return true
            }
        } else {
            if PatchBackupManager.shared.backupOriginalFile(at: patch.targetDirectory, privilege: currentPrivilege) {
                let injection = PatchStorageProcessor.shared.syncWorkspaceAndInject(projectName: patch.name, activePrivilege: currentPrivilege)
                if injection.success {
                    availablePatches[index].isEnabled = true
                    self.operationErrorMessage = injection.message
                    return true
                } else { self.operationErrorMessage = injection.message }
            } else {
                self.operationErrorMessage = "Error de seguridad: Fallo al resguardar la ruta original."
            }
        }
        return false
    }
}
