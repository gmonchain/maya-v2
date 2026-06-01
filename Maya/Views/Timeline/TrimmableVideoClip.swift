import SwiftUI

/// Trim + position-aware video clip(s) for the timeline.
///
/// Renders all clips on the timeline. Each clip is a self-contained block:
///   • Position on the timeline → `clip.timelineStart`
///   • Source IN/OUT inside the file → `clip.trimStartTime` / `clip.trimEndTime`
///
/// Drag the body to slide a clip horizontally. Drag the yellow handles to trim
/// the source range. Tap a clip to select it as the active clip.
/// Right-click for context menu with delete option.
struct TrimmableVideoClip: View {
    @Bindable var project: Project
    let height: CGFloat
    let thumbnailCount: Int

    @State private var isHovering: Bool = false

    // Per-interaction state: which clip index is being dragged/trimmed.
    @State private var draggedClipIndex: Int?
    @State private var activeHandle: TrimEdge?
    @State private var handleDragSnapshot: HandleSnapshot?
    @State private var bodyDragSnapshot: Double?
    @State private var isDraggingBody: Bool = false

    @State private var hoveredHandle: TrimEdge?

    private enum TrimEdge { case start, end }
    private struct HandleSnapshot {
        let trimStart: Double
        let trimEnd: Double
        let timelineStart: Double
        let clipID: UUID
    }

    private let handleWidth: CGFloat = 10
    private let handleHitWidth: CGFloat = 22
    private let trimColor = Color(red: 1.0, green: 0.82, blue: 0.10)
    private let activeClipTint = Color(red: 1.0, green: 0.82, blue: 0.10)
    private let inactiveClipTint = Color(red: 0.7, green: 0.65, blue: 0.30)
    private let cornerRadius: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let timelineDuration = project.timelineDuration

            ZStack(alignment: .topLeading) {
                // Empty timeline track — shown wherever clips aren't.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.white.opacity(0.06), lineWidth: 1)
                    )
                    .frame(width: width, height: height)

