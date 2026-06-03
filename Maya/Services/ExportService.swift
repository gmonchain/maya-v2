import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import Foundation
import OSLog
import SwiftUI
import VideoToolbox

private let log = Logger(subsystem: "com.gmonchain.maya", category: "Export")

actor ExportService {
    struct Snapshot: @unchecked Sendable {
        /// Already inside the app's sandbox container — no security-scope dance required.
        let sourceVideoURL: URL
        let deviceFrame: DeviceFrame
        let scale: CGFloat
        let offsetFraction: CGSize
        let background: BackgroundOption
        let blurPosterCG: CGImage?
        let backgroundImageCG: CGImage?
        /// Source URL of a background video asset. Already inside the sandbox (or has
        /// security-scope access granted during export).
        let backgroundVideoURL: URL?
        /// nil when `deviceFrame.kind == .none` — the compositor skips the overlay step.
        let frameOverlayCG: CGImage?
        /// Animations in absolute source-video coordinates. The compositor converts
        /// composition time → source time via `clips` before sampling, so cross-clip
        /// animations work correctly.
        let animations: [ZoomSegment]
        let renderSize: CGSize
        let bareCornerRadius: CGFloat
        let bareBezelWidth: CGFloat
        let bareBezelColor: CIColor
        let shadow: PhoneShadow
        let shadowColor: CIColor
        /// All clips on the timeline, ordered by their position.
        let clips: [VideoClip]
        /// Additional audio clips (music, voiceover, SFX) layered on the timeline.
        let audioClips: [AudioClip]
        /// Blur radius applied to the background image (0 = sharp).
        let backgroundBlurRadius: Double
        /// User-selected export quality.
        let exportQuality: ExportQuality
        /// User-selected render size (short side in pixels).
        let exportRenderSize: ExportRenderSize
        /// User-selected frame rate.
        let exportFPS: ExportFPS
        /// User-selected video codec.
        let exportVideoCodec: ExportVideoCodec
    }

    func exportWithBackground(
        project: Project,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        log.info("▶ exportWithBackground START → output: \(outputURL.lastPathComponent, privacy: .public)")
        let snap = try await MainActor.run {
            log.debug("Building snapshot on MainActor")
            return try ExportService.snapshot(from: project)
        }
        log.info("Snapshot built — render: \(Int(snap.renderSize.width))×\(Int(snap.renderSize.height)), clips: \(snap.clips.count), animations: \(snap.animations.count), bg: \(String(describing: snap.background), privacy: .public)")
        do {
            try await runWithBackground(snapshot: snap, outputURL: outputURL, progress: progress)
            log.info("✓ exportWithBackground DONE")
        } catch {
            log.error("✗ exportWithBackground FAILED: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func exportTransparent(
        project: Project,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        log.info("▶ exportTransparent START → output: \(outputURL.lastPathComponent, privacy: .public)")
        let snap = try await MainActor.run {
            log.debug("Building snapshot on MainActor")
            return try ExportService.snapshot(from: project)
        }
        log.info("Snapshot built — render: \(Int(snap.renderSize.width))×\(Int(snap.renderSize.height)), clips: \(snap.clips.count), animations: \(snap.animations.count), transparent mode")
        do {
            try await runTransparent(snapshot: snap, outputURL: outputURL, progress: progress)
            log.info("✓ exportTransparent DONE")
        } catch {
            log.error("✗ exportTransparent FAILED: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Snapshot builder (MainActor)

    @MainActor
    static func snapshot(from project: Project) throws -> Snapshot {
        guard let url = project.videoURL else {
            log.error("Snapshot failed: no source video URL")
            throw ExportError.noSourceVideo
        }
        log.debug("Source video: \(url.lastPathComponent, privacy: .public)")

        let overlay: CGImage?
        if project.deviceFrame.kind == .none {
            overlay = nil
            log.debug("Device frame: none")
        } else {
            guard let img = FrameOverlayProvider.cgImage(for: project.deviceFrame) else {
                log.error("Snapshot failed: missing frame overlay for \(project.deviceFrame.imageName, privacy: .public)")
                throw ExportError.missingFrameOverlay
            }
            overlay = img
            log.debug("Frame overlay loaded: \(project.deviceFrame.imageName, privacy: .public) size=\(img.width)×\(img.height)")
        }

        var backgroundCG: CGImage?
        if case .image(let imageURL) = project.background {
            log.debug("Loading background image: \(imageURL.lastPathComponent, privacy: .public)")
            _ = imageURL.startAccessingSecurityScopedResource()
            defer { imageURL.stopAccessingSecurityScopedResource() }
            if let ns = NSImage(contentsOf: imageURL) {
                var r = NSRect(origin: .zero, size: ns.size)
                backgroundCG = ns.cgImage(forProposedRect: &r, context: nil, hints: nil)
                if let cg = backgroundCG {
                    log.debug("Background image loaded: \(cg.width)×\(cg.height)")
                } else {
                    log.error("Background image loaded but cgImage nil for \(imageURL.lastPathComponent, privacy: .public)")
                }
            } else {
                log.error("NSImage(contentsOf:) returned nil for \(imageURL.lastPathComponent, privacy: .public)")
            }
        }
        var blurPosterCG: CGImage?
        if case .videoBlur = project.background {
            blurPosterCG = BlurPosterCache.shared.cachedCGImage(for: url)
            log.debug("Blur poster cached: \(blurPosterCG != nil ? "yes (\(blurPosterCG!.width)×\(blurPosterCG!.height))" : "no", privacy: .public)")
        }

        var bgVideoURL: URL?
        if case .video(let videoURL) = project.background {
            log.debug("Background video: \(videoURL.lastPathComponent, privacy: .public)")
            _ = videoURL.startAccessingSecurityScopedResource()
            bgVideoURL = videoURL
        }

        let renderSize = project.canvasAspect.renderSize(forShortSide: project.exportRenderSize.shortSide)
        log.debug("Render size: \(Int(renderSize.width))×\(Int(renderSize.height)), quality: \(String(describing: project.exportQuality), privacy: .public)")

        return Snapshot(
            sourceVideoURL: url,
            deviceFrame: project.deviceFrame,
            scale: project.scale,
            offsetFraction: project.offset,
            background: project.background,
            blurPosterCG: blurPosterCG,
            backgroundImageCG: backgroundCG,
            backgroundVideoURL: bgVideoURL,
            frameOverlayCG: overlay,
            animations: project.animations,
            renderSize: renderSize,
            bareCornerRadius: project.bareCornerRadius,
            bareBezelWidth: project.bareBezelWidth,
            bareBezelColor: (Color(hex: project.bareBezelHex) ?? .black).ciColor,
            shadow: project.shadow,
            shadowColor: (Color(hex: project.shadow.colorHex) ?? .black).ciColor,
            clips: project.clips,
            audioClips: project.audioClips,
            backgroundBlurRadius: project.backgroundBlurRadius,
            exportQuality: project.exportQuality,
            exportRenderSize: project.exportRenderSize,
            exportFPS: project.exportFPS,
            exportVideoCodec: project.exportVideoCodec
        )
    }
}

// MARK: - Export error

enum ExportError: LocalizedError {
    case noSourceVideo
    case noVideoTrack
    case cannotBuildComposition
    case cannotInitExportSession
    case missingFrameOverlay
    case readerStartFailed(Error?)
    case writerStartFailed(Error?)
    case writerFinishFailed
    case appendFailed

    var errorDescription: String? {
        switch self {
        case .noSourceVideo: "No source video loaded."
        case .noVideoTrack: "Source file has no video track."
        case .cannotBuildComposition: "Failed to build the AV composition."
        case .cannotInitExportSession: "Could not initialize the export session."
        case .missingFrameOverlay: "Could not produce the iPhone frame overlay."
        case .readerStartFailed(let e): "Reader failed to start: \(e?.localizedDescription ?? "unknown")"
        case .writerStartFailed(let e): "Writer failed to start: \(e?.localizedDescription ?? "unknown")"
        case .writerFinishFailed: "Writer failed to finish."
        case .appendFailed: "Failed to append sample buffer."
        }
    }
}

// MARK: - Audio volume and fade helper

extension ExportService {
    /// Applies volume and optional fade-in/fade-out ramps to an `AVMutableAudioMixInputParameters`.
    nonisolated static func applyVolumeAndFade(
        audioClip: AudioClip,
        to params: AVMutableAudioMixInputParameters,
        composition: AVMutableComposition
    ) {
        let startTime = CMTime(seconds: audioClip.timelineStart, preferredTimescale: 600)
        let endTime = CMTime(seconds: audioClip.timelineEnd, preferredTimescale: 600)
        let clipDur = audioClip.clipDuration
        let vol = Float(audioClip.volume)

        // Fade-in
        if audioClip.fadeInEnabled && audioClip.fadeInDuration > 0 {
            let fiDur = min(audioClip.fadeInDuration, clipDur / 2)
            let fadeInEnd = CMTime(seconds: audioClip.timelineStart + fiDur, preferredTimescale: 600)
            let range = CMTimeRange(start: startTime, duration: CMTimeSubtract(fadeInEnd, startTime))
            params.setVolumeRamp(fromStartVolume: 0, toEndVolume: vol, timeRange: range)
        } else {
            params.setVolume(vol, at: startTime)
        }

        // Fade-out
        if audioClip.fadeOutEnabled && audioClip.fadeOutDuration > 0 {
            let foDur = min(audioClip.fadeOutDuration, clipDur / 2)
            let fadeOutStart = CMTime(seconds: max(audioClip.timelineStart, audioClip.timelineEnd - foDur), preferredTimescale: 600)
            let range = CMTimeRange(start: fadeOutStart, duration: CMTimeSubtract(endTime, fadeOutStart))
            params.setVolumeRamp(fromStartVolume: vol, toEndVolume: 0, timeRange: range)
        } else {
            params.setVolume(0, at: endTime)
        }
    }
}

// MARK: - Continuation guard

final class ContinuationGuard<T>: @unchecked Sendable {
    nonisolated(unsafe) var continuation: CheckedContinuation<T, Error>?
    private let lock = NSLock()

    nonisolated init() {}

    nonisolated func finish(_ result: Result<T, Error>) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        guard let c else { return }
        switch result {
        case .success(let v): c.resume(returning: v)
        case .failure(let e): c.resume(throwing: e)
        }
    }
}

// MARK: - Frame overlay provider

@MainActor
enum FrameOverlayProvider {
    static func cgImage(for frame: DeviceFrame) -> CGImage? {
        if let ns = NSImage(named: frame.imageName), ns.size.width > 1 {
            var r = NSRect(origin: .zero, size: ns.size)
            return ns.cgImage(forProposedRect: &r, context: nil, hints: nil)
        }
        // Rasterize placeholder
        let height: CGFloat = 2622
        let width = height * frame.frameAspectRatio
        let renderer = ImageRenderer(content:
            PlaceholderFrameView(frame: frame)
                .frame(width: width, height: height)
        )
        renderer.scale = 1
        return renderer.cgImage
    }
}
