import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BackgroundPicker: View {
    @Bindable var project: Project

    @State private var selectedKind: Kind = .gradient
    @State private var solidHex: String = BackgroundOption.defaultSolids[0]
    @State private var gradientSpec: GradientSpec = GradientSpec.presets[0]
    @State private var imageURL: URL?

    // Custom solid editor
    @State private var customSolidColor: Color = Color(hex: "#6466FA") ?? .indigo

    // Custom gradient editor
    @State private var customGradientStart: Color = Color(hex: "#6466FA") ?? .indigo
    @State private var customGradientEnd: Color = Color(hex: "#EC4899") ?? .pink
    @State private var customGradientAngle: Double = 135

    enum Kind: String, CaseIterable, Identifiable {
        case none, solid, gradient, image, videoBlur
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: "None"
            case .solid: "Solid"
            case .gradient: "Gradient"
            case .image: "Image"
            case .videoBlur: "Blur"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background")
                .font(.headline)

            Picker("", selection: $selectedKind) {
                ForEach(Kind.allCases) { k in
                    Text(k.label).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: selectedKind) { _, _ in applySelection() }
            .onAppear {
                syncKindFromProject()
                seedCustomEditorsFromProject()
            }
            .onChange(of: project.background) { _, _ in syncKindFromProject() }

            Group {
                switch selectedKind {
                case .none:
                    transparencyInfo
                case .solid:
                    SolidSection(
                        project: project,
                        solidHex: $solidHex,
                        customSolidColor: $customSolidColor,
                        currentSolidHex: currentSolidHex
                    )
                case .gradient:
                    GradientSection(
                        project: project,
                        gradientSpec: $gradientSpec,
                        customGradientStart: $customGradientStart,
                        customGradientEnd: $customGradientEnd,
                        customGradientAngle: $customGradientAngle,
                        currentGradient: currentGradient
                    )
                case .image:
                    imagePicker
                case .videoBlur:
                    Text("Blurred frame of your video, Keynote-style.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if selectedKind == .solid || selectedKind == .gradient || selectedKind == .image {
                blurSlider
            }
        }
    }

    // MARK: - Transparency

    private var transparencyInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "#6466FA") ?? .accentColor)
                Text("Transparent")
                    .font(.callout.weight(.semibold))
            }
            Text("Export will be a .mov with HEVC + alpha. The framed phone shows over arbitrary content in any AVPlayer/AVKit consumer (your tutorial app, Final Cut, Motion).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Image

    private var imagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = imageURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            Button("Choose image…") { chooseImage() }
        }
    }

    private var blurSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Blur").font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(project.backgroundBlurRadius.rounded()))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: $project.backgroundBlurRadius,
                in: 0...40,
                step: 1
            )
        }
    }

    // MARK: - Sync helpers

    private var currentSolidHex: String? {
        if case .solid(let hex) = project.background { return hex }
        return nil
    }

    private var currentGradient: GradientSpec? {
        if case .gradient(let s) = project.background { return s }
        return nil
    }

    private func syncKindFromProject() {
        switch project.background {
        case .none: selectedKind = .none
        case .solid: selectedKind = .solid
        case .gradient: selectedKind = .gradient
        case .image: selectedKind = .image
        case .videoBlur: selectedKind = .videoBlur
        }
    }

    /// Seed the ColorPicker / gradient editor controls from whatever is currently
    /// active on the project, so the user picks up where they left off.
    private func seedCustomEditorsFromProject() {
        if case .solid(let hex) = project.background, let c = Color(hex: hex) {
            customSolidColor = c
            solidHex = hex
        }
        if case .gradient(let spec) = project.background {
            customGradientStart = spec.startColor
            customGradientEnd = spec.endColor
            customGradientAngle = spec.angleDegrees
            gradientSpec = spec
        }
    }

    private func applySelection() {
        switch selectedKind {
        case .none:
            project.background = .none
            project.backgroundBlurRadius = 0
        case .solid:
            project.background = .solid(hex: solidHex)
        case .gradient:
            project.background = .gradient(gradientSpec)
        case .image:
            if let url = imageURL {
                project.background = .image(url)
            } else {
                project.background = .solid(hex: solidHex)
            }
        case .videoBlur:
            project.background = .videoBlur
            project.backgroundBlurRadius = 0
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            imageURL = url
            project.background = .image(url)
        }
    }
}
