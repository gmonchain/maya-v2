import SwiftUI

/// Trim + position-aware video clip(s) for the timeline — now multi-track.
///
/// Renders all clips across all tracks. Each track is a horizontal row.
/// Clips on the same track are arranged left-to-right; clips on different
/// tracks stack vertically. Drag the body to slide a clip horizontally
/// (and vertically to move between tracks). Drag the yellow handles to
/// trim the source range. Tap a clip to select it as the active clip.
/// Right-click for context menu with delete option.
struct TrimmableVideoClip: View {
    @Bindable var project: Project
    let height: CGFloat
    let thumbnailCount: Int

    @State private var isHovering: Bool = false

    // Per-interaction state: which clip is being dragged/trimmed (identified by UUID, not index).
    @State private var draggedClipID: UUID?
    @State private var activeHandle: TrimEdge?
    @State private var handleDragSnapshot: HandleSnapshot?
    @State private var bodyDragSnapshot: BodySnapshot?
    @State private var isDraggingBody: Bool = false

    @State private var hoveredHandle: TrimEdge?

    private enum TrimEdge { case start, end }

    private struct HandleSnapshot {
        let trimStart: Double
        let trimEnd: Double
        let timelineStart: Double
        let clipID: UUID
    }

    private struct BodySnapshot {
        let timelineStart: Double
        let trackIndex: Int
        let clipID: UUID
    }

    private let handleWidth: CGFloat = 10
    private let handleHitWidth: CGFloat = 22
    private let trimColor = Color(red: 1.0, green: 0.82, blue: 0.10)
    private let activeClipTint = Color(red: 1.0, green: 0.82, blue: 0.10)
    private let inactiveClipTint = Color(red: 0.5, green: 0.47, blue: 0.20)
    private let cornerRadius: CGFloat = 8
    private let trackSpacing: CGFloat = 2

