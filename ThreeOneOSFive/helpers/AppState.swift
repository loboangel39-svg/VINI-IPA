import Foundation
import Combine

enum ExecutionPrivilegeLevel: Int, Comparable {
    case jailed = 0
    case airlift = 1
    case kernelRoot = 2
    static func < (lhs: ExecutionPrivilegeLevel, rhs: ExecutionPrivilegeLevel) -> Bool { 
        return lhs.rawValue < rhs.rawValue 
    }
}

class AppState: ObservableObject {
    @Published var privilegeLevel: ExecutionPrivilegeLevel = .jailed
    @Published var kernelExploitRunning: Bool = false
    @Published var exploitStatusMessage: String = "Inicializando entorno 3105..."
    
    func initializeExecutionEnvironment(airliftReady: Bool) {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        self.kernelExploitRunning = true
        self.exploitStatusMessage = "Analizando estructura adaptativa de iOS \(osVersion.majorVersion).\(osVersion.minorVersion)..."
        
        if KernelExploitManager.shared.executeKernelBadQueryBypass() {
            self.privilegeLevel = .kernelRoot
            self.exploitStatusMessage = "Entorno Adaptado: Acceso Kernel Directo (iOS \(osVersion.majorVersion) R/W local activo)."
            self.kernelExploitRunning = false
            return
        }
        
        self.kernelExploitRunning = false
        if validateAirliftVersionScope(major: osVersion.majorVersion, minor: osVersion.minorVersion, patch: osVersion.patchVersion) {
            if airliftReady {
                self.privilegeLevel = .airlift
                self.exploitStatusMessage = "Entorno Adaptado: Escritura via Tunnel de Red Local (Airlift Activo)."
            } else {
                self.privilegeLevel = .jailed
                self.exploitStatusMessage = "Airlift compatible. Requiere activar LocalDevVPN e importar archivo de emparejamiento."
            }
        } else {
            self.privilegeLevel = .jailed
            self.exploitStatusMessage = "Error: Esta version de firmware no cuenta con vectores publicos en la arquitectura 3105."
        }
    }

    private func validateAirliftVersionScope(major: Int, minor: Int, patch: Int) -> Bool {
        if major == 18 && minor == 7 && (patch >= 2 && patch <= 10) { return true }
        if major == 26 {
            if minor == 6 && patch >= 3 { return true }
            if minor == 7 { return true }
        }
        if major == 27 {
            if minor <= 2 { return true }
        }
        return false
    }
}