                if timelineDuration > 0, project.videoURL != nil {
                    ForEach(Array(project.clips.enumerated()), id: \.element.id) { index, clip in
                        let clipStartX = CGFloat(clip.timelineStart / timelineDuration) * width
                        let clipEndX = CGFloat(clip.timelineEnd / timelineDuration) * width
                        let clipWidth = max(0, clipEndX - clipStartX)
                        let isActive = clip.id == project.activeClipID

                        clipBlock(clip: clip, clipIndex: index, clipWidth: clipWidth, timelineWidth: width, timelineDuration: timelineDuration)
                            .frame(width: clipWidth, height: height)
                            .offset(x: clipStartX)
                            .onTapGesture {
                                project.activeClipID = clip.id
                            }
                            .contextMenu {
                                Button {
                                    project.activeClipID = clip.id
                                    project.deleteActiveClip()
                                } label: {
                                    Label("Delete clip", systemImage: "trash")
                                }
                                .disabled(project.clips.count <= 1)
                            }

                        handle(edge: .start, clip: clip, clipIndex: index, x: clipStartX, timelineWidth: width, timelineDuration: timelineDuration)
                        handle(edge: .end, clip: clip, clipIndex: index, x: clipEndX, timelineWidth: width, timelineDuration: timelineDuration)

                        // Clip label
                        if clipWidth > 60 {
                            Text(String(format: "%.1fs", clip.clipDuration))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(isActive ? .white.opacity(0.9) : .white.opacity(0.5))
                                .position(x: clipStartX + clipWidth / 2, y: height / 2)
                                .allowsHitTesting(false)
                        }
                    }

                    // Time tooltip for the active handle
                    if let edge = activeHandle, let idx = draggedClipIndex, idx < project.clips.count {
                        let clip = project.clips[idx]
                        let displayTime = edge == .start ? clip.timelineStart : clip.timelineEnd
                        let timelineDur = max(project.timelineDuration, 0.001)
                        let x = edge == .start
                            ? CGFloat(clip.timelineStart / timelineDur) * width
                            : CGFloat(clip.timelineEnd / timelineDur) * width
                        TimeTooltip(text: formatTimestamp(displayTime))
                            .offset(x: x - 28, y: -26)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: width, height: height)
            .onHover { isHovering = $0 }
        }
        .frame(height: height)
    }

    /// The clip block: thumbnails for the trim range + yellow border + body drag.
    private func clipBlock(clip: VideoClip, clipIndex: Int, clipWidth: CGFloat, timelineWidth: CGFloat, timelineDuration: Double) -> some View {
        let sourceDuration = max(project.durationSeconds, 0.001)
        let clipDur = max(clip.clipDuration, 0.001)
        let virtualStripWidth = clipWidth * (sourceDuration / clipDur)
        let stripOffsetX = -CGFloat(clip.trimStartTime / sourceDuration) * virtualStripWidth
        let isActive = clip.id == project.activeClipID
        let isDragged = draggedClipIndex == clipIndex

        return ZStack {
            if let url = project.videoURL {
                VideoThumbnailStrip(
                    url: url,
                    thumbnailCount: thumbnailCount,
                    height: height
                )
                .frame(width: virtualStripWidth, height: height)
                .offset(x: stripOffsetX)
                .frame(width: clipWidth, height: height, alignment: .leading)
                .clipped()
            }

            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    (activeHandle != nil && isDragged) || (isDraggingBody && isDragged)
                        ? (isActive ? activeClipTint : inactiveClipTint)
                        : (isActive ? activeClipTint.opacity(isHovering ? 0.9 : 0.55) : inactiveClipTint.opacity(0.35)),
                    lineWidth: (activeHandle != nil && isDragged) || (isDraggingBody && isDragged) ? 3 : 2
                )
                .frame(width: clipWidth, height: height)
                .animation(.easeOut(duration: 0.15), value: activeHandle)
                .animation(.easeOut(duration: 0.15), value: isHovering)
                .animation(.easeOut(duration: 0.15), value: isDraggingBody)
        }
        .frame(width: clipWidth, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .local)
                .onChanged { v in
                    if bodyDragSnapshot == nil {
                        project.pushUndo()
                        bodyDragSnapshot = clip.timelineStart
                        draggedClipIndex = clipIndex
                        project.activeClipID = clip.id
                    }
                    isDraggingBody = true
                    guard let snapStart = bodyDragSnapshot,
                          timelineWidth > 0,
                          timelineDuration > 0 else { return }
                    let dt = (Double(v.translation.width) / Double(timelineWidth)) * timelineDuration
                    let proposed = max(0, snapStart + dt)
                    project.clips[clipIndex].timelineStart = proposed
                    // Keep playhead inside the dragged clip
                    if project.currentSeconds < project.clips[clipIndex].timelineStart {
                        project.seek(to: project.clips[clipIndex].timelineStart)
                    } else if project.currentSeconds > project.clips[clipIndex].timelineEnd {
                        project.seek(to: project.clips[clipIndex].timelineEnd)
                    }
                }
                .onEnded { _ in
                    bodyDragSnapshot = nil
                    draggedClipIndex = nil
                    isDraggingBody = false
                }
        )
    }

    private func handle(edge: TrimEdge, clip: VideoClip, clipIndex: Int, x: CGFloat, timelineWidth: CGFloat, timelineDuration: Double) -> some View {
        let isActive = activeHandle == edge && draggedClipIndex == clipIndex

        return ZStack {
            Color.white.opacity(0.001)
                .frame(width: handleHitWidth, height: height)

            RoundedRectangle(cornerRadius: 3)
                .fill(isActive ? activeClipTint : inactiveClipTint)
                .frame(width: handleWidth, height: height + 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 2, height: height * 0.4)
                )
                .shadow(color: .black.opacity(0.35), radius: isActive ? 6 : 2, y: 1)
                .scaleEffect(isActive ? 1.08 : (isHovering ? 1.02 : 1.0))
                .animation(.easeOut(duration: 0.15), value: isActive)
                .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .contentShape(Rectangle())
        .position(x: x, y: height / 2)
        .onHover { hovering in
            if hovering {
                hoveredHandle = edge
            } else if hoveredHandle == edge {
                hoveredHandle = nil
            }
            applyCursor()
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { v in
                    if handleDragSnapshot == nil {
                        project.pushUndo()
                        handleDragSnapshot = HandleSnapshot(
                            trimStart: clip.trimStartTime,
                            trimEnd: clip.trimEndTime,
                            timelineStart: clip.timelineStart,
                            clipID: clip.id
                        )
                        draggedClipIndex = clipIndex
                        project.activeClipID = clip.id
                    }
                    activeHandle = edge
                    guard let snap = handleDragSnapshot,
                          timelineWidth > 0,
                          timelineDuration > 0 else { return }
                    let dt = (Double(v.translation.width) / Double(timelineWidth)) * timelineDuration
                    switch edge {
                    case .start:
                        let proposedTrim = snap.trimStart + dt
                        let clampedTrim = max(0, min(proposedTrim, snap.trimEnd - VideoClip.minDuration))
                        let actualDelta = clampedTrim - snap.trimStart
                        project.clips[clipIndex].trimStartTime = clampedTrim
                        project.clips[clipIndex].timelineStart = max(0, snap.timelineStart + actualDelta)
                        if project.currentSeconds < project.clips[clipIndex].timelineStart {
                            project.seek(to: project.clips[clipIndex].timelineStart)
                        }
                    case .end:
                        let proposedTrim = snap.trimEnd + dt
                        let clamped = max(snap.trimStart + VideoClip.minDuration, min(proposedTrim, project.durationSeconds))
                        project.clips[clipIndex].trimEndTime = clamped
                        if project.currentSeconds > project.clips[clipIndex].timelineEnd {
                            project.seek(to: project.clips[clipIndex].timelineEnd)
                        }
                    }
                }
                .onEnded { _ in
                    handleDragSnapshot = nil
                    activeHandle = nil
                    draggedClipIndex = nil
                    hoveredHandle = nil
                    applyCursor()
                }
        )
    }

    /// Centralized cursor logic — handles always win over the body, dragging body shows
    /// closed hand, hovering body shows open hand, nothing → arrow.
    private func applyCursor() {
        if hoveredHandle != nil {
            NSCursor.resizeLeftRight.set()
        } else if isDraggingBody {
            NSCursor.closedHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}
