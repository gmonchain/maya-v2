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

    // MARK: - With background pipeline

    private func runWithBackground(snapshot: Snapshot, outputURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let outputAccess = outputURL.startAccessingSecurityScopedResource()
        defer { if outputAccess { outputURL.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: snapshot.sourceVideoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else { throw ExportError.noVideoTrack }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ExportError.cannotBuildComposition }

        // Insert each clip's trimmed range into the composition sequentially.
        var insertTime: CMTime = .zero
        for clip in snapshot.clips {
            let range = CMTimeRange(
                start: CMTime(seconds: clip.trimStartTime, preferredTimescale: 600),
                duration: CMTime(seconds: clip.clipDuration, preferredTimescale: 600)
            )
            try compositionVideoTrack.insertTimeRange(range, of: sourceVideoTrack, at: insertTime)
            insertTime = CMTimeAdd(insertTime, CMTime(seconds: clip.clipDuration, preferredTimescale: 600))
        }

        // Audio passthrough — same pattern.
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let sourceAudio = audioTracks.first,
           let compositionAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            var audioInsertTime: CMTime = .zero
            for clip in snapshot.clips {
                let range = CMTimeRange(
                    start: CMTime(seconds: clip.trimStartTime, preferredTimescale: 600),
                    duration: CMTime(seconds: clip.clipDuration, preferredTimescale: 600)
                )
                try? compositionAudio.insertTimeRange(range, of: sourceAudio, at: audioInsertTime)
                audioInsertTime = CMTimeAdd(audioInsertTime, CMTime(seconds: clip.clipDuration, preferredTimescale: 600))
            }
        }

        let totalDuration = insertTime
        let renderSize = snapshot.renderSize
        let frameDuration = try await sourceVideoTrack.load(.minFrameDuration)
        let fps = frameDuration == .invalid || frameDuration.seconds <= 0 ? CMTime(value: 1, timescale: 60) : frameDuration

        let backgroundImage = try buildBackgroundCIImage(snapshot: snapshot, size: renderSize)
        let frameOverlay = snapshot.frameOverlayCG.map { CIImage(cgImage: $0) }

        let instruction = DeviceFrameCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
        instruction.deviceFrame = snapshot.deviceFrame
        instruction.scale = snapshot.scale
        instruction.offsetFraction = snapshot.offsetFraction
        instruction.sourceTrackID = compositionVideoTrack.trackID
        instruction.backgroundImage = backgroundImage
        instruction.frameOverlay = frameOverlay
        instruction.renderTransparent = false
        // Shift animations from source coords to composition time coords.
        instruction.animations = Self.animationsForComposition(snapshot.animations, clips: snapshot.clips)
        instruction.bareCornerRadius = snapshot.bareCornerRadius
        instruction.bareBezelWidth = snapshot.bareBezelWidth
        instruction.bareBezelColor = snapshot.bareBezelColor
        instruction.shadow = snapshot.shadow
        instruction.shadowColor = snapshot.shadowColor

        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = fps
        videoComposition.renderSize = renderSize
        videoComposition.customVideoCompositorClass = DeviceFrameCompositor.self
        videoComposition.instructions = [instruction]

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.cannotInitExportSession
        }
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let progressTask = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                progress(Double(session.progress))
                if session.status == .completed || session.status == .failed || session.status == .cancelled {
                    return
                }
            }
        }
        defer { progressTask.cancel() }

        try await session.export(to: outputURL, as: .mp4)
        progress(1.0)
    }

    // MARK: - Transparent pipeline

    private func runTransparent(snapshot: Snapshot, outputURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let outputAccess = outputURL.startAccessingSecurityScopedResource()
        defer { if outputAccess { outputURL.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: snapshot.sourceVideoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else { throw ExportError.noVideoTrack }

        let rawFrameDuration = try await sourceVideoTrack.load(.minFrameDuration)
        let frameDuration: CMTime = (rawFrameDuration == .invalid || rawFrameDuration.seconds <= 0)
            ? CMTime(value: 1, timescale: 60)
            : rawFrameDuration

        let renderSize = snapshot.renderSize
        let frameOverlay = snapshot.frameOverlayCG.map { CIImage(cgImage: $0) }

        // Build a composition from all clips so the reader produces the right sequence.
        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ExportError.cannotBuildComposition }

        var insertTime: CMTime = .zero
        for clip in snapshot.clips {
            let range = CMTimeRange(
                start: CMTime(seconds: clip.trimStartTime, preferredTimescale: 600),
                duration: CMTime(seconds: clip.clipDuration, preferredTimescale: 600)
            )
            try compVideoTrack.insertTimeRange(range, of: sourceVideoTrack, at: insertTime)
            insertTime = CMTimeAdd(insertTime, CMTime(seconds: clip.clipDuration, preferredTimescale: 600))
        }

        // Audio
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let sourceAudio = audioTracks.first,
           let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            var audioInsertTime: CMTime = .zero
            for clip in snapshot.clips {
                let range = CMTimeRange(
                    start: CMTime(seconds: clip.trimStartTime, preferredTimescale: 600),
                    duration: CMTime(seconds: clip.clipDuration, preferredTimescale: 600)
                )
                try? compAudioTrack.insertTimeRange(range, of: sourceAudio, at: audioInsertTime)
                audioInsertTime = CMTimeAdd(audioInsertTime, CMTime(seconds: clip.clipDuration, preferredTimescale: 600))
            }
        }

        let totalDuration = insertTime

        let instruction = DeviceFrameCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
        instruction.deviceFrame = snapshot.deviceFrame
        instruction.scale = snapshot.scale
        instruction.offsetFraction = snapshot.offsetFraction
        instruction.sourceTrackID = compVideoTrack.trackID
        instruction.backgroundImage = nil
        instruction.frameOverlay = frameOverlay
        instruction.renderTransparent = true
        // Shift animations to composition time.
        instruction.animations = Self.animationsForComposition(snapshot.animations, clips: snapshot.clips)
        instruction.bareCornerRadius = snapshot.bareCornerRadius
        instruction.bareBezelWidth = snapshot.bareBezelWidth
        instruction.bareBezelColor = snapshot.bareBezelColor
        instruction.shadow = snapshot.shadow
        instruction.shadowColor = snapshot.shadowColor

        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = frameDuration
        videoComposition.renderSize = renderSize
        videoComposition.customVideoCompositorClass = DeviceFrameCompositor.self
        videoComposition.instructions = [instruction]

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let reader = try AVAssetReader(asset: composition)
        let compVideoTracks = try await composition.loadTracks(withMediaType: .video)
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: compVideoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = videoComposition
        if reader.canAdd(videoOutput) { reader.add(videoOutput) }

        let compAudioTracks = try await composition.loadTracks(withMediaType: .audio)
        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack = compAudioTracks.first {
            let o = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100
            ])
            if reader.canAdd(o) {
                reader.add(o)
                audioOutput = o
            }
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoCompressionProps: [String: Any] = [
            kVTCompressionPropertyKey_Quality as String: 0.85,
            kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_PremultipliedAlpha
        ]
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: videoCompressionProps
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        if writer.canAdd(videoInput) { writer.add(videoInput) }

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 128_000
            ]
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            a.expectsMediaDataInRealTime = false
            if writer.canAdd(a) {
                writer.add(a)
                audioInput = a
            }
        }

        let pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(renderSize.width),
                kCVPixelBufferHeightKey as String: Int(renderSize.height)
            ]
        )

        guard reader.startReading() else { throw ExportError.readerStartFailed(reader.error) }
        guard writer.startWriting() else { throw ExportError.writerStartFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)

        let totalSeconds = totalDuration.seconds

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                try await self.pumpVideo(
                    output: videoOutput,
                    input: videoInput,
                    adaptor: pixelAdaptor,
                    totalSeconds: totalSeconds,
                    progress: progress
                )
            }
            if let ao = audioOutput, let ai = audioInput {
                group.addTask { [self] in
                    try await self.pumpAudio(output: ao, input: ai)
                }
            }
            try await group.waitForAll()
        }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }
        if writer.status == .failed { throw writer.error ?? ExportError.writerFinishFailed }
        progress(1.0)
    }

    private nonisolated func pumpVideo(
        output: AVAssetReaderVideoCompositionOutput,
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        totalSeconds: Double,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let queue = DispatchQueue(label: "maya.export.video", qos: .userInitiated)
        let state = ContinuationGuard<Void>()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.continuation = continuation
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        state.finish(.success(()))
                        return
                    }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                    if !adaptor.append(buffer, withPresentationTime: pts) {
                        input.markAsFinished()
                        state.finish(.failure(ExportError.appendFailed))
                        return
                    }
                    if totalSeconds > 0 {
                        let p = pts.seconds / totalSeconds
                        progress(min(max(p, 0), 0.99))
                    }
                }
            }
        }
    }

    private nonisolated func pumpAudio(
        output: AVAssetReaderTrackOutput,
        input: AVAssetWriterInput
    ) async throws {
        let queue = DispatchQueue(label: "maya.export.audio", qos: .userInitiated)
        let state = ContinuationGuard<Void>()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.continuation = continuation
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        state.finish(.success(()))
                        return
                    }
                    if !input.append(sample) {
                        input.markAsFinished()
                        state.finish(.failure(ExportError.appendFailed))
                        return
                    }
                }
            }
        }
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

    // MARK: - Helpers

    private func buildBackgroundCIImage(snapshot: Snapshot, size: CGSize) throws -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        switch snapshot.background {
        case .solid(let hex):
            let color = (Color(hex: hex) ?? .black).ciColor
            return CIImage(color: color).cropped(to: rect)
        case .gradient(let spec):
            let filter = CIFilter.linearGradient()
            filter.color0 = spec.startColor.ciColor
            filter.color1 = spec.endColor.ciColor
            let r = spec.angleDegrees * .pi / 180
            let half = max(size.width, size.height)
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            filter.point0 = CGPoint(x: mid.x - cos(r) * half, y: mid.y - sin(r) * half)
            filter.point1 = CGPoint(x: mid.x + cos(r) * half, y: mid.y + sin(r) * half)
            return (filter.outputImage ?? CIImage(color: .black)).cropped(to: rect)
        case .image:
            if let cg = snapshot.backgroundImageCG {
                let img = CIImage(cgImage: cg)
                let s = img.extent.size
                guard s.width > 0, s.height > 0 else { return CIImage(color: .black).cropped(to: rect) }
                let scale = max(size.width / s.width, size.height / s.height)
                var scaled = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                scaled = scaled.transformed(by: CGAffineTransform(
                    translationX: rect.midX - scaled.extent.midX,
                    y: rect.midY - scaled.extent.midY
                ))
                return scaled.cropped(to: rect)
            }
            return CIImage(color: .black).cropped(to: rect)
        case .videoBlur:
            if let cg = snapshot.blurPosterCG {
                let img = CIImage(cgImage: cg)
                let s = img.extent.size
                guard s.width > 0, s.height > 0 else { return CIImage(color: .black).cropped(to: rect) }
                let scale = max(size.width / s.width, size.height / s.height)
                var scaled = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                scaled = scaled.transformed(by: CGAffineTransform(
                    translationX: rect.midX - scaled.extent.midX,
                    y: rect.midY - scaled.extent.midY
                ))
                return scaled.cropped(to: rect)
            }
            return CIImage(color: .black).cropped(to: rect)
        case .none:
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: rect)
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
