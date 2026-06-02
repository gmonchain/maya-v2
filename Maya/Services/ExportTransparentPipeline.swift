import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import VideoToolbox

// MARK: - Transparent export pipeline

extension ExportService {

    func runTransparent(snapshot: Snapshot, outputURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
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
            guard let sourceAudioTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first else { continue }
            guard let compAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            let range = CMTimeRange(
                start: CMTime(seconds: audioClip.trimStartTime, preferredTimescale: 600),
                duration: CMTime(seconds: audioClip.clipDuration, preferredTimescale: 600)
            )
            let insertAt = CMTime(seconds: audioClip.timelineStart, preferredTimescale: 600)
            try? compAudioTrack.insertTimeRange(range, of: sourceAudioTrack, at: insertAt)
        }

        let totalDuration = snapshot.clips.map(\.timelineEnd).max().map {
            CMTime(seconds: $0, preferredTimescale: 600)
        } ?? .zero

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

    nonisolated func pumpAudio(
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
}
