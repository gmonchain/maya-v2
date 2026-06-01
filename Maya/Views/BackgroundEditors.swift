import SwiftUI

// MARK: - Solid section

struct SolidSection: View {
    @Bindable var project: Project
    @Binding var solidHex: String
    @Binding var customSolidColor: Color
    let currentSolidHex: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            solidGrid
            Divider()
            customSolidEditor
        }
    }

    private var solidGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 36), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(BackgroundOption.defaultSolids, id: \.self) { hex in
                Button {
                    solidHex = hex
                    customSolidColor = Color(hex: hex) ?? .black
                    project.background = .solid(hex: hex)
                } label: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: hex) ?? .black)
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(currentSolidHex == hex ? Color.accentColor : .black.opacity(0.1),
                                         lineWidth: currentSolidHex == hex ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customSolidEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ColorPicker("", selection: Binding(
                    get: { customSolidColor },
                    set: { newColor in
                        customSolidColor = newColor
                        let hex = newColor.hexString
                        solidHex = hex
                        project.background = .solid(hex: hex)
                    }
                ), supportsOpacity: false)
                .labelsHidden()

                Text(customSolidColor.hexString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
    }
}

// MARK: - Gradient section

struct GradientSection: View {
    @Bindable var project: Project
    @Binding var gradientSpec: GradientSpec
    @Binding var customGradientStart: Color
    @Binding var customGradientEnd: Color
    @Binding var customGradientAngle: Double
    let currentGradient: GradientSpec?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            gradientGrid
            Divider()
            customGradientEditor
        }
    }

    private var gradientGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 60), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(GradientSpec.presets.enumerated()), id: \.offset) { _, spec in
                Button {
                    gradientSpec = spec
                    customGradientStart = spec.startColor
                    customGradientEnd = spec.endColor
                    customGradientAngle = spec.angleDegrees
                    project.background = .gradient(spec)
                } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [spec.startColor, spec.endColor],
                                             startPoint: spec.startUnitPoint,
                                             endPoint: spec.endUnitPoint))
                        .frame(height: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(currentGradient == spec ? Color.accentColor : .black.opacity(0.1),
                                         lineWidth: currentGradient == spec ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customGradientEditor: some View {
        let customSpec = GradientSpec(
            startHex: customGradientStart.hexString,
            endHex: customGradientEnd.hexString,
            angleDegrees: customGradientAngle
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text("Custom").font(.caption.weight(.semibold)).foregroundStyle(.secondary)

            // Live preview
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    colors: [customGradientStart, customGradientEnd],
                    startPoint: customSpec.startUnitPoint,
                    endPoint: customSpec.endUnitPoint
                ))
                .frame(height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )

            HStack(spacing: 12) {
                BackgroundColorWell(label: "Start", binding: $customGradientStart)
                BackgroundColorWell(label: "End", binding: $customGradientEnd)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Angle").font(.caption.weight(.medium))
                    Spacer()
                    Text("\(Int(customGradientAngle.rounded()))°")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $customGradientAngle, in: 0...360, step: 1)
            }
        }
        .onChange(of: customGradientStart) { _, _ in pushCustomGradient() }
        .onChange(of: customGradientEnd) { _, _ in pushCustomGradient() }
        .onChange(of: customGradientAngle) { _, _ in pushCustomGradient() }
    }

    private func pushCustomGradient() {
        let spec = GradientSpec(
            startHex: customGradientStart.hexString,
            endHex: customGradientEnd.hexString,
            angleDegrees: customGradientAngle
        )
        gradientSpec = spec
        project.background = .gradient(spec)
    }
}

// MARK: - Color well helper

struct BackgroundColorWell: View {
    let label: String
    let binding: Binding<Color>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium))
            HStack(spacing: 8) {
                ColorPicker("", selection: binding, supportsOpacity: false)
                    .labelsHidden()
                Text(binding.wrappedValue.hexString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
