import AVFoundation
import AppKit
import CoreMedia
import SwiftUI

struct TimelineView: View {
    @Bindable var project: Project
    let onSelectSegment: (ZoomSegment) -> Void

    @State private var isScrubbing: Bool = false

    private let rowLabelWidth: CGFloat = 96
    private let rulerHeight: CGFloat = 20
    private let animationsHeight: CGFloat = 60
    private let trackHeight: CGFloat = 56
    private let audioTrackHeight: CGFloat = 40
    private let thumbnailCount: Int = 18

    /// Dynamic height: one row per track + spacing between tracks.
    private var videoHeight: CGFloat {
        CGFloat(project.trackCount) * trackHeight + CGFloat(max(0, project.trackCount - 1)) * 2
    }

    /// Audio section height — only shown when audio clips exist.
    private var audioSectionHeight: CGFloat {
        project.audioClips.isEmpty ? 0 : audioTrackHeight + 4
    }

    var body: some View {
        VStack(spacing: 0) {
            TimelineToolbar(project: project)
            Divider().opacity(0.4)
            HStack(alignment: .top, spacing: 12) {
                rowLabels
                tracks
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black.opacity(0.35))
    }

    private var rowLabels: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Space matching the ruler row
            Color.clear.frame(height: rulerHeight)

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Animations")
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(height: animationsHeight, alignment: .center)

            HStack(spacing: 6) {
                Image(systemName: "iphone")
                Text(project.deviceFrame.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(height: videoHeight, alignment: .center)

            if !project.audioClips.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                    Text("Audio")
                        .font(.callout.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
                .frame(height: audioTrackHeight, alignment: .center)
            }
        }
        .frame(width: rowLabelWidth, alignment: .leading)
    }

    private var tracks: some View {
        GeometryReader { proxy in
            let viewportWidth = proxy.size.width
            let zoom = max(project.timelineZoom, 0.1)
            let contentWidth = max(viewportWidth, viewportWidth * zoom)
            let duration = project.timelineDuration
            let totalHeight = rulerHeight + animationsHeight + videoHeight + audioSectionHeight + 8

            ZStack(alignment: .topLeading) {
                // Scroll interceptor — behind content, receives scrollWheel events
                // that SwiftUI views don't consume by default.
                TimelineScrollInterceptor { zoomDelta, panDelta, anchorX in
                    let effectiveZoom = max(project.timelineZoom, 0.1)
                    let effectiveContentWidth = max(viewportWidth, viewportWidth * effectiveZoom)

                    // --- Pan (horizontal scroll) ---
                    if abs(panDelta) > 0 {
                        let rawOffset = project.timelineScrollOffset - panDelta
                        project.timelineScrollOffset = max(0, min(rawOffset, max(0, effectiveContentWidth - viewportWidth)))
                    }

                    // --- Zoom (vertical scroll) ---
                    if abs(zoomDelta) > 0.000001 {
                        let oldZoom = effectiveZoom
                        let newZoom = max(0.1, min(20.0, oldZoom * (1.0 + zoomDelta)))
                        let newContentWidth = max(viewportWidth, viewportWidth * newZoom)

                        // Zoom-anchor math: keep the point under the cursor stationary.
                        // contentPoint = scrollOffset + anchorX
                        // After zoom: newOffset = contentPoint * (newZoom / oldZoom) - anchorX
                        let contentPoint = project.timelineScrollOffset + anchorX
                        let newOffset = contentPoint * (newZoom / oldZoom) - anchorX
                        let clampedOffset = max(0, min(newOffset, max(0, newContentWidth - viewportWidth)))

                        project.timelineZoom = newZoom
                        project.timelineScrollOffset = clampedOffset
                    }
                }
                .frame(width: viewportWidth, height: totalHeight)

                VStack(spacing: 4) {
                    TimeRuler(duration: duration, width: contentWidth, height: rulerHeight)
                    AnimationsTrack(
                        project: project,
                        height: animationsHeight,
                        onSelectSegment: onSelectSegment
                    )
                    TrimmableVideoClip(
                        project: project,
                        height: trackHeight,
                        thumbnailCount: thumbnailCount
                    )
                    if !project.audioClips.isEmpty {
                        AudioTrackView(
                            project: project,
                            height: audioTrackHeight
                        )
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                .offset(x: -project.timelineScrollOffset)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in
                    if duration > 0 {
                        let contentX = point.x + project.timelineScrollOffset
                        let raw = Double(contentX / contentWidth) * duration
                        project.seek(to: raw)
                    }
                }

                // Draggable playhead with time tooltip. Position is in viewport coords.
                if duration > 0 {
                    let x = CGFloat(project.currentSeconds / duration) * contentWidth - project.timelineScrollOffset
                    Playhead(
                        height: totalHeight,
                        timeText: isScrubbing ? formatTimestamp(project.currentSeconds) : nil
                    )
                    .position(x: x, y: totalHeight / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("tracksSpace"))
                            .onChanged { v in
                                guard duration > 0 else { return }
                                isScrubbing = true
                                let contentX = v.location.x + project.timelineScrollOffset
                                let t = max(0, min(Double(contentX / contentWidth) * duration, duration))
                                project.seek(to: t)
                            }
                            .onEnded { _ in isScrubbing = false }
                    )
                }
            }
            .frame(width: viewportWidth)
            .clipped()
            .coordinateSpace(name: "tracksSpace")
        }
        .frame(height: rulerHeight + animationsHeight + videoHeight + audioSectionHeight + 8)
    }

}

// MARK: - Time Ruler

private struct TimeRuler: View {
    let duration: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { ctx, size in
            guard duration > 0 else { return }
            let major = majorInterval(duration: duration)
            let minor = major / 4

            // Minor ticks first (drawn behind majors).
            var t = 0.0
            while t <= duration {
                let x = CGFloat(t / duration) * size.width
                if !nearlyMultiple(t, of: major) {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height - 3))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(path, with: .color(.white.opacity(0.22)), lineWidth: 1)
                }
                t += minor
            }

            // Major ticks + labels.
            t = 0.0
            while t <= duration {
                let x = CGFloat(t / duration) * size.width
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height - 6))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: 1)

                ctx.draw(
                    Text(format(time: t))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.75)),
                    at: CGPoint(x: x, y: 4),
                    anchor: .top
                )
                t += major
            }
        }
        .frame(width: width, height: height)
    }

    private func majorInterval(duration: Double) -> Double {
        switch duration {
        case ..<10: 1
        case ..<30: 2
        case ..<90: 5
        case ..<300: 15
        default: 30
        }
    }

    /// Treats values within a tiny epsilon as multiples — guards against floating drift.
    private func nearlyMultiple(_ t: Double, of step: Double) -> Bool {
        guard step > 0 else { return false }
        let r = t.truncatingRemainder(dividingBy: step)
        return r < 0.001 || abs(r - step) < 0.001
    }

    private func format(time t: Double) -> String {
        let total = Int(t.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Playhead

private struct Playhead: View {
    let height: CGFloat
    let timeText: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Capsule()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 2, height: height - 12)
            }
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            .allowsHitTesting(false)

            // Wider invisible grab zone for the drag gesture
            Color.white.opacity(0.001)
                .frame(width: 18, height: height)

            if let text = timeText {
                TimeTooltip(text: text)
                    .offset(y: -(height / 2) - 14)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
    }
}
