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

    static func load(
        fileManager: FileManager = .default,
        allowedPatchIDs: Set<UUID> = []
    ) -> [PatchLibraryItem] {
        guard !allowedPatchIDs.isEmpty else {
            log("patch: no patches assigned, returning empty list")
            return []
        }

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

                guard allowedPatchIDs.contains(summary.packageID) else {
                    continue
                }

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
        log("patch: loaded \(result.count) remote patches (filtered from \(allowedPatchIDs.count) assigned)")
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
            let sanitized = projectName.replacingOccurrences(
                of: "/", with: "_"
            )
            destination = root.appendingPathComponent(
                "\(sanitized).3105", isDirectory: false
            )
        }
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        return destination
    }

    static func delete(_ item: PatchLibraryItem, fileManager: FileManager = .default) throws {
        if let workspace = item.workspaceURL {
            try? fileManager.removeItem(at: workspace)
        }
        try? PatchKeyStore.delete(for: item.summary)
        try fileManager.removeItem(at: item.packageURL)
    }
}
