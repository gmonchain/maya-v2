import AVFoundation
import SwiftUI

/// Displays audio clips as colored bars in the timeline.
/// Each audio clip is shown as a resizable bar with trim handles,
/// draggable body, and a label.
struct AudioTrackView: View {
    @Bindable var project: Project
    let height: CGFloat

    @State private var draggedClipID: UUID?
    @State private var bodyDragSnapshot: AudioBodySnapshot?
    @State private var isDraggingBody = false
    @State private var isHovering = false

    private struct AudioBodySnapshot {
        let timelineStart: Double
        let clipID: UUID
    }

    private let handleWidth: CGFloat = 8
    @State private var activeHandle: TrimEdge?
    @State private var handleDragSnapshot: AudioHandleSnapshot?
    @State private var hoveredHandle: TrimEdge?

    private struct AudioHandleSnapshot {
        let trimStart: Double
        let trimEnd: Double
        let timelineStart: Double
        let clipID: UUID
    }

    private enum TrimEdge { case start, end }

    private let cornerRadius: CGFloat = 6
    private let clipColor = Color(red: 0.30, green: 0.65, blue: 1.0) // Blue tint for audio
    private let clipColorActive = Color(red: 0.40, green: 0.75, blue: 1.0)

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let duration = project.timelineDuration

