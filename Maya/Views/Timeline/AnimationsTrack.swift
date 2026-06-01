import SwiftUI

struct AnimationsTrack: View {
    @Bindable var project: Project
    let height: CGFloat
    let onSelectSegment: (ZoomSegment) -> Void

    @State private var hoverX: CGFloat?
    /// Set by a SegmentBlock during drag when its snapped time matches the playhead.
    /// We render a vertical guide line at that x coordinate as long as it is set.
    @State private var snapGuideX: CGFloat?

    static let snapStep: Double = 0.25
    static let playheadSnapTolerance: Double = 0.15

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let duration = project.timelineDuration

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )

                // Existing segments. Each segment lives in source coords; we find the
                // clip it belongs to and shift by that clip's display offset so it
                // appears under the correct timeline window.
                ForEach(project.animations) { segment in
                    let clipOffset = Self.displayOffset(for: segment, clips: project.clips)
                    let isLive = clipOffset != nil
                    SegmentBlock(
                        segment: segment,
                        isSelected: project.selectedAnimationID == segment.id,
                        isLive: isLive,
                        trackWidth: width,
                        totalDuration: duration,
                        clipDisplayOffset: clipOffset ?? 0,
                        playheadTime: project.currentSeconds,
                        height: height - 12,
                        onTap: {
                            project.selectedAnimationID = segment.id
                            onSelectSegment(segment)
                        },
                        onDragStart: {
                            project.pushUndo()
                        },
                        onChange: { updated in
                            project.updateZoomSegment(updated)
                        },
                        onDelete: { project.removeZoomSegment(id: segment.id) },
                        onSnap: { snappedTime in
                            if let t = snappedTime, let offset = clipOffset, duration > 0 {
                                snapGuideX = CGFloat((t + offset) / duration) * width
                            } else {
                                snapGuideX = nil
                            }
                        }
                    )
                }

                // Snap guide: vertical accent line drawn at the snapped time during a drag.
                if let gx = snapGuideX {
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.82, blue: 0.10))
                        .frame(width: 1, height: height - 8)
                        .offset(x: gx - 0.5, y: 4)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Hover-to-add: only when not over an existing segment.
                if let hx = hoverX, duration > 0 {
                    let time = (Double(hx) / Double(width)) * duration
                    if project.segment(containing: time) == nil {
                        HoverAddButton(hx: hx, height: height) {
                            let snapped = Self.snap(time, toPlayhead: project.currentSeconds)
                            let segment = project.addZoomSegment(at: snapped)
                            onSelectSegment(segment)
                        }
                    }
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    hoverX = max(0, min(p.x, width))
                case .ended:
                    hoverX = nil
                }
            }
        }
        .frame(height: height)
    }

    /// Finds the clip that contains the segment's source time range and returns
    /// the offset needed to convert source coords → timeline display coords.
    static func displayOffset(for segment: ZoomSegment, clips: [VideoClip]) -> Double? {
        guard let clip = clips.first(where: {
            segment.startTime >= $0.trimStartTime && segment.startTime < $0.trimEndTime
        }) else { return nil }
        return clip.timelineStart - clip.trimStartTime
    }

    static func snap(_ t: Double, toPlayhead playheadTime: Double? = nil) -> Double {
        if let p = playheadTime, abs(t - p) < playheadSnapTolerance {
            return p
        }
        return (t / snapStep).rounded() * snapStep
    }
}

// MARK: - Time tooltip

struct TimeTooltip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            .fixedSize()
            .transition(.opacity)
    }
}

func formatTimestamp(_ t: Double) -> String {
    let safe = max(t, 0)
    let total = Int(safe)
    let m = total / 60
    let s = total % 60
    let cs = Int((safe - floor(safe)) * 100)
    return String(format: "%d:%02d.%02d", m, s, cs)
}
