import Foundation

/// Static helper for macOS App Sandbox file adoption.
///
/// URLs obtained via drag-drop or NSOpenPanel only carry usable scope on the
/// thread / queue that received them. The robust approach is to bring the file
/// *into* the sandbox once (hard-link or copy), then operate on the local copy.
enum SandboxHelper {
    static func cacheDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("VideoSources", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func adoptIntoSandbox(_ source: URL) throws -> (sandboxURL: URL, displayName: String) {
        let originalName = source.lastPathComponent
        let cleanedName = originalName.replacingOccurrences(of: "/", with: "-")
        let dest = try cacheDirectory()
            .appendingPathComponent("\(UUID().uuidString)-\(cleanedName)")

        do {
            try FileManager.default.linkItem(at: source, to: dest)
        } catch {
            try FileManager.default.copyItem(at: source, to: dest)
        }
        return (dest, originalName)
    }

    static func cleanupCachedSource(at url: URL?) {
        guard let url else { return }
        let dir = (try? cacheDirectory().path) ?? ""
        guard !dir.isEmpty, url.path.hasPrefix(dir) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
