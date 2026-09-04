import Foundation

// MARK: - Patch Storage
// Almacena patches remotos en Documents/RemotePatches/
// Cada patch se guarda como patch-<id>.3105
// Las descargas van primero a un archivo temporal para evitar corrupción.

final class PatchStorage {
    static let shared = PatchStorage()
    
    /// Directorio principal: Documents/RemotePatches/
    private var storageDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("RemotePatches", isDirectory: true)
    }
    
    /// Directorio temporal para descargas en progreso
    private var tempDirectory: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("VINI_Downloads", isDirectory: true)
    }
    
    init() {
        ensureDirectories()
    }
    
    // MARK: - Directory Setup
    
    private func ensureDirectories() {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - File Paths
    
    /// Ruta final de un patch almacenado
    func patchFileURL(patchId: String) -> URL {
        return storageDirectory.appendingPathComponent("patch-\(patchId).3105")
    }
    
    /// Ruta temporal para una descarga en progreso
    func tempFileURL(patchId: String) -> URL {
        return tempDirectory.appendingPathComponent("download-\(patchId)-\(UUID().uuidString).3105.tmp")
    }
    
    /// Metadata local de un patch (versión descargada)
    func metadataURL(patchId: String) -> URL {
        return storageDirectory.appendingPathComponent("patch-\(patchId).meta.json")
    }
    
    // MARK: - File Operations
    
    /// Verifica si un patch existe localmente
    func patchExists(patchId: String) -> Bool {
        return FileManager.default.fileExists(atPath: patchFileURL(patchId: patchId).path)
    }
    
    /// Obtiene el tamaño del archivo local de un patch
    func patchFileSize(patchId: String) -> Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: patchFileURL(patchId: patchId).path),
              let size = attrs[.size] as? Int else {
            return nil
        }
        return size
    }
    
    /// Guarda un patch de forma atómica: temp → verificar → reemplazar
    /// Este es el método clave que evita que una descarga fallida corrompa el archivo anterior.
    func savePatch(patchId: String, tempURL: URL, version: String, expectedSize: Int? = nil) throws {
        // 1. Verificar que el archivo temporal existe y tiene datos
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            throw PatchStorageError.tempFileMissing
        }
        
        let tempSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int ?? 0
        guard tempSize > 0 else {
            throw PatchStorageError.emptyDownload
        }
        
        // 2. Verificar tamaño esperado (si se proporcionó)
        if let expected = expectedSize, expected > 0, tempSize != expected {
            throw PatchStorageError.sizeMismatch(expected: expected, actual: tempSize)
        }
        
        // 3. Reemplazar archivo anterior de forma atómica
        let finalURL = patchFileURL(patchId: patchId)
        
        // Si existe archivo anterior, hacer backup temporal primero
        if FileManager.default.fileExists(atPath: finalURL.path) {
            let backupURL = storageDirectory.appendingPathComponent("patch-\(patchId).backup.3105")
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.moveItem(at: finalURL, to: backupURL)
            
            // Mover nuevo archivo a su lugar
            do {
                try FileManager.default.moveItem(at: tempURL, to: finalURL)
                // Éxito — eliminar backup
                try? FileManager.default.removeItem(at: backupURL)
            } catch {
                // Falló el move — restaurar backup
                try? FileManager.default.moveItem(at: backupURL, to: finalURL)
                throw error
            }
        } else {
            // No hay archivo anterior — mover directamente
            try FileManager.default.moveItem(at: tempURL, to: finalURL)
        }
        
        // 4. Guardar metadata local
        let metadata = PatchLocalMetadata(
            patchId: patchId,
            version: version,
            downloadedAt: Date().ISO8601Format(),
            fileSize: tempSize
        )
        let metaData = try JSONEncoder().encode(metadata)
        try metaData.write(to: metadataURL(patchId: patchId))
    }
    
    /// Obtiene la metadata local de un patch
    func localMetadata(patchId: String) -> PatchLocalMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(patchId: patchId)),
              let metadata = try? JSONDecoder().decode(PatchLocalMetadata.self, from: data) else {
            return nil
        }
        return metadata
    }
    
    /// Obtiene la versión local de un patch
    func localVersion(patchId: String) -> String? {
        return localMetadata(patchId: patchId)?.version
    }
    
    /// Elimina un patch local
    func deletePatch(patchId: String) {
        try? FileManager.default.removeItem(at: patchFileURL(patchId: patchId))
        try? FileManager.default.removeItem(at: metadataURL(patchId: patchId))
    }
    
    /// Lista todos los patches almacenados localmente
    func localPatchIds() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "3105" && $0.deletingPathExtension().lastPathComponent.hasPrefix("patch-") }
            .map { $0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "patch-", with: "") }
    }
    
    /// Limpia archivos temporales de descargas fallidas
    func cleanupTempFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
    
    /// Lee los datos de un patch almacenado
    func readPatchData(patchId: String) -> Data? {
        return try? Data(contentsOf: patchFileURL(patchId: patchId))
    }
}

// MARK: - Models

struct PatchLocalMetadata: Codable {
    let patchId: String
    let version: String
    let downloadedAt: String
    let fileSize: Int
}

enum PatchStorageError: LocalizedError {
    case tempFileMissing
    case emptyDownload
    case sizeMismatch(expected: Int, actual: Int)
    
    var errorDescription: String? {
        switch self {
        case .tempFileMissing: return "Temporary download file missing"
        case .emptyDownload: return "Downloaded file is empty"
        case .sizeMismatch(let expected, let actual):
            return "Size mismatch: expected \(expected) bytes, got \(actual)"
        }
    }
}
