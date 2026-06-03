import AVFoundation
import CoreMedia
import Foundation
import OSLog

private let log = Logger(subsystem: "com.gmonchain.maya", category: "ExportInfo")

// MARK: - Apple spec check

/// A single spec comparison result — displayed as ✓ or ✗ in the info card.
struct SpecCheck: Identifiable, Sendable {
    enum Status: Sendable {
        case pass
        case fail
    }

    let id = UUID()
    let label: String
    let spec: String          // e.g. "≤ 500 MB"
    let actual: String        // e.g. "342.1 MB"
    let status: Status
}

// MARK: - Exported video metadata

struct ExportVideoInfo: Sendable {
    let fileName: String
    let fileSizeMB: Double
    let durationSeconds: Double
    let resolutionWidth: Int
    let resolutionHeight: Int
    let codecName: String
    let codecType: UInt32
    let fps: Double
    let bitrateMbps: Double
    let audioCodec: String
    let audioCodecType: UInt32
    let audioChannels: Int
    let audioSampleRate: Double
    let hasAlpha: Bool
    let isProRes: Bool

    /// Compare every measurable spec against Apple's official App Preview
    /// requirements and return a list of pass/fail checks.
    var specChecks: [SpecCheck] {
        var checks: [SpecCheck] = []

        // 1. File size ≤ 500 MB
        checks.append(SpecCheck(
            label: "File size",
            spec: "≤ 500 MB",
            actual: String(format: "%.1f MB", fileSizeMB),
            status: fileSizeMB <= 500 ? .pass : .fail
        ))

        // 2. Duration 15–30 s
        checks.append(SpecCheck(
            label: "Duration",
            spec: "15–30 s",
            actual: String(format: "%.1f s", durationSeconds),
            status: (15...30).contains(durationSeconds) ? .pass : .fail
        ))

        // 3. FPS ≤ 30
        checks.append(SpecCheck(
            label: "Frame rate",
            spec: "≤ 30 fps",
            actual: String(format: "%.0f fps", fps),
            status: fps <= 30 ? .pass : .fail
        ))

        // 4. Codec: H.264 or ProRes 422 (HQ)
        let codecOK = codecType == kCMVideoCodecType_H264 || isProRes
        checks.append(SpecCheck(
            label: "Video codec",
            spec: "H.264 or ProRes 422",
            actual: codecName,
            status: codecOK ? .pass : .fail
        ))

        // 5. Resolution (accepted App Store resolutions)
        let resolutionOK = isAcceptedAppStoreResolution(w: resolutionWidth, h: resolutionHeight)
        checks.append(SpecCheck(
            label: "Resolution",
            spec: "886×1920 / 1080×1920 / 750×1334",
            actual: "\(resolutionWidth)×\(resolutionHeight)",
            status: resolutionOK ? .pass : .fail
        ))

        // 6. Bitrate: 10–12 Mbps for H.264
        let bitrateOK = bitrateMbps >= 8 && bitrateMbps <= 14
        checks.append(SpecCheck(
            label: "Bitrate",
            spec: "10–12 Mbps",
            actual: String(format: "%.0f Mbps", bitrateMbps),
            status: bitrateOK ? .pass : .fail
        ))

        // 7. Audio codec: AAC 256kbps
        let isAAC = audioCodecType == kAudioFormatMPEG4AAC
            || audioCodecType == kAudioFormatMPEG4AAC_HE
            || audioCodecType == kAudioFormatMPEG4AAC_LD
        checks.append(SpecCheck(
            label: "Audio codec",
            spec: "AAC",
            actual: audioCodec,
            status: isAAC ? .pass : .fail
        ))

        // 8. Audio channels: stereo (2)
        checks.append(SpecCheck(
            label: "Audio channels",
            spec: "Stereo (2)",
            actual: "\(audioChannels)ch",
            status: audioChannels == 2 ? .pass : .fail
        ))

        // 9. Sample rate: 44.1kHz or 48kHz
        let srOK = abs(audioSampleRate - 44100) < 1 || abs(audioSampleRate - 48000) < 1
        checks.append(SpecCheck(
            label: "Sample rate",
            spec: "44.1 / 48 kHz",
            actual: String(format: "%.0f Hz", audioSampleRate),
            status: srOK ? .pass : .fail
        ))

        return checks
    }

    /// Returns true if (w, h) is one of Apple's accepted App Preview resolutions.
    private func isAcceptedAppStoreResolution(w: Int, h: Int) -> Bool {
        let accepted: [CGSize] = [
            CGSize(width: 886, height: 1920),
            CGSize(width: 1920, height: 886),
            CGSize(width: 1080, height: 1920),
            CGSize(width: 1920, height: 1080),
            CGSize(width: 750, height: 1334),
            CGSize(width: 1334, height: 750),
        ]
        return accepted.contains { abs($0.width - CGFloat(w)) <= 2 && abs($0.height - CGFloat(h)) <= 2 }
    }
}

// MARK: - Extractor

enum ExportedVideoInspector {

