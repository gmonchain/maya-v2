import SwiftUI

struct DeviceSection: View {
    @Bindable var project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Device").font(.headline)
                Spacer()
                if project.deviceModel.kind == .physical {
                    Text(project.deviceColor.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            // Model picker — wraps to multiple rows so all entries fit comfortably.
            let columns = [GridItem(.adaptive(minimum: 78), spacing: 6)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(DeviceModel.all) { model in
                    DeviceModelChip(
                        label: model.shortName,
                        symbol: model.kind == .physical ? nil : model.symbol,
                        isSelected: project.deviceModelID == model.id
                    ) {
                        project.selectDeviceModel(model)
                    }
                }
            }

            // Color swatches only apply to physical models.
            if project.deviceModel.kind == .physical {
                HStack(spacing: 10) {
                    ForEach(project.deviceModel.colors) { color in
                        DeviceColorSwatch(
                            color: color,
                            isSelected: project.deviceColorID == color.id
                        ) {
                            project.selectDeviceColor(color)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                // Corner radius is user-controlled when there's no fixed device
                // hardware dictating its screen geometry.
                bareControlsSection
            }
        }
    }

    private var bareControlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sidebarSliderRow(
                title: "Corner radius",
                value: $project.bareCornerRadius,
                range: 0...0.5,
                display: "\(Int(project.bareCornerRadius * 200))%"
            )

            if project.deviceModel.kind == .generic {
                sidebarSliderRow(
                    title: "Bezel width",
                    value: $project.bareBezelWidth,
                    range: 0...0.1,
                    display: "\(Int(project.bareBezelWidth * 1000))"
                )

                bezelColorRow
            }
        }
    }

    private var bezelColorRow: some View {
        let binding = Binding<Color>(
            get: { Color(hex: project.bareBezelHex) ?? .black },
            set: { newColor in
                project.bareBezelHex = newColor.hexString
            }
        )
        return HStack(spacing: 10) {
            Text("Bezel color").font(.caption.weight(.medium))
            ColorPicker("", selection: binding, supportsOpacity: false)
                .labelsHidden()
            Text(project.bareBezelHex)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Device model short name

private extension DeviceModel {
    /// Short label for the picker chip. Strips/abbreviates the product family
    /// so chips fit in the narrow row: "iPhone 15 Pro" → "15 Pro",
    /// "MacBook Pro 14" → "M Pro 14".
    var shortName: String {
        if displayName.hasPrefix("iPhone ") {
            return String(displayName.dropFirst("iPhone ".count))
        }
        if displayName.hasPrefix("MacBook ") {
            return "M " + displayName.dropFirst("MacBook ".count)
        }
        return displayName
    }
}

// MARK: - Device model chip

private struct DeviceModelChip: View {
    let label: String
    let symbol: String?
    let isSelected: Bool
    let action: () -> Void

    private var fillColor: Color {
        isSelected ? (Color(hex: "#6466FA") ?? .accentColor) : Color.gray.opacity(0.12)
    }

    private var strokeColor: Color {
        isSelected ? Color.white.opacity(0.35) : Color.gray.opacity(0.18)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 7).fill(fillColor))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(strokeColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Device color swatch

private struct DeviceColorSwatch: View {
    let color: DeviceColor
    let isSelected: Bool
    let action: () -> Void

    private var swatch: Color {
        Color(hex: color.swatchHex) ?? .gray
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Selection ring sits behind the swatch with a small gap so the
                // tint reads even on white/silver finishes.
                Circle()
                    .stroke(isSelected
                            ? (Color(hex: "#6466FA") ?? .accentColor)
                            : Color.clear,
                            lineWidth: 2)
                    .frame(width: 30, height: 30)

                Circle()
                    .fill(swatch)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(color.name)
    }
}
