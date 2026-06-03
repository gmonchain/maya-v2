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
        /// Animations in absolute source-video coordinates. Each export path shifts/filters
        /// them as appropriate for its time base.
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

    // MARK: - Animation shifting

    /// Maps source-time animations into composition-time coordinates for multi-clip export.
    /// Clips are placed at their `timelineStart` in the composition, so the mapping is:
    ///   compositionTime = clip.timelineStart + (animationSourceTime − clip.trimStartTime) / clip.speed
    /// Animation duration is also divided by speed since the clip plays back faster.
    nonisolated static func animationsForComposition(_ segments: [ZoomSegment], clips: [VideoClip]) -> [ZoomSegment] {
        guard !clips.isEmpty else { return [] }
        let minDuration = 0.4
        let totalCompositionDuration = clips.map(\.timelineEnd).max() ?? 0

        return segments.compactMap { seg in
            // Find which clip this animation's start falls in.
            guard let clip = clips.first(where: { clip in
                seg.startTime >= clip.trimStartTime && seg.startTime < clip.trimEndTime
            }) else { return nil }

            let speed = clip.speed
            // Map source time to composition time, accounting for playback speed
            let compositionStart = clip.timelineStart + (seg.startTime - clip.trimStartTime) / speed
            // Animation duration in source time → duration in composition time
            let compositionDuration = seg.duration / speed

            var s = seg
            s.startTime = compositionStart
            let effectiveEnd = min(clip.timelineEnd, compositionStart + compositionDuration)
            s.duration = max(minDuration, effectiveEnd - s.startTime)
            // Clamp total composition
            if s.startTime >= totalCompositionDuration { return nil }
            let half = max(0.05, s.duration / 2)
            s.transitionIn = min(s.transitionIn, half)
            s.transitionOut = min(s.transitionOut, half)
            return s
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
            exportRenderSize: project.exportRenderSize
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
