import AVFoundation
import SwiftUI

extension Notification.Name {
    static let importVideo = Notification.Name("importVideo")
}

/// Compact transport bar above the tracks. Play/pause, current time, total/trimmed duration,
/// trim badge with reset, and a mute toggle. Kept slim so the timeline still has room.
struct TimelineToolbar: View {
    @Bindable var project: Project

    var body: some View {
        HStack(spacing: 16) {
            // Group 1: Transport & Time
            HStack(spacing: 8) {
                openVideoButton
                
                playPauseButton
                
                timeDisplay
            }
            
            Divider()
                .frame(height: 16)
                .overlay(Color.white.opacity(0.2))
            
            // Group 2: Editing Tools
            HStack(spacing: 6) {
                splitButton
                addZoomButton
            }
            
            Divider()
                .frame(height: 16)
                .overlay(Color.white.opacity(0.2))
            
            // Group 3: Add/Import
            HStack(spacing: 6) {
                addTrackButton
                addAudioButton
            }
            
            if project.isTrimmed {
                clipsBadge
            }
            
            Spacer()
            
            // Group 4: Settings & Controls
            HStack(spacing: 10) {
                playbackSpeedControl
                overlapToggleButton
                muteButton
                moreMenuButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    
    // MARK: - Component Views
    
    private var playPauseButton: some View {
        Button(action: { project.togglePlayback() }) {
            Image(systemName: project.player?.timeControlStatus == .playing ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .hoverLabel("Play/Pause (space)")
    }
    
    private var timeDisplay: some View {
        HStack(spacing: 4) {
            Text(formatTimestamp(project.currentSeconds))
                .foregroundStyle(.white.opacity(0.95))
            Text("/")
                .foregroundStyle(.white.opacity(0.4))
            Text(formatTimestamp(displayedDuration))
                .foregroundStyle(.white.opacity(0.6))
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }
    
    private var muteButton: some View {
        Button(action: { project.toggleMute() }) {
            Image(systemName: project.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(project.isMuted ? .white.opacity(0.5) : .white.opacity(0.85))
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .hoverLabel(project.isMuted ? "Unmute (m)" : "Mute (m)")
    }
    
    private var moreMenuButton: some View {
        Menu {
            Section("Keyboard Shortcuts") {
                Label("Play/Pause: Space", systemImage: "play.fill")
                Label("Mark In: I", systemImage: "inlet.left")
                Label("Mark Out: O", systemImage: "inlet.right")
                Label("Reset Trim: ⌥⌫", systemImage: "arrow.counterclockwise")
                Label("Split: S", systemImage: "scissors")
                Label("Scrub ←/→: Arrow keys", systemImage: "arrow.left.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.12))
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverLabel("More")
    }

    private var displayedDuration: Double {
        project.timelineDuration
    }

    // MARK: - Open Video button

    private var openVideoButton: some View {
        Button(action: openVideoPicker) {
            Image(systemName: "film.stack")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "#6466FA") ?? .accentColor)
                )
        }
        .buttonStyle(.plain)
        .hoverLabel("Open Video")
    }

    private func openVideoPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie, .video]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            NotificationCenter.default.post(
                name: .importVideo,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }

    // MARK: - Playback Speed

    private static let speedOptions: [(label: String, value: Double)] = [
        ("0.5x", 0.5),
        ("1x", 1.0),
        ("1.5x", 1.5),
        ("2x", 2.0),
    ]

    private var playbackSpeedControl: some View {
        Menu {
            ForEach(Self.speedOptions, id: \.label) { option in
                Button {
                    project.playbackSpeed = option.value
                } label: {
                    HStack {
                        Text(option.label)
                        if project.playbackSpeed == option.value {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(String(format: "%.1fx", project.playbackSpeed))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: 48, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.12))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverLabel("Speed")
    }

    // MARK: - Split button

    private var splitButton: some View {
        Button(action: {
            project.splitAtPlayhead()
        }) {
            Image(systemName: "scissors")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 1.0, green: 0.82, blue: 0.10))
                )
        }
        .buttonStyle(.plain)
        .disabled(project.videoURL == nil || !canSplit)
        .opacity(project.videoURL == nil || !canSplit ? 0.4 : 1.0)
        .hoverLabel("Split (S)")
    }

    /// The playhead must be inside a clip (not at its very edges) to allow splitting.
    private var canSplit: Bool {
        guard let clip = project.activeClip else { return false }
        return project.currentSeconds > clip.timelineStart + 0.05
            && project.currentSeconds < clip.timelineEnd - 0.05
    }

    // MARK: - Add zoom button

    /// Adds a zoom segment at the current playhead. If the playhead is already inside an
    /// existing segment, selects it instead of stacking a new one on top.
    private var addZoomButton: some View {
        Button(action: addZoomAtPlayhead) {
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "#6466FA") ?? .accentColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(project.videoURL == nil)
        .opacity(project.videoURL == nil ? 0.4 : 1.0)
        .hoverLabel("Add Zoom")
    }

    private func addZoomAtPlayhead() {
        guard project.videoURL != nil else { return }
        let t = project.currentSeconds
        if let existing = project.segment(containing: t) {
            project.selectedAnimationID = existing.id
            return
        }
        _ = project.addZoomSegment(at: t)
    }

    // MARK: - Add track button

    private var addTrackButton: some View {
        Button(action: { project.addTrack() }) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "#3AA655") ?? Color.green)
                )
        }
        .buttonStyle(.plain)
        .disabled(project.videoURL == nil)
        .opacity(project.videoURL == nil ? 0.4 : 1.0)
        .hoverLabel("Add Track")
    }

    // MARK: - Add audio button

    private var addAudioButton: some View {
        Button(action: { openAudioPicker() }) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "#4A9EE0") ?? Color.blue)
                )
        }
        .buttonStyle(.plain)
        .disabled(project.videoURL == nil)
        .opacity(project.videoURL == nil ? 0.4 : 1.0)
        .hoverLabel("Add Audio")
    }

    private func openAudioPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff, .appleScript, .audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            project.addAudioClip(from: url)
        }
    }

    // MARK: - Clips badge

    private var clipsBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "film")
            if project.clips.count > 1 {
                Text("\(project.clips.count) clips")
            } else {
                let trimmed = max(0, project.durationSeconds - project.clipDuration)
                if trimmed > 0.01 {
                    Text(String(format: "%.2fs trimmed", trimmed))
                } else {
                    Text("1 clip")
                }
            }
            if project.clips.count > 1 {
                Button {
                    // Reset all clips back to one
                    guard let firstClip = project.clips.first else { return }
                    project.pushUndo()
                    let dur = project.durationSeconds
                    project.clips = [VideoClip(
                        id: UUID(),
                        trimStartTime: 0,
                        trimEndTime: dur,
                        timelineStart: 0
                    )]
                    project.activeClipID = project.clips.first?.id
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .hoverLabel("Reset Clips")
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.black.opacity(0.85))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color(red: 1.0, green: 0.82, blue: 0.10))
        )
    }

    private func shortcutHint(_ key: String, description: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .frame(minWidth: 14)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Overlap toggle

    private var overlapToggleButton: some View {
        Button(action: {
            project.allowClipOverlap.toggle()
        }) {
            Image(systemName: project.allowClipOverlap ? "rectangle.stack.fill" : "rectangle.dashed")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(project.allowClipOverlap ? .white : .white.opacity(0.7))
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(project.allowClipOverlap
                            ? (Color(hex: "#6466FA") ?? .accentColor)
                            : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .hoverLabel(project.allowClipOverlap ? "Overlap Mode" : "Snap Mode")
    }
}

// MARK: - Hover Label Modifier

private struct HoverLabelModifier: ViewModifier {
    let text: String
    @State private var isHovering = false
    
    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
            }
            .overlay(alignment: .top) {
                if isHovering {
                    Text(text)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.9))
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        )
                        .fixedSize()
                        .offset(y: -28)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.15), value: isHovering)
                }
            }
    }
}

extension View {
    func hoverLabel(_ text: String) -> some View {
        modifier(HoverLabelModifier(text: text))
    }
}
