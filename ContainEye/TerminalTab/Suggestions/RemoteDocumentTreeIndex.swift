import Foundation
import Blackbird

struct IndexedRemotePath: Hashable {
    let path: String
    let isDirectory: Bool
    let lastSeen: Date

    var basename: String {
        String(path.split(separator: "/").last ?? "")
    }
}

actor RemoteDocumentTreeIndex {
    private var cache: [String: [String: IndexedRemotePath]] = [:]
    private var loadedCredentialKeys = Set<String>()

    func bootstrap(credentialKey: String, cwd: String) async {
        await loadIfNeeded(credentialKey: credentialKey)
        await upsert(credentialKey: credentialKey, path: normalize(path: cwd), isDirectory: true)

        if normalize(path: cwd) != "/" {
            await upsert(credentialKey: credentialKey, path: "/", isDirectory: true)
        }
    }

    func upsert(credentialKey: String, path: String, isDirectory: Bool) async {
        let normalized = normalize(path: path)
        await loadIfNeeded(credentialKey: credentialKey)

        var nodes = cache[credentialKey, default: [:]]
        nodes[normalized] = IndexedRemotePath(path: normalized, isDirectory: isDirectory, lastSeen: .now)
        cache[credentialKey] = nodes

        let model = RemotePathNode(credentialKey: credentialKey, path: normalized, isDirectory: isDirectory, lastSeen: .now)
        try? await model.write(to: SharedDatabase.db)
    }

    func suggestChildren(credentialKey: String, directory: String, prefix: String, limit: Int) async -> [String] {
        await loadIfNeeded(credentialKey: credentialKey)

        let normalizedDir = normalize(path: directory)
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)
        let nodes = cache[credentialKey, default: [:]].values

        let suggestions = nodes.compactMap { node -> String? in
            guard parentPath(of: node.path) == normalizedDir else {
                return nil
            }

            let base = node.basename
            guard !base.isEmpty else {
                return nil
            }

            if !trimmedPrefix.isEmpty && !base.hasPrefix(trimmedPrefix) {
                return nil
            }

            return node.isDirectory ? "\(base)/" : base
        }

        return Array(Set(suggestions)).sorted().prefix(limit).map { $0 }
    }

    private func loadIfNeeded(credentialKey: String) async {
        guard !loadedCredentialKeys.contains(credentialKey) else {
            return
        }

        loadedCredentialKeys.insert(credentialKey)

        let existing = (try? await RemotePathNode.read(
            from: SharedDatabase.db,
            matching: \.$credentialKey == credentialKey,
            orderBy: .descending(\.$lastSeen),
            limit: 3000
        )) ?? []

        var nodes: [String: IndexedRemotePath] = [:]
        for row in existing {
            nodes[row.path] = IndexedRemotePath(path: row.path, isDirectory: row.isDirectory, lastSeen: row.lastSeen)
        }

        cache[credentialKey] = nodes
    }

    private func normalize(path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "/"
        }

        var normalized = trimmed
        if !normalized.hasPrefix("/") {
            normalized = "/" + normalized
        }

        while normalized.contains("//") {
            normalized = normalized.replacingOccurrences(of: "//", with: "/")
        }

        if normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        return normalized
    }

    private func parentPath(of path: String) -> String {
        guard path != "/" else {
            return "/"
        }

        let components = path.split(separator: "/")
        guard components.count > 1 else {
            return "/"
        }

        return "/" + components.dropLast().joined(separator: "/")
    }
}
