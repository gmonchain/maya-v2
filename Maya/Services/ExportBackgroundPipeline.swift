import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import Foundation
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.gmonchain.maya", category: "ExportBackground")

// MARK: - Background export pipeline

extension ExportService {

    func runWithBackground(snapshot: Snapshot, outputURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let outputAccess = outputURL.startAccessingSecurityScopedResource()
        defer { if outputAccess { outputURL.stopAccessingSecurityScopedResource() } }

        log.info("Starting background export to \(outputURL.path, privacy: .public)")
        log.debug("outputAccess granted: \(outputAccess, privacy: .public)")

        let asset = AVURLAsset(url: snapshot.sourceVideoURL)
        log.debug("Loading AVAsset from \(snapshot.sourceVideoURL.lastPathComponent, privacy: .public)")
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            log.error("No video track found in source asset")
            throw ExportError.noVideoTrack
        }
        let sourceDuration = CMTimeGetSeconds(try await sourceVideoTrack.load(.timeRange).duration)
        log.debug("Source video track found, duration: \(sourceDuration, privacy: .public)s")

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
                // Account for playback speed: scale the inserted time range so the clip
                // plays faster/slower on the timeline.
                if clip.speed != 1.0 {
                    let trackRange = CMTimeRange(
                        start: insertAt,
                        duration: CMTime(seconds: clip.clipDuration, preferredTimescale: 600)
                    )
                    let scaledDuration = CMTime(seconds: clip.clipDuration / clip.speed, preferredTimescale: 600)
                    compTrack.scaleTimeRange(trackRange, toDuration: scaledDuration)
                }
            }
        }

        // Audio passthrough — single track, all clips placed at their timelineStart.
        // Must also scale by speed so audio stays in sync with sped-up video.
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let sourceAudio = audioTracks.first,
           let compositionAudio = composition.addMutableTrack(
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
                do {
                    try compositionAudio.insertTimeRange(range, of: sourceAudio, at: insertAt)
                    if clip.speed != 1.0 {
                        let trackRange = CMTimeRange(
                            start: insertAt,
                            duration: CMTime(seconds: clip.clipDuration, preferredTimescale: 600)
                        )
                        let scaledDuration = CMTime(seconds: clip.clipDuration / clip.speed, preferredTimescale: 600)
                        compositionAudio.scaleTimeRange(trackRange, toDuration: scaledDuration)
                    }
                } catch {
                    log.warning("Audio passthrough insert failed for clip at \(clip.timelineStart, privacy: .public)s: \(error.localizedDescription)")
                }
            }
        }

        // Collect audio-mix parameters as we add audio tracks.
        var audioMixParams: [AVMutableAudioMixInputParameters] = []

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
            let params = AVMutableAudioMixInputParameters(track: compAudioTrack)
            params.setVolume(Float(audioClip.volume), at: .zero)
            audioMixParams.append(params)
        }

        let videoMaxEnd = snapshot.clips.map(\.timelineEnd).max() ?? 0
        let audioMaxEnd = snapshot.audioClips.map(\.timelineEnd).max() ?? 0
        let totalDuration = CMTime(seconds: max(videoMaxEnd, audioMaxEnd), preferredTimescale: 600)
        log.info("Composition built — totalDuration: \(totalDuration.seconds, privacy: .public)s, clips: \(snapshot.clips.count), audioClips: \(snapshot.audioClips.count)")
        let renderSize = snapshot.renderSize
        let frameDuration = try await sourceVideoTrack.load(.minFrameDuration)
        let fps = frameDuration == .invalid || frameDuration.seconds <= 0 ? CMTime(value: 1, timescale: 60) : frameDuration

        let backgroundImage = try buildBackgroundCIImage(snapshot: snapshot, size: renderSize)
        let frameOverlay = snapshot.frameOverlayCG.map { CIImage(cgImage: $0) }
        log.debug("Background CIImage: \(backgroundImage != nil ? "present (\(Int(backgroundImage!.extent.width))×\(Int(backgroundImage!.extent.height)))" : "nil", privacy: .public), overlay: \(frameOverlay != nil ? "present" : "nil", privacy: .public)")

        // Background video track — composited behind the main content.
        let bgVideoAccess: Bool
        var backgroundVideoTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
        if let bgVideoURL = snapshot.backgroundVideoURL {
            bgVideoAccess = bgVideoURL.startAccessingSecurityScopedResource()
            let bgAsset = AVURLAsset(url: bgVideoURL)
            if let bgVideoTrack = try? await bgAsset.loadTracks(withMediaType: .video).first,
               let bgCompTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let bgDuration = (try? await bgVideoTrack.load(.timeRange).duration) ?? .zero
                if bgDuration.seconds > 0 {
                    // Loop the background video to cover totalDuration.
                    var insertTime = CMTime.zero
                    while insertTime < totalDuration {
                        let remaining = totalDuration - insertTime
                        let chunk = CMTimeCompare(remaining, bgDuration) < 0 ? remaining : bgDuration
                        let range = CMTimeRange(start: .zero, duration: chunk)
                        try? bgCompTrack.insertTimeRange(range, of: bgVideoTrack, at: insertTime)
                        insertTime = insertTime + chunk
                    }
                }
                backgroundVideoTrackID = bgCompTrack.trackID
                log.debug("Background video track added — trackID: \(backgroundVideoTrackID, privacy: .public), looped to \(totalDuration.seconds, privacy: .public)s")
            } else {
                log.warning("Could not add background video track — skipping")
            }
        } else {
            bgVideoAccess = false
        }
        defer {
            if bgVideoAccess, let bgVideoURL = snapshot.backgroundVideoURL {
                bgVideoURL.stopAccessingSecurityScopedResource()
            }
        }

        let instruction = DeviceFrameCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
        instruction.deviceFrame = snapshot.deviceFrame
        instruction.scale = snapshot.scale
        instruction.offsetFraction = snapshot.offsetFraction
        instruction.sourceTrackIDs = sourceTrackIDs
        instruction.backgroundImage = backgroundImage
        instruction.backgroundVideoTrackID = backgroundVideoTrackID
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

        guard let session = AVAssetExportSession(asset: composition, presetName: snapshot.exportQuality.backgroundPreset) else {
            log.error("AVAssetExportSession init failed for preset \(snapshot.exportQuality.backgroundPreset, privacy: .public)")
            throw ExportError.cannotInitExportSession
        }
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = snapshot.exportQuality != .ultra
        if !audioMixParams.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioMixParams
            session.audioMix = audioMix
            log.debug("Applied audio mix with \(audioMixParams.count, privacy: .public) parameter set(s)")
        }
        log.debug("AVAssetExportSession — preset: \(snapshot.exportQuality.backgroundPreset, privacy: .public), optimize: \(session.shouldOptimizeForNetworkUse, privacy: .public)")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            log.debug("Removing existing output file at \(outputURL.path, privacy: .public)")
            try FileManager.default.removeItem(at: outputURL)
        }

        let progressTask = Task.detached {
            var lastProgress: Float = -1
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                let p = session.progress
                progress(Double(p))
                if abs(p - lastProgress) > 0.01 {
                    log.debug("Export progress: \(String(format: "%.0f", p * 100), privacy: .public)%  status: \(session.status.rawValue, privacy: .public)")
                    lastProgress = p
                }
                if session.status == .completed || session.status == .failed || session.status == .cancelled {
                    if session.status == .failed {
                        if let err = session.error {
                            log.error("AVAssetExportSession failed — status: failed, error: \(err.localizedDescription, privacy: .public), code: \(err._code, privacy: .public)")
                        } else {
                            log.error("AVAssetExportSession failed — status: failed, no error object")
                        }
                    } else if session.status == .cancelled {
                        log.error("AVAssetExportSession was cancelled")
                    }
                    return
                }
            }
        }
        defer { progressTask.cancel() }

        log.info("Calling AVAssetExportSession.export()...")
        do {
            try await session.export(to: outputURL, as: .mp4)
            log.info("AVAssetExportSession.export() completed successfully")
        } catch {
            log.error("AVAssetExportSession.export() threw error: \(error.localizedDescription, privacy: .public)")
            // Also check session status after failure
            log.error("Session status after error: \(session.status.rawValue, privacy: .public), session.error: \(session.error?.localizedDescription ?? "nil", privacy: .public)")
            throw error
        }
        progress(1.0)
    }

    // MARK: - Background CIImage builder

    func buildBackgroundCIImage(snapshot: Snapshot, size: CGSize) throws -> CIImage? {
        let rect = CGRect(origin: .zero, size: size)
        switch snapshot.background {
        case .solid(let hex):
            let color = (Color(hex: hex) ?? .black).ciColor
            var result = CIImage(color: color).cropped(to: rect)
            if snapshot.backgroundBlurRadius > 0 {
                result = result.applyingGaussianBlur(sigma: snapshot.backgroundBlurRadius * 2).cropped(to: rect)
            }
            return result
        case .gradient(let spec):
            let filter = CIFilter.linearGradient()
            filter.color0 = spec.startColor.ciColor
            filter.color1 = spec.endColor.ciColor
            let r = spec.angleDegrees * .pi / 180
            let half = max(size.width, size.height)
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            filter.point0 = CGPoint(x: mid.x - cos(r) * half, y: mid.y - sin(r) * half)
            filter.point1 = CGPoint(x: mid.x + cos(r) * half, y: mid.y + sin(r) * half)
            var result = (filter.outputImage ?? CIImage(color: .black)).cropped(to: rect)
            if snapshot.backgroundBlurRadius > 0 {
                result = result.applyingGaussianBlur(sigma: snapshot.backgroundBlurRadius * 2).cropped(to: rect)
            }
            return result
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
                var result = scaled.cropped(to: rect)
                if snapshot.backgroundBlurRadius > 0 {
                    result = result.applyingGaussianBlur(sigma: snapshot.backgroundBlurRadius * 2).cropped(to: rect)
                }
                return result
            }
            return CIImage(color: .black).cropped(to: rect)
        case .video:
            // Background video frames are pulled per-frame by the compositor via
            // `backgroundVideoTrackID`. Return nil so the compositor falls through.
            return nil
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
}
