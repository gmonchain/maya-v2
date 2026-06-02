import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import OSLog
import VideoToolbox

private let log = Logger(subsystem: "com.gmonchain.maya", category: "ExportTransparent")

// MARK: - Transparent export pipeline

extension ExportService {

    func runTransparent(snapshot: Snapshot, outputURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let outputAccess = outputURL.startAccessingSecurityScopedResource()
        defer { if outputAccess { outputURL.stopAccessingSecurityScopedResource() } }

        log.info("Starting transparent export to \(outputURL.path, privacy: .public)")
        log.debug("outputAccess granted: \(outputAccess, privacy: .public)")

        let asset = AVURLAsset(url: snapshot.sourceVideoURL)
        log.debug("Loading AVAsset from \(snapshot.sourceVideoURL.lastPathComponent, privacy: .public)")
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            log.error("No video track found in source asset")
            throw ExportError.noVideoTrack
        }
        let sourceDuration = CMTimeGetSeconds(try await sourceVideoTrack.load(.timeRange).duration)
        log.debug("Source video track loaded, duration: \(sourceDuration, privacy: .public)s")

        let rawFrameDuration = try await sourceVideoTrack.load(.minFrameDuration)
        let frameDuration: CMTime = (rawFrameDuration == .invalid || rawFrameDuration.seconds <= 0)
            ? CMTime(value: 1, timescale: 60)
            : rawFrameDuration

        let renderSize = snapshot.renderSize
        let frameOverlay = snapshot.frameOverlayCG.map { CIImage(cgImage: $0) }

        // Build a composition from all clips so the reader produces the right sequence.
        let composition = AVMutableComposition()

        // Group clips by track, sort each group by timelineStart, and insert
        // each clip at its actual timeline position so gaps and multi-track
        // layouts are preserved in the exported video.
        let trackGroups = Dictionary(grouping: snapshot.clips) { $0.trackIndex }
        let sortedTrackIndices = trackGroups.keys.sorted()
        var compositionTracks: [Int: AVMutableCompositionTrack] = [:]
        var sourceTrackIDs: [CMPersistentTrackID] = []

        for trackIndex in sortedTrackIndices {
            guard let compTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { throw ExportError.cannotBuildComposition }
            compositionTracks[trackIndex] = compTrack
            sourceTrackIDs.append(compTrack.trackID)

            let trackClips = (trackGroups[trackIndex] ?? []).sorted { $0.timelineStart < $1.timelineStart }
            for clip in trackClips {
                let range = CMTimeRange(
                    start: CMTime(seconds: clip.trimStartTime, preferredTimescale: 600),
                    duration: CMTime(seconds: clip.clipDuration, preferredTimescale: 600)
                )
                let insertAt = CMTime(seconds: clip.timelineStart, preferredTimescale: 600)
                try compTrack.insertTimeRange(range, of: sourceVideoTrack, at: insertAt)
            }
        }

