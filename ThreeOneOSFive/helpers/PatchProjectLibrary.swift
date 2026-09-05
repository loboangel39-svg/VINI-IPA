import Foundation

struct PatchLibraryItem: Identifiable {
    let summary: PatchPackageSummary
    var project: PatchProject?
    var contentKey: Data?
    var packageURL: URL

    var id: UUID { summary.packageID }
    var isLocked: Bool { project == nil }
    var workspaceURL: URL? {
        PatchWorkspaceService.workspaceURL(projectID: id)
    }
}

struct PatchPasswordRequest: Identifiable {
    let summary: PatchPackageSummary
    var id: UUID { summary.packageID }
}

enum PatchProjectLibrary {
    static func packageRootURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("PatchProjects", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func backupRootURL(fileManager: FileManager = .default) throws -> URL {
        let root = try packageRootURL(fileManager: fileManager)
            .appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // Carga todos los patches del directorio (sin filtrar)
    // El worker ya filtra por usuario, así que solo se descargan los asignados
    static func load(fileManager: FileManager = .default) -> [PatchLibraryItem] {
        // Bridge: copiar patches descargados de Documents/RemotePatches/ a Application Support/PatchProjects/
        bridgeDownloadedPatches(fileManager: fileManager)

        guard let root = try? packageRootURL(fileManager: fileManager),
              let urls = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
              ) else { return [] }

        var byID: [UUID: PatchLibraryItem] = [:]
        for url in urls where url.pathExtension.lowercased() == "3105" {
            do {
                let data = try readPackage(at: url)
                let summary = try PatchPackageCodec.inspect(data)
                let decoded: DecodedPatchPackage?
                if let contentKey = try PatchKeyStore.load(for: summary) {
                    decoded = try PatchPackageCodec.decode(data, contentKey: contentKey)
                } else if summary.isPasswordProtected {
                    decoded = nil
                } else {
                    decoded = try PatchPackageCodec.decode(data, password: nil)
                }
                let item = PatchLibraryItem(
                    summary: summary,
                    project: decoded?.project,
                    contentKey: decoded?.contentKey,
                    packageURL: url
                )
                if summary.schemaVersion >= 2, let project = decoded?.project {
                    do {
                        _ = try PatchWorkspaceService.ensureWorkspace(for: project)
                    } catch {
                        log("patch: workspace unavailable for \(project.id.uuidString)")
                    }
                }
                byID[summary.packageID] = item
            } catch {
                log("patch: skipped invalid local package \(url.lastPathComponent)")
            }
        }

        let result = byID.values.sorted {
            ($0.project?.updatedAt ?? .distantPast) > ($1.project?.updatedAt ?? .distantPast)
        }
        log("patch: loaded \(result.count) patches from disk")
        return result
    }

    static func readPackage(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isDirectory != true,
              values.isSymbolicLink != true,
              values.isRegularFile == true else {
            throw PatchPackageError.invalidProject
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    static func save(
        data: Data,
        projectName: String,
        existingURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let destination: URL
        if let existingURL {
            destination = existingURL
        } else {
            let root = try packageRootURL(fileManager: fileManager)
            let baseName = sanitizedFilename(projectName)
            var candidate = root.appendingPathComponent(baseName).appendingPathExtension("3105")
            var suffix = 2
            while fileManager.fileExists(atPath: candidate.path) {
                candidate = root.appendingPathComponent("\(baseName)-\(suffix)").appendingPathExtension("3105")
                suffix += 1
            }
            destination = candidate
        }
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        return destination
    }

    static func installImportedPackage(
        data: Data,
        decoded: DecodedPatchPackage,
        summary: PatchPackageSummary,
        existingURL: URL?,
        fileManager: FileManager = .default
    ) throws {
        let previousData = try existingURL.map { try readPackage(at: $0) }
        var savedURL: URL?
        do {
            savedURL = try save(
                data: data,
                projectName: decoded.project.name,
                existingURL: existingURL,
                fileManager: fileManager
            )
            if summary.schemaVersion >= 2 {
                _ = try PatchWorkspaceService.replaceWorkspace(
                    with: decoded.project,
                    fileManager: fileManager
                )
            } else {
                try? PatchWorkspaceService.deleteWorkspace(
                    projectID: decoded.project.id,
                    fileManager: fileManager
                )
            }
        } catch {
            if let previousData, let existingURL {
                try? previousData.write(
                    to: existingURL,
                    options: [.atomic, .completeFileProtection]
                )
            } else if let savedURL, fileManager.fileExists(atPath: savedURL.path) {
                try? fileManager.removeItem(at: savedURL)
            }
            throw error
        }
    }

    static func delete(_ item: PatchLibraryItem, fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: item.packageURL.path) {
            try fileManager.removeItem(at: item.packageURL)
        }
        try? PatchWorkspaceService.deleteWorkspace(projectID: item.id, fileManager: fileManager)
        try? PatchKeyStore.delete(for: item.summary)
    }

    static func synchronizeWorkspace(
        item: PatchLibraryItem,
        fileManager: FileManager = .default
    ) throws -> PatchProject {
        guard item.summary.schemaVersion >= 2,
              let baseProject = item.project,
              let contentKey = item.contentKey else {
            throw PatchPackageError.invalidProject
        }
        let workspace = try PatchWorkspaceService.ensureWorkspace(
            for: baseProject,
            fileManager: fileManager
        )
        let project = try PatchWorkspaceService.snapshot(
            baseProject: baseProject,
            workspaceURL: workspace,
            fileManager: fileManager
        )
        let original = try readPackage(at: item.packageURL)
        let updated = try PatchPackageCodec.update(
            original,
            project: project,
            contentKey: contentKey,
            schemaVersion: PatchPackageCodec.latestSchemaVersion
        )
        _ = try save(
            data: updated,
            projectName: project.name,
            existingURL: item.packageURL,
            fileManager: fileManager
        )
        return project
    }

    static func seedDefaultPackages(fileManager: FileManager = .default) {
        // DESHABILITADO: Los patches ahora se descargan remotamente desde el Worker
        log("patch: seedDefaultPackages deshabilitado - usando patches remotos")
        return
    }

    private static func sanitizedFilename(_ rawName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = rawName.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(scalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
        return result.isEmpty ? "Patch" : String(result)
    }

    // MARK: - Bridge: RemotePatches → PatchProjects
    // Copia los archivos .3105 descargados por PatchManager/PatchStorage
    // (Documents/RemotePatches/) al directorio que escanea este módulo
    // (Application Support/PatchProjects/).
    // También elimina de PatchProjects/ los patches remotos que ya no están asignados.
    private static func bridgeDownloadedPatches(fileManager: FileManager) {
        let patchManager = PatchManager.shared
        let localIds = patchManager.localPatchIds()

        guard let libraryRoot = try? packageRootURL(fileManager: fileManager) else {
            log("patch: bridge failed — cannot resolve PatchProjects directory")
            return
        }

        // 1. Copiar patches que sí están asignados
        var copied = 0
        for patchId in localIds {
            guard let data = patchManager.patchData(patchId) else { continue }
            let destURL = libraryRoot.appendingPathComponent("patch-\(patchId).3105")

            // Solo escribir si el contenido cambió
            if let existingData = try? Data(contentsOf: destURL), existingData == data {
                continue
            }

            do {
                try data.write(to: destURL, options: [.atomic])
                copied += 1
            } catch {
                log("patch: bridge failed for \(patchId) — \(error.localizedDescription)")
            }
        }
        if copied > 0 {
            log("patch: bridged \(copied) patches from RemotePatches to PatchProjects")
        }

        // 2. Eliminar de PatchProjects/ los patches remotos que ya no están asignados
        //    Solo eliminamos archivos con formato "patch-<uuid>.3105" (patches remotos)
        //    No tocamos patches creados/importados localmente por el usuario
        guard let existingFiles = try? fileManager.contentsOfDirectory(
            at: libraryRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let remotePatchIds = Set(localIds)
        var removed = 0

        for file in existingFiles where file.pathExtension.lowercased() == "3105" {
            let name = file.deletingPathExtension().lastPathComponent
            // Solo procesar archivos con formato "patch-<id>"
            guard name.hasPrefix("patch-") else { continue }

            let patchId = String(name.dropFirst("patch-".count))

            // Si este patch remoto ya no está en RemotePatches, eliminarlo
            if !remotePatchIds.contains(patchId) {
                do {
                    try fileManager.removeItem(at: file)
                    removed += 1
                    log("patch: removed orphaned remote patch from PatchProjects: \(patchId)")
                } catch {
                    log("patch: failed to remove orphaned patch \(patchId) — \(error.localizedDescription)")
                }
            }
        }

        if removed > 0 {
            log("patch: removed \(removed) orphaned remote patches from PatchProjects")
        }
    }
}
