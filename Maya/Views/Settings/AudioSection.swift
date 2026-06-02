import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar section for managing audio tracks — import background music, voiceovers, SFX.
struct AudioSection: View {
    @Bindable var project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Audio")
                    .font(.headline)
                Spacer()
                if !project.audioClips.isEmpty {
                    Text("\(project.audioClips.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "#4A9EE0") ?? .blue))
                }
            }

            Button {
                openAudioPicker()
            } label: {
                Label("Add audio…", systemImage: "waveform.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            .disabled(project.videoURL == nil)
            .opacity(project.videoURL == nil ? 0.4 : 1.0)

            if project.audioClips.isEmpty {
                Text("No audio tracks added yet.\nImport music, voiceover, or SFX.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ForEach(project.audioClips) { clip in
                    AudioClipRow(project: project, clip: clip)
                }
            }
        }
    }

    private func openAudioPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .wav, .aiff, .appleScript, .audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls {
                project.addAudioClip(from: url)
            }
        }
    }
}

// MARK: - Individual audio clip row

private struct AudioClipRow: View {
    @Bindable var project: Project
    let clip: AudioClip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: clip.isMuted ? "speaker.slash.fill" : "waveform")
                    .font(.system(size: 10))
                    .foregroundStyle(clip.isMuted ? .secondary : Color(hex: "#4A9EE0") ?? .blue)
                    .frame(width: 14)

                Text(clip.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 2)

                // Duration label
                Text(String(format: "%.1fs", clip.clipDuration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                // Mute button
                Button {
                    project.toggleAudioClipMute(id: clip.id)
                } label: {
                    Image(systemName: clip.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help(clip.isMuted ? "Unmute" : "Mute")

                // Delete button
                Button {
                    project.deleteAudioClip(id: clip.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove audio clip")
            }

            // Volume slider
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.1")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)

                Slider(
                    value: Binding(
                        get: { clip.volume },
                        set: { project.setAudioClipVolume(id: clip.id, volume: $0) }
                    ),
                    in: 0...2,
                    step: 0.05
                )
                .controlSize(.small)

                Image(systemName: "speaker.wave.3")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)

                Text(String(format: "%.0f%%", clip.volume * 100))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            clip.id == project.activeAudioClipID
                                ? (Color(hex: "#4A9EE0") ?? .blue).opacity(0.5)
                                : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Audio UTType extensions

extension UTType {
    /// Common audio file types for the open panel.
    static let mp3 = UTType(filenameExtension: "mp3")!
    static let mpeg4Audio = UTType.mpeg4Audio
    static let wav = UTType(filenameExtension: "wav")!
    static let aiff = UTType(filenameExtension: "aiff")!
    static let appleScript = UTType(filenameExtension: "caf")! // Core Audio Format
}
