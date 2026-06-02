import Foundation

/// Represents a segment of the source video on the project timeline.
/// Multiple clips allow splitting the video into independent segments,
/// each with its own source in/out points and timeline position.
struct VideoClip: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Source in-point (seconds in the original video file).
    var trimStartTime: Double
    /// Source out-point (seconds in the original video file).
    var trimEndTime: Double
    /// Position on the project timeline (seconds).
    /// Independent from source times — the user can slide clips around.
    var timelineStart: Double
    /// Which track row this clip sits on (0 = bottom track).
    var trackIndex: Int = 0
    /// Playback speed multiplier (1.0 = normal, 2.0 = double speed, 0.5 = half speed).
    var speed: Double = 1.0

    /// Duration of the clip content (source out - source in).
    var clipDuration: Double { max(0, trimEndTime - trimStartTime) }

    /// Duration on the timeline (accounting for playback speed).
    /// At 2x speed, a 60s source clip takes 30s on timeline.
    var timelineDuration: Double { clipDuration / speed }

    /// Right edge on the project timeline.
    var timelineEnd: Double { timelineStart + timelineDuration }

    /// Minimum duration a clip can be trimmed down to.
    static let minDuration: Double = 0.5

    /// Converts a project-timeline second to its source-video second within this clip.
    /// Outside the clip's timeline window, the closest source edge is returned.
    /// Accounts for playback speed: timeline duration = source duration / speed.
    func timelineToSource(_ t: Double) -> Double {
        if t <= timelineStart { return trimStartTime }
        if t >= timelineEnd { return trimEndTime }
        return trimStartTime + (t - timelineStart) * speed
    }

    /// Inverse: source-video second to timeline second.
    /// Accounts for playback speed.
    func sourceToTimeline(_ s: Double) -> Double {
        timelineStart + (s - trimStartTime) / speed
    }
}

// MARK: - Array safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