    /// Total height of all tracks combined.
    private var totalTrackHeight: CGFloat {
        CGFloat(project.trackCount) * height + CGFloat(max(0, project.trackCount - 1)) * trackSpacing
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let timelineDuration = project.timelineDuration

            ZStack(alignment: .topLeading) {
                // Empty timeline background spanning all tracks.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.white.opacity(0.06), lineWidth: 1)
                    )
                    .frame(width: width, height: totalTrackHeight)

                // Track rows
                ForEach(0..<project.trackCount, id: \.self) { trackIndex in
                    trackRow(
                        trackIndex: trackIndex,
                        width: width,
                        timelineDuration: timelineDuration
                    )
                    .offset(y: CGFloat(trackIndex) * (height + trackSpacing))
                }
            }
            .frame(width: width, height: totalTrackHeight)
            .onHover { isHovering = $0 }
        }
        .frame(height: totalTrackHeight)
    }

    // MARK: - Single track row

    private func trackRow(trackIndex: Int, width: CGFloat, timelineDuration: Double) -> some View {
        let trackClipIndices = project.clips.enumerated()
            .filter { $0.element.trackIndex == trackIndex }
            .map { $0.offset }

        return ZStack(alignment: .topLeading) {
            // Track background
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                )
                .frame(width: width, height: height)
                .contextMenu {
                    if trackIndex > 0 {
                        if trackClipIndices.isEmpty {
                            Button {
                                project.removeTrack(at: trackIndex)
                            } label: {
                                Label("Remove empty track", systemImage: "minus.rectangle")
                            }
                        } else {
                            Button {
                                project.removeTrackAndMoveClips(at: trackIndex)
                            } label: {
                                Label("Remove track (move clips to T1)", systemImage: "arrow.down.to.line")
                            }
                        }
                    }
                }

            // Track number label
            if project.trackCount > 1 {
                let hasClipAtLeft = trackClipIndices.contains { idx in
                    project.clips[idx].timelineStart < 0.5 / max(timelineDuration, 1)
                }
                if !hasClipAtLeft {
                    Text("T\(trackIndex + 1)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .position(x: 14, y: height / 2)
                        .allowsHitTesting(false)
                }
            }

            // Clips on this track
            if timelineDuration > 0, project.videoURL != nil {
                ForEach(trackClipIndices, id: \.self) { clipIndex in
                    let clip = project.clips[clipIndex]
                    let clipStartX = CGFloat(clip.timelineStart / timelineDuration) * width
                    let clipEndX = CGFloat(clip.timelineEnd / timelineDuration) * width
                    let clipWidth = max(0, clipEndX - clipStartX)
                    let isActive = clip.id == project.activeClipID

                    clipBlock(
                        clip: clip,
                        clipWidth: clipWidth,
                        timelineWidth: width,
                        timelineDuration: timelineDuration
                    )
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

                    if isActive {
                        handle(
                            edge: .start, clip: clip,
                            x: clipStartX, timelineWidth: width, timelineDuration: timelineDuration
                        )
                        handle(
                            edge: .end, clip: clip,
                            x: clipEndX, timelineWidth: width, timelineDuration: timelineDuration
                        )
                    }

                    // Clip label
                    if clipWidth > 60 {
                        Text(String(format: "%.1fs", clip.timelineDuration))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(isActive ? .white.opacity(0.9) : .white.opacity(0.5))
                            .position(x: clipStartX + clipWidth / 2, y: height / 2)
                            .allowsHitTesting(false)
                    }
                }

                // Transition buttons between adjacent clips on this track
                if timelineDuration > 0, project.videoURL != nil {
                    let sortedTrackClips = trackClipIndices
                        .map { project.clips[$0] }
                        .sorted { $0.timelineStart < $1.timelineStart }

                    ForEach(0..<(sortedTrackClips.count > 0 ? sortedTrackClips.count - 1 : 0), id: \.self) { i in
                        let beforeClip = sortedTrackClips[i]
                        let afterClip = sortedTrackClips[i + 1]
                        let boundaryX = CGFloat(beforeClip.timelineEnd / timelineDuration) * width
                        let existingTransition = project.transition(between: beforeClip.id, and: afterClip.id)

                        TransitionButton(
                            boundaryX: boundaryX,
                            height: height,
                            transition: existingTransition,
                            isSelected: existingTransition?.id == project.selectedTransitionID,
                            onTap: {
                                let transition = project.addTransition(
                                    beforeID: beforeClip.id,
                                    afterID: afterClip.id,
                                    type: existingTransition?.type ?? .fade
                                )
                                project.selectedTransitionID = transition.id
                            }
                        )
                    }
                }

                // Time tooltip for the active handle
                if let edge = activeHandle,
                   let handleID = draggedClipID,
                   let draggedClip = project.clips.first(where: { $0.id == handleID }) {
                    let displayTime = edge == .start ? draggedClip.trimStartTime : draggedClip.trimEndTime
                    let xPos = edge == .start ? draggedClip.timelineStart : draggedClip.timelineEnd
                    let x = CGFloat(xPos / max(timelineDuration, 0.001)) * width
                    let yOffset = CGFloat(draggedClip.trackIndex) * (height + trackSpacing)
                    TimeTooltip(text: formatTimestamp(displayTime))
                        .offset(x: x - 28, y: yOffset - 26)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Clip block

    /// The clip block: thumbnails for the trim range + yellow border + body drag.
    private func clipBlock(clip: VideoClip, clipWidth: CGFloat, timelineWidth: CGFloat, timelineDuration: Double) -> some View {
        let sourceDuration = max(project.durationSeconds, 0.001)
        let clipDur = max(clip.clipDuration, 0.001)
        let virtualStripWidth = clipWidth * (sourceDuration / clipDur)
        let stripOffsetX = -CGFloat(clip.trimStartTime / sourceDuration) * virtualStripWidth
        let isActive = clip.id == project.activeClipID
        let isDragged = draggedClipID == clip.id

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

            // Active clip background tint
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(activeClipTint.opacity(0.08))
                    .frame(width: clipWidth, height: height)
            }

            // Main border
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    (activeHandle != nil && isDragged) || (isDraggingBody && isDragged)
                        ? (isActive ? activeClipTint : inactiveClipTint)
                        : (isActive ? activeClipTint : inactiveClipTint.opacity(0.4)),
                    lineWidth: (activeHandle != nil && isDragged) || (isDraggingBody && isDragged) ? 3 : (isActive ? 3 : 1)
                )
                .frame(width: clipWidth, height: height)
                .animation(.easeOut(duration: 0.15), value: activeHandle)
                .animation(.easeOut(duration: 0.15), value: isHovering)
                .animation(.easeOut(duration: 0.15), value: isDraggingBody)

            // Glow effect on active clip
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(activeClipTint, lineWidth: 2)
                    .blur(radius: 4)
                    .opacity(0.6)
                    .frame(width: clipWidth, height: height)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: clipWidth, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .local)
                .onChanged { v in
                    if bodyDragSnapshot == nil {
                        project.pushUndo()
                        bodyDragSnapshot = BodySnapshot(
                            timelineStart: clip.timelineStart,
                            trackIndex: clip.trackIndex,
                            clipID: clip.id
                        )
                        draggedClipID = clip.id
                        project.activeClipID = clip.id
                    }
                    isDraggingBody = true
                    guard let snapStart = bodyDragSnapshot?.timelineStart,
                          let originalTrack = bodyDragSnapshot?.trackIndex,
                          let clipID = bodyDragSnapshot?.clipID,
                          let ci = project.clips.firstIndex(where: { $0.id == clipID }),
                          timelineWidth > 0,
                          timelineDuration > 0 else { return }

                    // Horizontal: slide the clip
                    let dt = (Double(v.translation.width) / Double(timelineWidth)) * timelineDuration
                    var proposed = max(0, snapStart + dt)
                    let clipDur = project.clips[ci].timelineDuration
                    proposed = project.snapClipPosition(proposed, duration: clipDur, excludingClipAt: ci)
                    project.clips[ci].timelineStart = proposed

                    // Vertical: move to another track
                    let trackStep = height + trackSpacing
                    let trackDelta = Int(round(Double(v.translation.height) / Double(trackStep)))
                    let targetTrack = max(0, min(originalTrack + trackDelta, project.trackCount - 1))
                    project.clips[ci].trackIndex = targetTrack
                }
                .onEnded { v in
                    // Sync playhead now that drag is done.
                    if let clipID = bodyDragSnapshot?.clipID,
                       let ci = project.clips.firstIndex(where: { $0.id == clipID }) {
                        project.seek(to: project.clips[ci].timelineStart)
                    }
                    bodyDragSnapshot = nil
                    draggedClipID = nil
                    isDraggingBody = false
                }
        )
    }

    // MARK: - Trim handles

    private func handle(edge: TrimEdge, clip: VideoClip, x: CGFloat, timelineWidth: CGFloat, timelineDuration: Double) -> some View {
        let isActive = activeHandle == edge && draggedClipID == clip.id

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
                        draggedClipID = clip.id
                        project.activeClipID = clip.id
                    }
                    activeHandle = edge
                    guard let snap = handleDragSnapshot,
                          let ci = project.clips.firstIndex(where: { $0.id == snap.clipID }),
                          timelineWidth > 0,
                          timelineDuration > 0 else { return }
                    let dt = (Double(v.translation.width) / Double(timelineWidth)) * timelineDuration
                    switch edge {
                    case .start:
                        let proposedTrim = snap.trimStart + dt
                        let clampedTrim = max(0, min(proposedTrim, snap.trimEnd - VideoClip.minDuration))
                        let actualDelta = clampedTrim - snap.trimStart
                        project.clips[ci].trimStartTime = clampedTrim
                        project.clips[ci].timelineStart = max(0, snap.timelineStart + actualDelta)
                        if project.currentSeconds < project.clips[ci].timelineStart {
                            project.seek(to: project.clips[ci].timelineStart)
                        }
                    case .end:
                        let proposedTrim = snap.trimEnd + dt
                        let clamped = max(snap.trimStart + VideoClip.minDuration, min(proposedTrim, project.durationSeconds))
                        project.clips[ci].trimEndTime = clamped
                    }
                }
                .onEnded { v in
                    // Sync playhead now that handle drag is done.
                    if let clipID = handleDragSnapshot?.clipID,
                       let ci = project.clips.firstIndex(where: { $0.id == clipID }) {
                        switch edge {
                        case .start: project.seek(to: project.clips[ci].timelineStart)
                        case .end: project.seek(to: project.clips[ci].timelineEnd)
                        }
                    }
                    handleDragSnapshot = nil
                    activeHandle = nil
                    draggedClipID = nil
                    hoveredHandle = nil
                    applyCursor()
                }
        )
    }

    // MARK: - Cursor

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

// MARK: - Transition Button

/// Small circular button shown at the boundary between two clips.
/// Displays "+" when no transition exists, or the transition type icon when one is set.
struct TransitionButton: View {
    let boundaryX: CGFloat
    let height: CGFloat
    let transition: Transition?
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovering = false

    private let buttonSize: CGFloat = 28

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(
                        isSelected
                            ? (Color(hex: "#6466FA") ?? .indigo)
                            : Color.black.opacity(0.6)
                    )
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay(
                        Circle()
                            .stroke(
                                isSelected
                                    ? Color.white
                                    : (Color(hex: "#6466FA") ?? .indigo).opacity(0.8),
                                lineWidth: isSelected ? 2 : 1.5
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)

                if let transition = transition {
                    Image(systemName: transition.type.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(
                            isHovering
                                ? .white
                                : (Color(hex: "#6466FA") ?? .indigo)
                        )
                }
            }
            .scaleEffect(isHovering ? 1.15 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .position(x: boundaryX, y: height / 2)
        .onHover { isHovering = $0 }
        .help(transition.map { "Transition: \($0.type.displayName)" } ?? "Add transition")
    }
}
