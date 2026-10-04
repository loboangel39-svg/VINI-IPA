import Foundation

class PatchBackupManager {
    static let shared = PatchBackupManager()
    private init() {}
    private let fileManager = FileManager.default
    
    func backupOriginalFile(at targetPath: String, privilege: ExecutionPrivilegeLevel) -> Bool {
        let targetURL = URL(fileURLWithPath: targetPath)
        let backupURL = targetURL.appendingPathExtension("bak")
        if fileManager.fileExists(atPath: backupURL.path) { return true }
        guard fileManager.fileExists(atPath: targetURL.path) else { return false }
        
        if privilege == .kernelRoot {
            try? fileManager.copyItem(at: targetURL, to: backupURL)
        }
        return true 
    }
    
    func restoreOriginalFile(at targetPath: String, privilege: ExecutionPrivilegeLevel) -> Bool {
        let targetURL = URL(fileURLWithPath: targetPath)
        let backupURL = targetURL.appendingPathExtension("bak")
        guard fileManager.fileExists(atPath: backupURL.path) else { return false }
        
        if privilege == .kernelRoot {
            try? fileManager.removeItem(at: targetURL)
            try? fileManager.moveItem(at: backupURL, to: targetURL)
        }
        return true
    }
}
