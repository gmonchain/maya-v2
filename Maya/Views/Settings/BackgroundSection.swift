import SwiftUI

struct BackgroundSection: View {
    @Bindable var project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $project.shadow.enabled) {
                Text("Shadow").font(.headline)
            }
            .toggleStyle(.switch)

            if project.shadow.enabled {
                HStack(spacing: 10) {
                    Text("Color").font(.caption.weight(.medium))
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: project.shadow.colorHex) ?? .black },
                        set: { project.shadow.colorHex = $0.hexString }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    Text(project.shadow.colorHex)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                sidebarSliderRow(
                    title: "Blur",
                    value: $project.shadow.radius,
                    range: PhoneShadow.radiusRange,
                    display: "\(Int(project.shadow.radius))pt"
                )

                sidebarSliderRow(
                    title: "Offset Y",
                    value: $project.shadow.offsetY,
                    range: PhoneShadow.offsetYRange,
                    display: "\(Int(project.shadow.offsetY))pt"
                )

                sidebarSliderRow(
                    title: "Offset X",
                    value: $project.shadow.offsetX,
                    range: PhoneShadow.offsetXRange,
                    display: "\(Int(project.shadow.offsetX))pt"
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Opacity").font(.caption.weight(.medium))
                        Spacer()
                        Text("\(Int(project.shadow.opacity * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $project.shadow.opacity, in: PhoneShadow.opacityRange)
                }
            }
        }
    }
}