        // Audio passthrough — single track, all clips placed at their timelineStart.
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let sourceAudio = audioTracks.first,
           let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let sortedClips = snapshot.clips.sorted { $0.timelineStart < $1.timelineStart }
            for clip in sortedClips {
                let range = CMTimeRange(
                    start: CMTime(seconds: clip.trimStartTime, preferredTimescale: 600),
                    duration: CMTime(seconds: clip.clipDuration, preferredTimescale: 600)
                )
                let insertAt = CMTime(seconds: clip.timelineStart, preferredTimescale: 600)
                try? compAudioTrack.insertTimeRange(range, of: sourceAudio, at: insertAt)
            }
        }

        // Additional audio clips (music, voiceover, SFX)
        for audioClip in snapshot.audioClips where !audioClip.isMuted {
            let audioAsset = AVURLAsset(url: audioClip.sourceURL)
            guard let sourceAudioTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first else {
                log.warning("Audio clip '\(audioClip.displayName, privacy: .public)': no audio track found in asset")
                continue
            }
            guard let compAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                log.error("Could not add audio composition track for clip '\(audioClip.displayName, privacy: .public)'")
                continue
            }

            let trackTimeRange = (try? await sourceAudioTrack.load(.timeRange)) ?? CMTimeRange(start: .zero, duration: .zero)
            let trackEnd = CMTimeRangeGetEnd(trackTimeRange)
            // Subtract 1 unit at the track's native timescale to account for
            // Double→CMTime floating-point imprecision. Without this margin,
            // `CMTime(seconds: trimEnd)` can land past the track boundary
            // at the native timescale → -11841 InvalidSourceMedia.
            let safeTrackEnd = CMTimeSubtract(trackEnd, CMTime(value: 1, timescale: trackEnd.timescale))

            let desiredStart = CMTime(seconds: audioClip.trimStartTime, preferredTimescale: 600)
            let desiredEnd   = CMTime(seconds: audioClip.trimEndTime,   preferredTimescale: 600)

            let safeStart = CMTimeMaximum(.zero, CMTimeMinimum(desiredStart, safeTrackEnd))
            let safeEnd   = CMTimeMinimum(desiredEnd, safeTrackEnd)
            let safeDuration = CMTimeMaximum(
                CMTime(value: 1, timescale: 600),
                CMTimeSubtract(safeEnd, safeStart)
            )

            let range = CMTimeRange(start: safeStart, duration: safeDuration)
            let insertAt = CMTime(seconds: audioClip.timelineStart, preferredTimescale: 600)
            do {
                try compAudioTrack.insertTimeRange(range, of: sourceAudioTrack, at: insertAt)
            } catch {
                log.error("Failed to insert audio clip '\(audioClip.displayName, privacy: .public)' (start=\(range.start.seconds, privacy: .public), dur=\(range.duration.seconds, privacy: .public), trackEnd=\(trackEnd.seconds, privacy: .public)): \(error.localizedDescription)")
                continue
            }
        }

        let videoMaxEnd = snapshot.clips.map(\.timelineEnd).max() ?? 0
        let audioMaxEnd = snapshot.audioClips.map(\.timelineEnd).max() ?? 0
        let totalDuration = CMTime(seconds: max(videoMaxEnd, audioMaxEnd), preferredTimescale: 600)
        log.info("Composition built — totalDuration: \(totalDuration.seconds, privacy: .public)s, clips: \(snapshot.clips.count), audioClips: \(snapshot.audioClips.count)")

        let instruction = DeviceFrameCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
        instruction.deviceFrame = snapshot.deviceFrame
        instruction.scale = snapshot.scale
        instruction.offsetFraction = snapshot.offsetFraction
        instruction.sourceTrackIDs = sourceTrackIDs
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
        var audioOutput: AVAssetReaderAudioMixOutput?
        if !compAudioTracks.isEmpty {
            let o = AVAssetReaderAudioMixOutput(audioTracks: compAudioTracks, audioSettings: [
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
                log.debug("Audio reader: \(compAudioTracks.count, privacy: .public) track(s) via AVAssetReaderAudioMixOutput")
            }
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        var videoCompressionProps: [String: Any] = [
            kVTCompressionPropertyKey_Quality as String: snapshot.exportQuality.transparentQuality,
            kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_PremultipliedAlpha
        ]
        if let baseBitrate = snapshot.exportQuality.transparentBitrate {
            // Scale bitrate proportionally to pixel count so higher resolutions
            // don't suffer from undersized bitrate budgets.
            let scaleFactor = snapshot.exportRenderSize.shortSide / 1080
            videoCompressionProps[kVTCompressionPropertyKey_AverageBitRate as String] = Int(Double(baseBitrate) * scaleFactor * scaleFactor)
        }
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

        guard reader.startReading() else {
            let readerErr = reader.error
            log.error("AVAssetReader failed to start: \(readerErr?.localizedDescription ?? "unknown", privacy: .public), status: \(reader.status.rawValue, privacy: .public)")
            throw ExportError.readerStartFailed(readerErr)
        }
        guard writer.startWriting() else {
            let writerErr = writer.error
            log.error("AVAssetWriter failed to start: \(writerErr?.localizedDescription ?? "unknown", privacy: .public), status: \(writer.status.rawValue, privacy: .public)")
            throw ExportError.writerStartFailed(writerErr)
        }
        writer.startSession(atSourceTime: .zero)
        log.debug("Reader & writer started, beginning frame pump...")

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

        log.info("Video & audio pumping done, finishing writer...")
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }
        if writer.status == .failed {
            let writerErr = writer.error
            log.error("AVAssetWriter finishWriting failed — status: failed, error: \(writerErr?.localizedDescription ?? "unknown", privacy: .public), code: \(writerErr?._code ?? 0, privacy: .public)")
            throw writerErr ?? ExportError.writerFinishFailed
        }
        if writer.status == .cancelled {
            log.error("AVAssetWriter was cancelled")
        }
        log.info("Writer finished — status: \(writer.status.rawValue, privacy: .public)")
        progress(1.0)
    }

    // MARK: - Pump helpers

    nonisolated func pumpVideo(
        output: AVAssetReaderVideoCompositionOutput,
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        totalSeconds: Double,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let queue = DispatchQueue(label: "maya.export.video", qos: .userInitiated)
        let state = ContinuationGuard<Void>()
        var frameCount = 0
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.continuation = continuation
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        log.debug("Video pump: no more samples after \(frameCount, privacy: .public) frames")
                        input.markAsFinished()
                        state.finish(.success(()))
                        return
                    }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    guard let buffer = CMSampleBufferGetImageBuffer(sample) else {
                        log.warning("Video pump: sample at \(pts.seconds, privacy: .public)s has no image buffer — skipping")
                        continue
                    }
                    if !adaptor.append(buffer, withPresentationTime: pts) {
                            log.error("Video pump: adaptor.append failed at frame \(frameCount, privacy: .public) (t=\(pts.seconds, privacy: .public)s), input ready: \(input.isReadyForMoreMediaData, privacy: .public)")
                        input.markAsFinished()
                        state.finish(.failure(ExportError.appendFailed))
                        return
                    }
                    frameCount += 1
                    if totalSeconds > 0 {
                        let p = pts.seconds / totalSeconds
                        progress(min(max(p, 0), 0.99))
                    }
                }
            }
        }
        log.debug("Video pump finished: \(frameCount, privacy: .public) total frames")
    }

    nonisolated func pumpAudio(
        output: AVAssetReaderAudioMixOutput,
        input: AVAssetWriterInput
    ) async throws {
        let queue = DispatchQueue(label: "maya.export.audio", qos: .userInitiated)
        let state = ContinuationGuard<Void>()
        var frameCount = 0
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.continuation = continuation
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        log.debug("Audio pump: no more samples after \(frameCount, privacy: .public) frames")
                        input.markAsFinished()
                        state.finish(.success(()))
                        return
                    }
                    if !input.append(sample) {
                        log.error("Audio pump: append failed at frame \(frameCount, privacy: .public)")
                        input.markAsFinished()
                        state.finish(.failure(ExportError.appendFailed))
                        return
                    }
                    frameCount += 1
                }
            }
        }
        log.debug("Audio pump finished: \(frameCount, privacy: .public) total frames")
    }
}
