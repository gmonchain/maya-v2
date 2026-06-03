import AVFoundation
import Foundation

/// Represents an audio clip (background music, voiceover, SFX) on the project timeline.
/// Audio clips are independent from video clips — they have their own timeline position
/// and source trim range.
struct AudioClip: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceURL: URL
    /// Display name (filename without extension).
    var displayName: String

    /// Source in-point (seconds in the original audio file).
    var trimStartTime: Double
    /// Source out-point (seconds in the original audio file).
    var trimEndTime: Double

    /// Position on the project timeline (seconds).
    var timelineStart: Double

    /// Volume multiplier (0.0 – 2.0, default 1.0).
    var volume: Double = 1.0

    /// Whether this clip is muted.
    var isMuted: Bool = false

    // MARK: - Fade in/out

    /// Whether fade-in is enabled for this clip.
    var fadeInEnabled: Bool = true
    /// Duration of the fade-in ramp (seconds). Clamped to half the clip duration.
    var fadeInDuration: Double = 0.5

    /// Whether fade-out is enabled for this clip.
    var fadeOutEnabled: Bool = true
    /// Duration of the fade-out ramp (seconds). Clamped to half the clip duration.
    var fadeOutDuration: Double = 0.5

    /// Total duration of the original audio file (before any trim).
    var sourceDuration: Double

    /// Duration of the audio content after trim.
    var clipDuration: Double { max(0, trimEndTime - trimStartTime) }

    /// Right edge on the project timeline.
    var timelineEnd: Double { timelineStart + clipDuration }

    /// Minimum duration an audio clip can be trimmed down to.
    static let minDuration: Double = 0.1

    /// Converts a project-timeline second to its source-audio second within this clip.
    func timelineToSource(_ t: Double) -> Double {
        if t <= timelineStart { return trimStartTime }
        if t >= timelineEnd { return trimEndTime }
        return trimStartTime + (t - timelineStart)
    }

    /// Inverse: source-audio second to timeline second.
    func sourceToTimeline(_ s: Double) -> Double {
        timelineStart + (s - trimStartTime)
    }

    /// Returns the effective volume at a given *timeline* position,
    /// taking fade-in and fade-out into account.
    func effectiveVolume(at timelineTime: Double) -> Double {
        guard !isMuted else { return 0 }
        let rel = timelineTime - timelineStart
        let dur = clipDuration
        guard dur > 0 else { return volume }

        // Fade-in
        if fadeInEnabled && fadeInDuration > 0 {
            let fadeInEnd = min(fadeInDuration, dur / 2)
            if rel >= 0 && rel < fadeInEnd {
                return volume * (rel / fadeInEnd)
            }
        }

        // Fade-out
        if fadeOutEnabled && fadeOutDuration > 0 {
            let fadeOutStart = max(0, dur - min(fadeOutDuration, dur / 2))
            if rel > fadeOutStart && rel <= dur {
                return volume * ((dur - rel) / (dur - fadeOutStart))
            }
        }

        return volume
    }

    static func == (lhs: AudioClip, rhs: AudioClip) -> Bool {
        lhs.id == rhs.id
            && lhs.trimStartTime == rhs.trimStartTime
            && lhs.trimEndTime == rhs.trimEndTime
            && lhs.timelineStart == rhs.timelineStart
            && lhs.volume == rhs.volume
            && lhs.isMuted == rhs.isMuted
            && lhs.fadeInEnabled == rhs.fadeInEnabled
            && lhs.fadeInDuration == rhs.fadeInDuration
            && lhs.fadeOutEnabled == rhs.fadeOutEnabled
            && lhs.fadeOutDuration == rhs.fadeOutDuration
    }
}
