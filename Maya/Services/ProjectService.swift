import AVFoundation
import Foundation

/// Handles saving and loading `.mayaproj` project bundles.
///
/// A `.mayaproj` file is a macOS package (directory) containing:
/// - `project.json` — serialized editing state
/// - `media/` — sandbox copies of video and audio source files
///
/// This keeps the project self-contained and portable.
enum ProjectService {

    static let fileExtension = "mayaproj"
    static let jsonFileName = "project.json"
    static let mediaFolderName = "media"

    // MARK: - Save

    static func save(project: Project, to packageURL: URL) throws {
        let fm = FileManager.default

        // Create the package directory
        if fm.fileExists(atPath: packageURL.path) {
            try fm.removeItem(at: packageURL)
        }
        try fm.createDirectory(at: packageURL, withIntermediateDirectories: true)

        // Create media subfolder
        let mediaDir = packageURL.appendingPathComponent(mediaFolderName, isDirectory: true)
        try fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        // Build project file data (adjust background image and audio URLs to package-relative paths)
        var projectFile = project.toProjectFile()

        // Copy video file into media/
        if let videoURL = project.videoURL {
            let videoName = videoURL.lastPathComponent
            let dest = mediaDir.appendingPathComponent(videoName)
            try copyOrLink(from: videoURL, to: dest)
            projectFile.videoFileName = videoName
        }

        // Copy audio files into media/
        var updatedAudioClips: [AudioClipData] = []
        for audioClip in project.audioClips {
            let audioName = audioClip.sourceURL.lastPathComponent
            let dest = mediaDir.appendingPathComponent(audioName)
            do {
                try copyOrLink(from: audioClip.sourceURL, to: dest)
                var clipData = AudioClipData(from: audioClip)
                clipData.fileName = audioName
                updatedAudioClips.append(clipData)
            } catch {
                // Skip audio files that can't be copied
            }
        }
        projectFile.audioClips = updatedAudioClips

        // Handle background image
        if case .image(let imageURL) = project.background {
            let imageName = imageURL.lastPathComponent
            let dest = mediaDir.appendingPathComponent(imageName)
            try copyOrLink(from: imageURL, to: dest)
            projectFile.background = .image(fileName: imageName)
        }

        // Serialize project.json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(projectFile)
        let jsonURL = packageURL.appendingPathComponent(jsonFileName)
        try jsonData.write(to: jsonURL, options: .atomic)
    }

    // MARK: - Load

    static func load(from packageURL: URL) throws -> (projectFile: MayaProjectFile, videoURL: URL, audioURLs: [String: URL], imageURLs: [String: URL]) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: packageURL.path) else {
            throw ProjectError.fileNotFound
        }

        // Read project.json
        let jsonURL = packageURL.appendingPathComponent(jsonFileName)
        guard fm.fileExists(atPath: jsonURL.path) else {
            throw ProjectError.invalidProject
        }
        let jsonData = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()
        let projectFile = try decoder.decode(MayaProjectFile.self, from: jsonData)

        let mediaDir = packageURL.appendingPathComponent(mediaFolderName, isDirectory: true)

        // Resolve video URL
        var videoURL: URL?
        if let videoFileName = projectFile.videoFileName {
            let candidate = mediaDir.appendingPathComponent(videoFileName)
            if fm.fileExists(atPath: candidate.path) {
                videoURL = candidate
            }
        }

        // Build audio URL map (fileName -> sandbox URL)
        var audioURLs: [String: URL] = [:]
        for clipData in projectFile.audioClips {
            let candidate = mediaDir.appendingPathComponent(clipData.fileName)
            if fm.fileExists(atPath: candidate.path) {
                audioURLs[clipData.fileName] = candidate
            }
        }

        // Build background image URL map
        var imageURLs: [String: URL] = [:]
        if case .image(let fileName) = projectFile.background {
            let candidate = mediaDir.appendingPathComponent(fileName)
            if fm.fileExists(atPath: candidate.path) {
                imageURLs[fileName] = candidate
            }
        }

        guard let video = videoURL else {
            throw ProjectError.videoNotFound
        }

        return (projectFile, video, audioURLs, imageURLs)
    }

    // MARK: - Helpers

    private static func copyOrLink(from source: URL, to dest: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { return }
        do {
            try fm.linkItem(at: source, to: dest)
        } catch {
            try fm.copyItem(at: source, to: dest)
        }
    }
}

// MARK: - Errors

enum ProjectError: LocalizedError {
    case fileNotFound
    case invalidProject
    case videoNotFound

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "Project file not found."
        case .invalidProject: return "Invalid or corrupted Maya project file."
        case .videoNotFound: return "The video file is missing from the project bundle."
        }
    }
}
