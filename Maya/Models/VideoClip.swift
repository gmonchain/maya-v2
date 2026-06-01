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

    /// Duration of the clip content (source out - source in).
    var clipDuration: Double { max(0, trimEndTime - trimStartTime) }

    /// Right edge on the project timeline.
    var timelineEnd: Double { timelineStart + clipDuration }

    /// Minimum duration a clip can be trimmed down to.
    static let minDuration: Double = 0.5

    /// Converts a project-timeline second to its source-video second within this clip.
    /// Outside the clip's timeline window, the closest source edge is returned.
    func timelineToSource(_ t: Double) -> Double {
        if t <= timelineStart { return trimStartTime }
        if t >= timelineEnd { return trimEndTime }
        return trimStartTime + (t - timelineStart)
    }

    /// Inverse: source-video second to timeline second.
    func sourceToTimeline(_ s: Double) -> Double {
        timelineStart + (s - trimStartTime)
    }
}

// MARK: - Array safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