    /// Enumerate and read AVFileType-based format names.
    private static let codecNames: [UInt32: String] = [
        kCMVideoCodecType_HEVC: "HEVC/H.265",
        kCMVideoCodecType_HEVCWithAlpha: "HEVC + Alpha",
        kCMVideoCodecType_H264: "H.264",
        kCMVideoCodecType_JPEG: "JPEG",
        kCMVideoCodecType_MPEG4Video: "MPEG-4",
        kCMVideoCodecType_AppleProRes422: "ProRes 422",
        kCMVideoCodecType_AppleProRes4444: "ProRes 4444",
    ]

    private static let audioCodecNames: [UInt32: String] = [
        kAudioFormatMPEG4AAC: "AAC",
        kAudioFormatMPEG4AAC_HE: "AAC HE",
        kAudioFormatMPEG4AAC_LD: "AAC LD",
        kAudioFormatLinearPCM: "Linear PCM",
        kAudioFormatAppleLossless: "Apple Lossless",
        kAudioFormatMPEGLayer3: "MP3",
    ]

    static func inspect(file url: URL) async -> ExportVideoInfo? {
        let asset = AVURLAsset(url: url)

        let videoTracks: [AVAssetTrack]
        let audioTracks: [AVAssetTrack]
        let duration: CMTime
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
            duration = try await asset.load(.duration)
        } catch {
            log.warning("Could not inspect exported video: \(error.localizedDescription)")
            return nil
        }

        guard let videoTrack = videoTracks.first else { return nil }

        // File size
        let fileSizeBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let fileSizeMB = Double(fileSizeBytes) / 1_000_000.0

        // Duration
        let durSeconds = duration.seconds.isFinite ? duration.seconds : 0

        // Resolution
        let natSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let isPortrait = abs(preferredTransform.b) > 0 || abs(preferredTransform.c) > 0
        let w = Int(isPortrait ? abs(natSize.height) : abs(natSize.width))
        let h = Int(isPortrait ? abs(natSize.width) : abs(natSize.height))

        // Codec
        var codecName = "Unknown"
        var codecType: UInt32 = 0
        var isProRes = false
        let formatDescs = try? await videoTrack.load(.formatDescriptions) as? [CMFormatDescription]
        if let first = formatDescs?.first {
            codecType = CMFormatDescriptionGetMediaSubType(first)
            codecName = codecNames[codecType] ?? fourccToString(codecType)
            isProRes = codecType == kCMVideoCodecType_AppleProRes422
                || codecType == kCMVideoCodecType_AppleProRes4444
        }

        // FPS
        var fps: Double = 0
        let fd = try? await videoTrack.load(.minFrameDuration)
        if let d = fd, d.isValid, d.seconds > 0 {
            fps = round(1.0 / d.seconds)
        }

        // Bitrate
        var bitrateMbps: Double = 0
        if let bps = try? await videoTrack.load(.estimatedDataRate), bps > 0 {
            bitrateMbps = Double(bps) / 1_000_000.0
        } else if durSeconds > 0 {
            let totalBits = Double(fileSizeBytes) * 8
            bitrateMbps = (totalBits / durSeconds) / 1_000_000.0
        }

        // Alpha
        let hasAlpha = codecName.contains("Alpha")

        // Audio
        var audioCodec = "None"
        var audioCodecType: UInt32 = 0
        var audioChannels = 0
        var audioSampleRate: Double = 0

        if let audioTrack = audioTracks.first {
            let audioDescs = try? await audioTrack.load(.formatDescriptions) as? [CMFormatDescription]
            if let ad = audioDescs?.first {
                audioCodecType = CMFormatDescriptionGetMediaSubType(ad)
                audioCodec = audioCodecNames[audioCodecType] ?? fourccToString(audioCodecType)

                let audioDesc = ad as CMAudioFormatDescription
                if let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(audioDesc) {
                    let asbd = asbdPtr.pointee
                    audioChannels = Int(asbd.mChannelsPerFrame)
                    audioSampleRate = asbd.mSampleRate
                }
            }
        }

        let info = ExportVideoInfo(
            fileName: url.lastPathComponent,
            fileSizeMB: fileSizeMB,
            durationSeconds: durSeconds,
            resolutionWidth: w,
            resolutionHeight: h,
            codecName: codecName,
            codecType: codecType,
            fps: fps,
            bitrateMbps: bitrateMbps,
            audioCodec: audioCodec,
            audioCodecType: audioCodecType,
            audioChannels: audioChannels,
            audioSampleRate: audioSampleRate,
            hasAlpha: hasAlpha,
            isProRes: isProRes
        )

        log.debug("Exported video inspected — \(w)×\(h), \(codecName), \(String(format: "%.0f", fps))fps, \(String(format: "%.1f", bitrateMbps))Mbps")
        return info
    }

    private static func fourccToString(_ code: UInt32) -> String {
        let c1 = (code >> 24) & 0xFF
        let c2 = (code >> 16) & 0xFF
        let c3 = (code >> 8) & 0xFF
        let c4 = code & 0xFF
        let bytes = [c1, c2, c3, c4]
        let chars = bytes.map { b -> Character in
            guard let scalar = UnicodeScalar(b), scalar.isASCII else { return "?" }
            return Character(scalar)
        }
        return String(chars).trimmingCharacters(in: .whitespaces)
    }
}
