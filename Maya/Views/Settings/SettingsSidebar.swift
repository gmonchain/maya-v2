import SwiftUI

// MARK: - Shared sidebar helper

func sidebarSliderRow(title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, display: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack {
            Text(title).font(.caption.weight(.medium))
            Spacer()
            Text(display)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        Slider(value: value, in: range)
    }
}

// MARK: - Settings Sidebar

struct SettingsSidebar: View {
    @Bindable var project: Project
    let onExport: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RecordingSection(project: project)
                Divider()
                DeviceSection(project: project)
                Divider()
                transformSection
                Divider()
                BackgroundPicker(project: project)
                Divider()
                BackgroundSection(project: project)
                Divider()
                exportSection
                if let error = project.lastExportError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 12)
            }
            .padding(16)
        }
        .frame(minWidth: 280)
    }

    // MARK: - Transform

    private var transformSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Size & Position")
                .font(.headline)

            HStack {
                Image(systemName: "minus.magnifyingglass")
                Slider(value: $project.scale, in: 0.3...1.6)
                Image(systemName: "plus.magnifyingglass")
            }
            Text(String(format: "Scale: %.0f%%", project.scale * 100))
                .font(.caption)
                .foregroundStyle(.secondary)

            sidebarSliderRow(
                title: "Offset X",
                value: Binding(
                    get: { project.offset.width },
                    set: { project.offset.width = $0 }
                ),
                range: -0.5...0.5,
                display: String(format: "%.3f", project.offset.width)
            )

            sidebarSliderRow(
                title: "Offset Y",
                value: Binding(
                    get: { project.offset.height },
                    set: { project.offset.height = $0 }
                ),
                range: -0.5...0.5,
                display: String(format: "%.3f", project.offset.height)
            )

            Button("Reset position") {
                project.offset = .zero
                project.scale = 0.85
            }
            .controlSize(.small)
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export")
                .font(.headline)

            ExportCardButton(
                title: exportButtonTitle,
                subtitle: exportSubtitle,
                icon: exportButtonIcon,
                isEnabled: project.videoURL != nil && !project.isExporting,
                isExporting: project.isExporting,
                progress: project.exportProgress,
                action: onExport
            )
        }
    }

    private var exportButtonTitle: String {
        project.background.isTransparent ? "Export transparent" : "Export video"
    }

    private var exportButtonIcon: String {
        project.background.isTransparent
            ? "square.and.arrow.down.on.square.fill"
            : "square.and.arrow.down.fill"
    }

    /// One-line subtitle shown under the export title. Pieces are joined with
    /// middle dots so it stays readable without breaking onto two rows.
    private var exportSubtitle: String {
        let size = project.canvasAspect.renderSize
        let dims = "\(Int(size.width))×\(Int(size.height))"
        let pieces: [String] = project.background.isTransparent
            ? [dims, "HEVC + α", "MOV"]
            : [dims, "H.264", "MP4"]
        return pieces.joined(separator: " · ")
    }
}

// MARK: - Export card

/// Full-bleed export button styled as a tinted card. Doubles as the progress
/// surface while the export is running so the layout doesn't reflow.
private struct ExportCardButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isEnabled: Bool
    let isExporting: Bool
    let progress: Double
    let action: () -> Void

    @State private var isHovering = false

    private var accent: Color { Color(hex: "#6466FA") ?? .accentColor }
    private var accentDark: Color { Color(hex: "#4F46E5") ?? accent }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(isEnabled ? 1.0 : 0.45),
                                accentDark.opacity(isEnabled ? 1.0 : 0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(isEnabled ? 0.22 : 0.08), lineWidth: 1)
                    )
                    .shadow(
                        color: accent.opacity(isEnabled && isHovering ? 0.45 : 0.25),
                        radius: isHovering ? 14 : 8,
                        x: 0,
                        y: isHovering ? 6 : 4
                    )

                if isExporting {
                    progressContent
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                } else {
                    idleContent
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .animation(.easeOut(duration: 0.2), value: isExporting)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovering = hovering && isEnabled
        }
        .help(isEnabled ? "Render and save the video" : "Load a video to enable export")
    }

    private var idleContent: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .offset(x: isHovering ? 3 : 0)
        }
    }

    private var progressContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(.white)
                Text("Exporting")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(String(format: "%.0f%%", max(0, min(1, progress)) * 100))
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(4, g.size.width * CGFloat(max(0, min(1, progress)))))
                }
            }
            .frame(height: 6)
        }
    }
}
