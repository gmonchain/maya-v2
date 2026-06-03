import SwiftUI

/// Right-side detail panel for a selected audio clip.
/// Provides volume, fade in/out, mute, and clip info controls.
struct AudioEditorPanel: View {
    @Bindable var project: Project
    let clipID: UUID
    let onDismiss: () -> Void

    @State private var hasPushedUndo: Bool = false

    private var clip: AudioClip? {
        project.audioClips.first { $0.id == clipID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                if let binding = clipBinding() {
                    VStack(alignment: .leading, spacing: 20) {
                        clipInfoSection
                        Divider()
                        volumeSection(binding: binding)
                        Divider()
                        fadeSection(binding: binding)
                        Divider()
                        actionsSection
                    }
                    .padding(16)
                } else {
                    Text("Audio clip not found.")
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "#4A9EE0") ?? .blue)
            Text("Audio clip")
                .font(.headline)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Close panel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Clip info

    private var clipInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Clip info")

            HStack(spacing: 10) {
                Image(systemName: clip?.isMuted == true ? "speaker.slash.fill" : "waveform")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(clip?.isMuted == true ? .secondary : Color(hex: "#4A9EE0") ?? .blue)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(clip?.displayName ?? "—")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let c = clip {
                        Text(String(format: "%.1fs  •  %.0f%%", c.clipDuration, c.volume * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Volume

    private func volumeSection(binding: Binding<AudioClip>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Volume")
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.1")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Slider(
                    value: Binding(
                        get: { binding.wrappedValue.volume },
                        set: { newValue in
                            pushUndoIfNeeded()
                            binding.wrappedValue.volume = newValue
                            project.setAudioClipVolume(id: clipID, volume: newValue)
                        }
                    ),
                    in: 0...2,
                    step: 0.05
                )

                Image(systemName: "speaker.wave.3")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Text(String(format: "%.0f%%", binding.wrappedValue.volume * 100))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    // MARK: - Fade in/out

    private func fadeSection(binding: Binding<AudioClip>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Fade")

            // Fade In
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Toggle(isOn: Binding(
                        get: { binding.wrappedValue.fadeInEnabled },
                        set: { newValue in
                            pushUndoIfNeeded()
                            binding.wrappedValue.fadeInEnabled = newValue
                        }
                    )) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrowtriangle.right.and.line.vertical")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Fade in")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Spacer()

                    if binding.wrappedValue.fadeInEnabled {
                        Text(String(format: "%.2fs", binding.wrappedValue.fadeInDuration))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if binding.wrappedValue.fadeInEnabled {
                    Slider(
                        value: Binding(
                            get: { binding.wrappedValue.fadeInDuration },
                            set: { newValue in
                                let maxDur = binding.wrappedValue.clipDuration / 2
                                binding.wrappedValue.fadeInDuration = max(0.05, min(newValue, maxDur))
                            }
                        ),
                        in: 0.05...max(0.05, binding.wrappedValue.clipDuration / 2),
                        step: 0.05
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Fade Out
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Toggle(isOn: Binding(
                        get: { binding.wrappedValue.fadeOutEnabled },
                        set: { newValue in
                            pushUndoIfNeeded()
                            binding.wrappedValue.fadeOutEnabled = newValue
                        }
                    )) {
                        HStack(spacing: 6) {
                            Image(systemName: "line.vertical.and.arrowtriangle.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Fade out")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    Spacer()

                    if binding.wrappedValue.fadeOutEnabled {
                        Text(String(format: "%.2fs", binding.wrappedValue.fadeOutDuration))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if binding.wrappedValue.fadeOutEnabled {
                    Slider(
                        value: Binding(
                            get: { binding.wrappedValue.fadeOutDuration },
                            set: { newValue in
                                let maxDur = binding.wrappedValue.clipDuration / 2
                                binding.wrappedValue.fadeOutDuration = max(0.05, min(newValue, maxDur))
                            }
                        ),
                        in: 0.05...max(0.05, binding.wrappedValue.clipDuration / 2),
                        step: 0.05
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Visual fade preview
            if binding.wrappedValue.fadeInEnabled || binding.wrappedValue.fadeOutEnabled {
                fadePreview(binding: binding)
            }
        }
    }

    /// Small visual representation of the fade curve
    private func fadePreview(binding: Binding<AudioClip>) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let dur = binding.wrappedValue.clipDuration
            let fi = binding.wrappedValue.fadeInEnabled ? min(binding.wrappedValue.fadeInDuration, dur / 2) : 0
            let fo = binding.wrappedValue.fadeOutEnabled ? min(binding.wrappedValue.fadeOutDuration, dur / 2) : 0

            Path { path in
                path.move(to: CGPoint(x: 0, y: h))

                if fi > 0 {
                    let fiEndX = CGFloat(fi / dur) * w
                    path.addLine(to: CGPoint(x: fiEndX, y: 0))
                } else {
                    path.addLine(to: CGPoint(x: 0, y: 0))
                }

                let steadyStartX = CGFloat(fi / dur) * w
                let steadyEndX = CGFloat((dur - fo) / dur) * w
                path.addLine(to: CGPoint(x: steadyEndX, y: 0))

                if fo > 0 {
                    let foStartX = CGFloat((dur - fo) / dur) * w
                    path.addLine(to: CGPoint(x: w, y: h))
                } else {
                    path.addLine(to: CGPoint(x: w, y: 0))
                }
            }
            .stroke(
                LinearGradient(
                    colors: [Color(hex: "#4A9EE0") ?? .blue, Color(hex: "#6466FA") ?? .indigo],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
            .frame(height: h)
        }
        .frame(height: 32)
        .padding(.top, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.08))
        )
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack {
            // Mute toggle
            Button {
                pushUndoIfNeeded()
                project.toggleAudioClipMute(id: clipID)
            } label: {
                Label(
                    clip?.isMuted == true ? "Unmute" : "Mute",
                    systemImage: clip?.isMuted == true ? "speaker.wave.2.fill" : "speaker.slash.fill"
                )
            }
            .controlSize(.regular)

            Spacer()

            Button(role: .destructive) {
                project.deleteAudioClip(id: clipID)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .controlSize(.regular)
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func pushUndoIfNeeded() {
        if !hasPushedUndo {
            project.pushUndo()
            hasPushedUndo = true
        }
    }

    private func clipBinding() -> Binding<AudioClip>? {
        guard let _ = project.audioClips.firstIndex(where: { $0.id == clipID }) else { return nil }
        return Binding(
            get: {
                project.audioClips.first(where: { $0.id == self.clipID })
                    ?? AudioClip(id: UUID(), sourceURL: URL(fileURLWithPath: ""), displayName: "", trimStartTime: 0, trimEndTime: 0, timelineStart: 0, sourceDuration: 0)
            },
            set: { newValue in
                guard let idx = project.audioClips.firstIndex(where: { $0.id == self.clipID }) else { return }
                project.audioClips[idx] = newValue
                // Sync volume to preview player
                project.setAudioClipVolume(id: self.clipID, volume: newValue.volume)
            }
        )
    }
}
