import AVFoundation
import CoreMedia
import Foundation
import OSLog

private let log = Logger(subsystem: "com.gmonchain.maya", category: "AppStoreCheck")

// MARK: - Validation issue model

struct AppStoreValidationIssue: Identifiable, Hashable, Sendable {
    enum Severity: String, CaseIterable, Sendable {
        /// Blocks export — video cannot be uploaded to App Store Connect.
        case error
        /// Suggests improvement but does not block export.
        case warning
    }

    let id = UUID()
    let severity: Severity
    let title: String
    let message: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AppStoreValidationIssue, rhs: AppStoreValidationIssue) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Validator

enum AppStorePreviewValidator {

    /// Run all checks. When export re-encodes the video (which Maya does),
    /// FPS and codec are determined by the user's export settings, NOT by
    /// the source video. Pass `exportFPS` / `exportVideoCodec` to check
    /// those instead.
    static func validate(
        sourceVideo url: URL,
        canvasAspect: CanvasAspectRatio,
        timelineDurationS: Double? = nil,
        exportFPS: ExportFPS? = nil,
        exportVideoCodec: ExportVideoCodec? = nil
    ) async -> [AppStoreValidationIssue] {
        guard canvasAspect == .appStorePortrait || canvasAspect == .appStoreLandscape else {
            return []
        }
        let asset = AVURLAsset(url: url)
        var issues: [AppStoreValidationIssue] = []

        // ── Load tracks (only for checks that need source info) ─────────
        let videoTracks: [AVAssetTrack]
        let audioTracks: [AVAssetTrack]
        let duration: CMTime
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
            duration = try await asset.load(.duration)
        } catch {
            log.warning("AppStore val: could not load asset — \(error.localizedDescription)")
            return []
        }

        if videoTracks.first == nil {
            issues.append(AppStoreValidationIssue(
                severity: .error,
                title: "No video track",
                message: "The source file has no video track."
            ))
            return issues
        }

        // ── 1. Duration 15–30 s (from timeline/clips) ──────────────────
        let durSeconds: Double
        if let td = timelineDurationS, td > 0 {
            durSeconds = td
        } else {
            durSeconds = duration.seconds.isFinite ? duration.seconds : 0
        }
        if durSeconds < 15 {
            issues.append(AppStoreValidationIssue(
                severity: .error,
                title: "Video too short",
                message: "App Preview must be 15–30 seconds. This video is \(String(format: "%.1f", durSeconds))s."
            ))
        } else if durSeconds > 30 {
            issues.append(AppStoreValidationIssue(
                severity: .error,
                title: "Video too long",
                message: "App Preview must be 15–30 seconds. This video is \(String(format: "%.1f", durSeconds))s."
            ))
        }

        // ── 2. FPS ≤ 30 — use export setting when available ────────────
        let fpsForExport = exportFPS ?? .fps30
        if fpsForExport == .fps60 {
            issues.append(AppStoreValidationIssue(
                severity: .error,
                title: "Frame rate 60 fps",
                message: "Apple requires max 30 fps for App Previews. Change export setting to 30 fps."
            ))
        }

        // ── 3. Codec — use export setting when available ───────────────
        let codecForExport = exportVideoCodec ?? .h264
        if codecForExport == .hevc {
            issues.append(AppStoreValidationIssue(
                severity: .error,
                title: "Codec: HEVC/H.265",
                message: "Apple only accepts H.264 and ProRes 422 (HQ). Change export codec to H.264."
            ))
        }

        // ── 4. Bitrate (source only, informational) ────────────────────
        if let videoTrack = videoTracks.first {
            let dataRate = try? await videoTrack.load(.estimatedDataRate)
            if let bps = dataRate, bps > 0 {
                let mbps = Double(bps) / 1_000_000.0
                if mbps < 8 {
                    issues.append(AppStoreValidationIssue(
                        severity: .warning,
                        title: "Source bitrate low",
                        message: "\(String(format: "%.0f", mbps)) Mbps is below Apple's 10–12 Mbps target. Export will re-encode."
                    ))
                } else if mbps > 14 {
                    issues.append(AppStoreValidationIssue(
                        severity: .warning,
                        title: "Source bitrate high",
                        message: "\(String(format: "%.0f", mbps)) Mbps exceeds Apple's 10–12 Mbps target. Export will re-encode."
                    ))
                }
            }
        }

