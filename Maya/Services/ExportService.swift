import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import Foundation
import SwiftUI
import VideoToolbox

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
    }

    func exportWithBackground(
        project: Project,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let snap = try await MainActor.run { try ExportService.snapshot(from: project) }
        try await runWithBackground(snapshot: snap, outputURL: outputURL, progress: progress)
    }

    func exportTransparent(
        project: Project,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let snap = try await MainActor.run { try ExportService.snapshot(from: project) }
        try await runTransparent(snapshot: snap, outputURL: outputURL, progress: progress)
    }

    // MARK: - Animation shifting

    /// Maps source-time animations into composition-time coordinates for multi-clip export.
    /// For each animation, finds the clip whose source range contains it, then calculates
    /// its composition position as: (sum of preceding clip durations) + (animation start - clip trim start).
    nonisolated static func animationsForComposition(_ segments: [ZoomSegment], clips: [VideoClip]) -> [ZoomSegment] {
        guard !clips.isEmpty else { return [] }
        let minDuration = 0.4

        // Build cumulative offsets: clipOffsets[i] = sum of durations of clips 0..<i
        var clipOffsets: [Double] = []
        var cumulative: Double = 0
        for clip in clips {
            clipOffsets.append(cumulative)
            cumulative += clip.clipDuration
        }
        let totalCompositionDuration = cumulative

        return segments.compactMap { seg in
            // Find which clip this animation's start falls in.
            guard let (clipIndex, clip) = clips.enumerated().first(where: { _, clip in
                seg.startTime >= clip.trimStartTime && seg.startTime < clip.trimEndTime
            }) else { return nil }

            let compositionOffset = clipOffsets[clipIndex]
            let localStart = seg.startTime - clip.trimStartTime
            let clipDuration = clip.clipDuration

            var s = seg
            s.startTime = compositionOffset + localStart
            let effectiveEnd = min(compositionOffset + clipDuration, s.startTime + s.duration)
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
        guard let url = project.videoURL else { throw ExportError.noSourceVideo }
        let overlay: CGImage?
        if project.deviceFrame.kind == .none {
            overlay = nil
        } else {
            guard let img = FrameOverlayProvider.cgImage(for: project.deviceFrame) else {
                throw ExportError.missingFrameOverlay
            }
            overlay = img
        }
        var backgroundCG: CGImage?
        if case .image(let imageURL) = project.background {
            _ = imageURL.startAccessingSecurityScopedResource()
            defer { imageURL.stopAccessingSecurityScopedResource() }
            if let ns = NSImage(contentsOf: imageURL) {
                var r = NSRect(origin: .zero, size: ns.size)
                backgroundCG = ns.cgImage(forProposedRect: &r, context: nil, hints: nil)
            }
        }
        var blurPosterCG: CGImage?
        if case .videoBlur = project.background {
            blurPosterCG = BlurPosterCache.shared.cachedCGImage(for: url)
        }

        return Snapshot(
            sourceVideoURL: url,
            deviceFrame: project.deviceFrame,
            scale: project.scale,
            offsetFraction: project.offset,
            background: project.background,
            blurPosterCG: blurPosterCG,
            backgroundImageCG: backgroundCG,
            frameOverlayCG: overlay,
            animations: project.animations,
            renderSize: project.canvasAspect.renderSize,
            bareCornerRadius: project.bareCornerRadius,
            bareBezelWidth: project.bareBezelWidth,
            bareBezelColor: (Color(hex: project.bareBezelHex) ?? .black).ciColor,
            shadow: project.shadow,
            shadowColor: (Color(hex: project.shadow.colorHex) ?? .black).ciColor,
            clips: project.clips
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
