import Foundation
import Observation

/// Stores paths of recently opened Maya project files so the user can
/// quickly reopen them from the welcome / drop-zone area.
@Observable
final class RecentProjectsStore {
    private(set) var projects: [RecentProject] = []

    private let maxCount = 8
    private let defaultsKey = "RecentProjects"

    init() { load() }

    /// Add or bump a project to the top of the recents list.
    func didOpen(url: URL) {
        // Resolve symlinks so the same folder doesn't appear twice with different paths.
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let name = resolved.deletingPathExtension().lastPathComponent
        projects.removeAll { $0.url == resolved }
        projects.insert(RecentProject(url: resolved, displayName: name), at: 0)
        if projects.count > maxCount { projects = Array(projects.prefix(maxCount)) }
        save()
    }

    func remove(at index: Int) {
        guard projects.indices.contains(index) else { return }
        projects.remove(at: index)
        save()
    }

    // MARK: - Persistence (file-system bookmarks so sandboxed reopen works)

    private func save() {
        var bookmarks: [Data] = []
        for p in projects {
            if let data = try? p.url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                bookmarks.append(data)
            }
        }
        UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
    }

    private func load() {
        guard let bookmarks = UserDefaults.standard.array(forKey: defaultsKey) as? [Data] else {
            return
        }
        var result: [RecentProject] = []
        for data in bookmarks {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            result.append(RecentProject(url: url, displayName: name))
        }
        projects = result
    }
}

struct RecentProject: Identifiable, Equatable {
    let id: UUID = UUID()
    let url: URL
    let displayName: String
}