            ZStack(alignment: .topLeading) {
                // Track background
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.white.opacity(0.06), lineWidth: 1)
                    )
                    .frame(width: width, height: height)

                // Audio clips
                if duration > 0 {
                    ForEach(project.audioClips) { clip in
                        let clipStartX = CGFloat(clip.timelineStart / duration) * width
                        let clipEndX = CGFloat(clip.timelineEnd / duration) * width
                        let clipWidth = max(0, clipEndX - clipStartX)
                        let isActive = clip.id == project.activeAudioClipID

                        audioClipBar(
                            clip: clip,
                            clipWidth: clipWidth,
                            timelineWidth: width,
                            timelineDuration: duration
                        )
                        .frame(width: clipWidth, height: height)
                        .offset(x: clipStartX)
                        .onTapGesture {
                            project.activeAudioClipID = clip.id
                        }
                        .contextMenu {
                            Button {
                                project.activeAudioClipID = clip.id
                                project.deleteAudioClip(id: clip.id)
                            } label: {
                                Label("Delete audio clip", systemImage: "trash")
                            }

                            Divider()

                            Button {
                                project.toggleAudioClipMute(id: clip.id)
                            } label: {
                                Label(
                                    clip.isMuted ? "Unmute" : "Mute",
                                    systemImage: clip.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                                )
                            }
                        }

                        // Trim handles
                        audioHandle(
                            edge: .start, clip: clip,
                            x: clipStartX, timelineWidth: width, timelineDuration: duration
                        )
                        audioHandle(
                            edge: .end, clip: clip,
                            x: clipEndX, timelineWidth: width, timelineDuration: duration
                        )

                        // Clip label
                        if clipWidth > 50 {
                            HStack(spacing: 3) {
                                Image(systemName: clip.isMuted ? "speaker.slash.fill" : "waveform")
                                    .font(.system(size: 8))
                                Text(clip.displayName)
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isActive ? .white.opacity(0.95) : .white.opacity(0.6))
                            .position(x: clipStartX + clipWidth / 2, y: height / 2)
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
            .frame(width: width, height: height)
            .onHover { isHovering = $0 }
        }
        .frame(height: height)
    }

    // MARK: - Audio clip bar

    private func audioClipBar(
        clip: AudioClip,
        clipWidth: CGFloat,
        timelineWidth: CGFloat,
        timelineDuration: Double
    ) -> some View {
        let isActive = clip.id == project.activeAudioClipID
        let isDragged = draggedClipID == clip.id

        return ZStack {
            // Fill
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    clip.isMuted
                        ? Color.gray.opacity(0.25)
                        : (isActive ? clipColorActive : clipColor).opacity(0.55)
                )

            // Waveform-like pattern (simple repeating lines for visual texture)
            if !clip.isMuted {
                GeometryReader { geo in
                    let barCount = max(1, Int(geo.size.width / 4))
                    ForEach(0..<barCount, id: \.self) { i in
                        let x = CGFloat(i) * (geo.size.width / CGFloat(barCount))
                        let h = CGFloat.random(in: 0.3...1.0) * geo.size.height * 0.7
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 2, height: h)
                            .position(x: x + 1, y: geo.size.height / 2)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }

            // Border
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    (activeHandle != nil && isDragged) || (isDraggingBody && isDragged)
                        ? clipColorActive
                        : (isActive ? clipColorActive : clipColor.opacity(0.6)),
                    lineWidth: (activeHandle != nil && isDragged) || (isDraggingBody && isDragged) ? 2.5 : (isActive ? 2 : 1)
                )
                .frame(width: clipWidth, height: height)

            // Glow on active
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(clipColorActive, lineWidth: 2)
                    .blur(radius: 4)
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }

            // Volume indicator (small bar at bottom)
            if clip.volume < 1.0 && !clip.isMuted {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.4))
                            .frame(width: geo.size.width * CGFloat(clip.volume), height: 2)
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 3)
                }
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
                        bodyDragSnapshot = AudioBodySnapshot(
                            timelineStart: clip.timelineStart,
                            clipID: clip.id
                        )
                        draggedClipID = clip.id
                        project.activeAudioClipID = clip.id
                    }
                    isDraggingBody = true
                    guard let snapStart = bodyDragSnapshot?.timelineStart,
                          let clipID = bodyDragSnapshot?.clipID,
                          let ci = project.audioClips.firstIndex(where: { $0.id == clipID }),
                          timelineWidth > 0,
                          timelineDuration > 0 else { return }

                    let dt = (Double(v.translation.width) / Double(timelineWidth)) * timelineDuration
                    let proposed = max(0, snapStart + dt)
                    project.audioClips[ci].timelineStart = proposed
                }
                .onEnded { _ in
                    bodyDragSnapshot = nil
                    draggedClipID = nil
                    isDraggingBody = false
                }
        )
    }

    // MARK: - Trim handles

    private func audioHandle(
        edge: TrimEdge,
        clip: AudioClip,
        x: CGFloat,
        timelineWidth: CGFloat,
        timelineDuration: Double
    ) -> some View {
        let isActive = activeHandle == edge && draggedClipID == clip.id

        return ZStack {
            Color.white.opacity(0.001)
                .frame(width: 18, height: height)

            RoundedRectangle(cornerRadius: 2)
                .fill(isActive ? clipColorActive : clipColor.opacity(0.7))
                .frame(width: handleWidth, height: height + 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 1.5, height: height * 0.35)
                )
                .shadow(color: .black.opacity(0.3), radius: isActive ? 4 : 1, y: 1)
                .scaleEffect(isActive ? 1.06 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isActive)
        }
        .contentShape(Rectangle())
        .position(x: x, y: height / 2)
        .onHover { hovered in
            if hovered { hoveredHandle = edge } else if hoveredHandle == edge { hoveredHandle = nil }
            applyCursor()
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { v in
                    if handleDragSnapshot == nil {
                        project.pushUndo()
                        handleDragSnapshot = AudioHandleSnapshot(
                            trimStart: clip.trimStartTime,
                            trimEnd: clip.trimEndTime,
                            timelineStart: clip.timelineStart,
                            clipID: clip.id
                        )
                        draggedClipID = clip.id
                        project.activeAudioClipID = clip.id
                    }
                    activeHandle = edge
                    guard let snap = handleDragSnapshot,
                          let ci = project.audioClips.firstIndex(where: { $0.id == snap.clipID }),
                          timelineWidth > 0,
                          timelineDuration > 0 else { return }
                    let dt = (Double(v.translation.width) / Double(timelineWidth)) * timelineDuration
                    switch edge {
                    case .start:
                        let proposedTrim = snap.trimStart + dt
                        let clampedTrim = max(0, min(proposedTrim, snap.trimEnd - AudioClip.minDuration))
                        let actualDelta = clampedTrim - snap.trimStart
                        project.audioClips[ci].trimStartTime = clampedTrim
                        project.audioClips[ci].timelineStart = max(0, snap.timelineStart + actualDelta)
                    case .end:
                        let proposedTrim = snap.trimEnd + dt
                        let audioDuration = project.audioClipTotalDuration(clipID: clip.id)
                        let clamped = max(snap.trimStart + AudioClip.minDuration, min(proposedTrim, audioDuration))
                        project.audioClips[ci].trimEndTime = clamped
                    }
                }
                .onEnded { _ in
                    handleDragSnapshot = nil
                    activeHandle = nil
                    draggedClipID = nil
                    hoveredHandle = nil
                    applyCursor()
                }
        )
    }

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
