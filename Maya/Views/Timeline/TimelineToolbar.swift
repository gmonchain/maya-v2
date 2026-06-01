import AVFoundation
import SwiftUI

/// Compact transport bar above the tracks. Play/pause, current time, total/trimmed duration,
/// trim badge with reset, and a mute toggle. Kept slim so the timeline still has room.
struct TimelineToolbar: View {
    @Bindable var project: Project

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { project.togglePlayback() }) {
                Image(systemName: project.player?.timeControlStatus == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help("Play/Pause (space)")

            HStack(spacing: 4) {
                Text(formatTimestamp(project.currentSeconds))
                    .foregroundStyle(.white.opacity(0.95))
                Text("/")
                    .foregroundStyle(.white.opacity(0.5))
                Text(formatTimestamp(displayedDuration))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))

            splitButton
            addZoomButton

            if project.isTrimmed {
                clipsBadge
            }

            Spacer()

            HStack(spacing: 10) {
                shortcutHint("I", description: "Mark in")
                shortcutHint("O", description: "Mark out")
                shortcutHint("⌫", description: "Reset trim")
                shortcutHint("S", description: "Split")
            }
            .help("Keyboard shortcuts")

            overlapToggleButton

            Button(action: { project.toggleMute() }) {
                Image(systemName: project.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(project.isMuted ? "Unmute (m)" : "Mute (m)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var displayedDuration: Double {
        project.timelineDuration
    }

    // MARK: - Split button

    private var splitButton: some View {
        Button(action: {
            project.splitAtPlayhead()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "scissors")
                    .font(.system(size: 11, weight: .semibold))
                Text("Split")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 1.0, green: 0.82, blue: 0.10))
            )
        }
        .buttonStyle(.plain)
        .disabled(project.videoURL == nil || !canSplit)
        .opacity(project.videoURL == nil || !canSplit ? 0.4 : 1.0)
        .help("Split clip at playhead (S)")
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
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Add zoom")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: "#6466FA") ?? .accentColor)
            )
        }
        .buttonStyle(.plain)
        .disabled(project.videoURL == nil)
        .opacity(project.videoURL == nil ? 0.4 : 1.0)
        .help("Add a zoom at the playhead")
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
                .help("Reset to single clip")
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
            HStack(spacing: 4) {
                Image(systemName: project.allowClipOverlap ? "rectangle.stack" : "rectangle.dashed")
                    .font(.system(size: 11, weight: .semibold))
                Text(project.allowClipOverlap ? "Overlap" : "Snap")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(project.allowClipOverlap
                        ? (Color(hex: "#6466FA") ?? .accentColor)
                        : Color.white.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .help(project.allowClipOverlap ? "Overlap mode: clips can overlap (click to snap)" : "Snap mode: clips snap to edges (click to overlap)")
    }
}
