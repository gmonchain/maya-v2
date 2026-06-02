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

    static func == (lhs: AudioClip, rhs: AudioClip) -> Bool {
        lhs.id == rhs.id
            && lhs.trimStartTime == rhs.trimStartTime
            && lhs.trimEndTime == rhs.trimEndTime
            && lhs.timelineStart == rhs.timelineStart
            && lhs.volume == rhs.volume
            && lhs.isMuted == rhs.isMuted
    }
}
