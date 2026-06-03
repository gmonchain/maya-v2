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

            if project.videoURL != nil && !project.isExporting {
                if project.canvasAspect != .appStorePortrait && project.canvasAspect != .appStoreLandscape {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Render size")
                            .font(.caption.weight(.medium))
                        HStack(spacing: 0) {
                            ForEach(ExportRenderSize.allCases) { size in
                                Button {
                                    project.exportRenderSize = size
                                } label: {
                                    Text(size.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 5)
                                        .background(
                                            project.exportRenderSize == size
                                                ? AnyShapeStyle(Color(hex: "#6466FA") ?? Color.accentColor)
                                                : AnyShapeStyle(Color.clear)
                                        )
                                        .foregroundStyle(project.exportRenderSize == size ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                )
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Quality")
                        .font(.caption.weight(.medium))
                    HStack(spacing: 0) {
                        ForEach(ExportQuality.allCases) { quality in
                            Button {
                                project.exportQuality = quality
                            } label: {
                                Text(quality.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(
                                        project.exportQuality == quality
                                            ? AnyShapeStyle(Color(hex: "#6466FA") ?? Color.accentColor)
                                            : AnyShapeStyle(Color.clear)
                                    )
                                    .foregroundStyle(project.exportQuality == quality ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )
                    )
                    Text(project.exportQuality.helpText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // FPS picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Frame rate")
                        .font(.caption.weight(.medium))
                    HStack(spacing: 0) {
                        ForEach(ExportFPS.allCases) { fps in
                            Button {
                                project.exportFPS = fps
                            } label: {
                                Text(fps.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(
                                        project.exportFPS == fps
                                            ? AnyShapeStyle(Color(hex: "#6466FA") ?? Color.accentColor)
                                            : AnyShapeStyle(Color.clear)
                                    )
                                    .foregroundStyle(project.exportFPS == fps ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )
                    )
                }

                // Codec picker (non-transparent only)
                if !project.background.isTransparent {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Video codec")
                            .font(.caption.weight(.medium))
                        HStack(spacing: 0) {
                            ForEach(ExportVideoCodec.allCases) { codec in
                                Button {
                                    project.exportVideoCodec = codec
                                } label: {
                                    Text(codec.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 5)
                                        .background(
                                            project.exportVideoCodec == codec
                                                ? AnyShapeStyle(Color(hex: "#6466FA") ?? Color.accentColor)
                                                : AnyShapeStyle(Color.clear)
                                        )
                                        .foregroundStyle(project.exportVideoCodec == codec ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                                )
                        )
                        Text(project.exportVideoCodec == .hevc ? "HEVC may not be accepted by App Store Connect for App Previews" : "H.264 is accepted by App Store Connect")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !project.appStoreIssues.isEmpty {
                appStoreIssueList
            }

            ExportCardButton(
                title: exportButtonTitle,
                subtitle: exportSubtitle,
                icon: exportButtonIcon,
                isEnabled: project.videoURL != nil && !project.isExporting && !project.hasAppStoreErrors,
                isExporting: project.isExporting,
                progress: project.exportProgress,
                action: onExport
            )

            if let fileURL = project.exportedFileURL,
               FileManager.default.fileExists(atPath: fileURL.path) {
                openFinderRow(fileURL: fileURL)

                if let info = project.exportedVideoInfo {
                    exportedVideoInfoCard(info)
                }
            }
        }
    }

    @ViewBuilder
    private func openFinderRow(fileURL: URL) -> some View {
        HStack(spacing: 6) {
            Button {
                NSWorkspace.shared.open(fileURL)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                    Text("Open")
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "#6466FA")?.opacity(0.12) ?? Color.accentColor.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "#6466FA")?.opacity(0.3) ?? Color.accentColor.opacity(0.3), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text("Finder")
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - App Store validation issues

    @ViewBuilder
    private var appStoreIssueList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App Preview Requirements")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(project.appStoreIssues) { issue in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: issue.severity == .error
                          ? "exclamationmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                        .frame(width: 16, alignment: .center)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(issue.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                        Text(issue.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((issue.severity == .error ? Color.red : Color.orange).opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke((issue.severity == .error ? Color.red : Color.orange).opacity(0.15), lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - Exported video info card

    @ViewBuilder
    private func exportedVideoInfoCard(_ info: ExportVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Apple Spec Check")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(info.specChecks.filter { $0.status == .pass }.count)/\(info.specChecks.count) OK")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(allPassed(info) ? .green : .orange)
            }
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(info.specChecks) { check in
                    specCheckRow(check)
                    if check.id != info.specChecks.last?.id {
                        Divider().opacity(0.3).padding(.leading, 68)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            )
        }
    }

    @ViewBuilder
    private func specCheckRow(_ check: SpecCheck) -> some View {
        HStack(spacing: 6) {
            Image(systemName: check.status == .pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(check.status == .pass ? .green : .red)
                .frame(width: 14)

            Text(check.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
                .lineLimit(1)

            Text(check.actual)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.primary)

            Spacer()

            Text(check.spec)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func allPassed(_ info: ExportVideoInfo) -> Bool {
        info.specChecks.allSatisfy { $0.status == .pass }
    }

    private var exportButtonTitle: String {
        project.background.isTransparent ? "Export transparent" : "Export video"
    }

    private var exportButtonIcon: String {
        project.background.isTransparent
            ? "square.and.arrow.down.on.square.fill"
            : "square.and.arrow.down.fill"
    }

    private var exportSubtitle: String {
        let size = project.canvasAspect.renderSize(forShortSide: project.exportRenderSize.shortSide)
        let dims = "\(Int(size.width))\u{00D7}\(Int(size.height))"
        let fpsLabel = project.exportFPS.displayName
        if project.background.isTransparent {
            return [dims, "HEVC + \u{03B1}", "MOV"].joined(separator: " \u{00B7} ")
        }
        let codecLabel = project.exportVideoCodec.displayName
        let ext = project.exportVideoCodec.fileExtension.uppercased()
        return [dims, codecLabel, ext, fpsLabel].joined(separator: " \u{00B7} ")
    }
}

// MARK: - Export card

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
