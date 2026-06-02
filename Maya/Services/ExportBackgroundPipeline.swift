import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import Foundation
import SwiftUI

// MARK: - Background export pipeline

extension ExportService {

    func runWithBackground(snapshot: Snapshot, outputURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let outputAccess = outputURL.startAccessingSecurityScopedResource()
        defer { if outputAccess { outputURL.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: snapshot.sourceVideoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else { throw ExportError.noVideoTrack }

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
                try? compositionAudio.insertTimeRange(range, of: sourceAudio, at: insertAt)
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
            // Apply volume via audio mix
            let params = AVMutableAudioMixInputParameters(track: compAudioTrack)
            params.setVolume(Float(audioClip.volume), at: .zero)
            // TODO: support per-clip volume ramping if needed in the future
        }

        let totalDuration = snapshot.clips.map(\.timelineEnd).max().map {
            CMTime(seconds: $0, preferredTimescale: 600)
        } ?? .zero
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
        instruction.sourceTrackIDs = sourceTrackIDs
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

        guard let session = AVAssetExportSession(asset: composition, presetName: snapshot.exportQuality.backgroundPreset) else {
            throw ExportError.cannotInitExportSession
        }
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = snapshot.exportQuality != .ultra

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

    // MARK: - Background CIImage builder

    func buildBackgroundCIImage(snapshot: Snapshot, size: CGSize) throws -> CIImage {
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