        // ── 5. Audio — AAC stereo, 44.1/48 kHz ─────────────────────────
        if let audioTrack = audioTracks.first {
            let audioDescs = try? await audioTrack.load(.formatDescriptions) as? [CMFormatDescription]
            if let ad = audioDescs?.first {
                let audioFormat = CMFormatDescriptionGetMediaSubType(ad)
                let isAAC = audioFormat == kAudioFormatMPEG4AAC
                    || audioFormat == kAudioFormatMPEG4AAC_HE
                    || audioFormat == kAudioFormatMPEG4AAC_LD
                if !isAAC {
                    issues.append(AppStoreValidationIssue(
                        severity: .warning,
                        title: "Audio not AAC",
                        message: "Apple requires AAC stereo 256 kbps. Current format may cause rejection."
                    ))
                }

                let audioDesc = ad as CMAudioFormatDescription
                if let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(audioDesc) {
                    let asbd = asbdPtr.pointee
                    if asbd.mChannelsPerFrame != 2 {
                        issues.append(AppStoreValidationIssue(
                            severity: .warning,
                            title: "Audio not stereo",
                            message: "Apple requires stereo (2-channel) audio. Current audio has \(asbd.mChannelsPerFrame) channel(s)."
                        ))
                    }
                    let sr = asbd.mSampleRate
                    let srOK = abs(sr - 44100) < 1 || abs(sr - 48000) < 1
                    if !srOK {
                        issues.append(AppStoreValidationIssue(
                            severity: .warning,
                            title: "Sample rate \(String(format: "%.0f Hz", sr))",
                            message: "Apple requires 44.1 kHz or 48 kHz sample rate."
                        ))
                    }
                }
            }
        } else {
            issues.append(AppStoreValidationIssue(
                severity: .warning,
                title: "No audio track",
                message: "App Preview videos should include AAC stereo audio. Without audio, the preview may be rejected."
            ))
        }

        // ── 6. Canva / CapCut metadata detection ───────────────────────
        let commonMetadata = asset.commonMetadata
        let softwareItems = AVMetadataItem.metadataItems(
            from: commonMetadata,
            withKey: AVMetadataKey.commonKeySoftware,
            keySpace: .common
        )
        if let swItem = softwareItems.first,
           let swValue = try? await swItem.load(.value) as? String {
            let lower = swValue.lowercased()
            if lower.contains("canva") || lower.contains("capcut") || lower.contains("cap cut") {
                issues.append(AppStoreValidationIssue(
                    severity: .warning,
                    title: "Exported from \(swValue.trimmingCharacters(in: .whitespaces))",
                    message: "Videos from Canva/CapCut may have incompatible metadata or encoding."
                ))
            }
        }
        let qtMetadata = asset.metadata(forFormat: .quickTimeMetadata)
        let softwareQTs = AVMetadataItem.metadataItems(from: qtMetadata, withKey: AVMetadataKey.commonKeySoftware, keySpace: .quickTimeMetadata)
        if let qtSW = softwareQTs.first,
           let qtValue = try? await qtSW.load(.value) as? String {
            let lower = qtValue.lowercased()
            if lower.contains("canva") || lower.contains("capcut") || lower.contains("cap cut") {
                if !issues.contains(where: { $0.title.contains("Canva") || $0.title.contains("CapCut") }) {
                    issues.append(AppStoreValidationIssue(
                        severity: .warning,
                        title: "Exported from \(qtValue.trimmingCharacters(in: .whitespaces))",
                        message: "Videos from Canva/CapCut may have incompatible metadata or encoding."
                    ))
                }
            }
        }

        log.debug("AppStore validation complete — \(issues.count) issue(s)")
        return issues
    }
}
