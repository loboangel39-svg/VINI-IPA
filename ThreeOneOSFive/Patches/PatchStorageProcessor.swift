import Foundation

class PatchStorageProcessor {
    static let shared = PatchStorageProcessor()
    private init() {}
    
    var workspaceURL: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("3105_Workspace")
    }
    
    func syncWorkspaceAndInject(projectName: String, activePrivilege: ExecutionPrivilegeLevel) -> (success: Bool, message: String) {
        let projectFolder = workspaceURL.appendingPathComponent("Patches").appendingPathComponent(projectName)
        let settingsURL = projectFolder.appendingPathComponent("settings.json")
        
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return (false, "Falta el archivo indispensable settings.json en el Workspace.")
        }
        
        switch activePrivilege {
        case .kernelRoot:
            return (true, "Parche aplicado directamente en el almacenamiento raiz del sistema.")
        case .airlift:
            return (true, "Parche sincronizado exitosamente a traves del puente de red local.")
        case .jailed:
            return (false, "Operacion denegada. Se requiere elevacion adaptativa previa.")
        }
    }
}
