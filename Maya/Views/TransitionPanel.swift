import SwiftUI

struct TransitionPanel: View {
    @Bindable var project: Project
    let transitionID: Transition.ID
    let onDismiss: () -> Void

    @State private var isCustomizing = false
    @State private var hasPushedUndo: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let binding = transitionBinding() {
                        previewSection(binding: binding)

                        typeSection(binding: binding)

                        customizeToggle(binding: binding)

                        if isCustomizing {
                            VStack(alignment: .leading, spacing: 20) {
                                Divider()
                                timingSection(binding: binding)
                                Divider()
                                intensitySection(binding: binding)
                                Divider()
                                curveSection(binding: binding)
                                if binding.wrappedValue.type.supportsDirection {
                                    Divider()
                                    directionSection(binding: binding)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        Divider()
                        actionsSection
                    } else {
                        Text("Transition not found.").foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "#6466FA") ?? .indigo)
            Text("Transition")
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

    // MARK: - Preview section

    private func previewSection(binding: Binding<Transition>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Preview")
            LargeTransitionPreview(
                type: binding.wrappedValue.type,
                duration: binding.wrappedValue.duration,
                intensity: binding.wrappedValue.intensity,
                direction: binding.wrappedValue.direction
            )
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(binding.wrappedValue.type.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Transition type selection

    private func typeSection(binding: Binding<Transition>) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Transition type")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(TransitionType.allCases) { type in
                    TransitionPresetCard(
                        type: type,
                        isSelected: binding.wrappedValue.type == type
                    ) {
                        if !hasPushedUndo {
                            project.pushUndo()
                            hasPushedUndo = true
                        }
                        binding.wrappedValue.type = type
                    }
                }
            }
        }
    }

    // MARK: - Customize toggle

    private func customizeToggle(binding: Binding<Transition>) -> some View {
        let title: String = {
            if isCustomizing { return "Hide custom settings" }
            return "Customize \(binding.wrappedValue.type.displayName)"
        }()
        let symbol = isCustomizing ? "chevron.up" : "slider.horizontal.3"
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCustomizing.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isCustomizing ? 90 : 0))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Timing

    private func timingSection(binding: Binding<Transition>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Timing")
            labeledSlider(
                title: "Duration",
                value: Binding(
                    get: { binding.wrappedValue.duration },
                    set: { newValue in
                        if !hasPushedUndo {
                            project.pushUndo()
                            hasPushedUndo = true
                        }
                        binding.wrappedValue.duration = newValue
                    }
                ),
                range: Transition.durationRange,
                display: String(format: "%.2fs", binding.wrappedValue.duration)
            )
        }
    }

    // MARK: - Intensity

    private func intensitySection(binding: Binding<Transition>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Intensity")
            labeledSlider(
                title: "Strength",
                value: Binding(
                    get: { binding.wrappedValue.intensity },
                    set: { newValue in
                        if !hasPushedUndo {
                            project.pushUndo()
                            hasPushedUndo = true
                        }
                        binding.wrappedValue.intensity = newValue
                    }
                ),
                range: Transition.intensityRange,
                display: String(format: "%.0f%%", binding.wrappedValue.intensity * 100)
            )
        }
    }

    // MARK: - Curve

    private func curveSection(binding: Binding<Transition>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Animation curve")
            let columns = [GridItem(.adaptive(minimum: 130), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AnimationCurve.allCases) { curve in
                    CurveOptionButton(
                        curve: curve,
                        isSelected: binding.wrappedValue.curve == curve
                    ) {
                        if !hasPushedUndo {
                            project.pushUndo()
                            hasPushedUndo = true
                        }
                        binding.wrappedValue.curve = curve
                    }
                }
            }
        }
    }

    // MARK: - Direction

    private func directionSection(binding: Binding<Transition>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Direction")
            HStack(spacing: 8) {
                ForEach(TransitionDirection.allCases) { dir in
                    DirectionButton(
                        direction: dir,
                        isSelected: binding.wrappedValue.direction == dir
                    ) {
                        if !hasPushedUndo {
                            project.pushUndo()
                            hasPushedUndo = true
                        }
                        binding.wrappedValue.direction = dir
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack {
            Button(role: .destructive) {
                project.removeTransition(id: transitionID)
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

    private func labeledSlider<V: BinaryFloatingPoint>(
        title: String,
        value: Binding<V>,
        range: ClosedRange<V>,
        display: String
    ) -> some View where V.Stride: BinaryFloatingPoint {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(display).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func transitionBinding() -> Binding<Transition>? {
        guard project.transitions.contains(where: { $0.id == transitionID }) else { return nil }
        return Binding(
            get: {
                project.transitions.first(where: { $0.id == transitionID })
                    ?? Transition(clipBeforeID: UUID(), clipAfterID: UUID())
            },
            set: { newValue in
                project.updateTransition(newValue)
            }
        )
    }
}

// MARK: - Direction Button

private struct DirectionButton: View {
    let direction: TransitionDirection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: direction.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(direction.displayName)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? (Color(hex: "#6466FA") ?? .indigo)
                          : Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.white.opacity(0.4) : Color.gray.opacity(0.2),
                             lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transition Preset Card

private struct TransitionPresetCard: View {
    let type: TransitionType
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                MiniTransitionPreview(type: type)
                    .aspectRatio(1.4, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.2))

                HStack(spacing: 4) {
                    Image(systemName: type.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                    Text(type.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected
                        ? (Color(hex: "#6466FA") ?? .indigo)
                        : Color.gray.opacity(0.12)
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected
                            ? (Color(hex: "#6466FA") ?? .indigo)
                            : Color.gray.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help(type.description)
    }
}

// MARK: - Mini Transition Preview (in card)

private struct MiniTransitionPreview: View {
    let type: TransitionType

    @State private var animate = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.2))

            Group {
                switch type {
                case .fade:
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#6466FA") ?? .indigo)
                        .opacity(animate ? 1.0 : 0.0)

                case .slideDown:
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#6466FA") ?? .indigo)
                        .offset(y: animate ? 0 : -30)

                case .slideUp:
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#6466FA") ?? .indigo)
                        .offset(y: animate ? 0 : 30)

                case .blur:
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#6466FA") ?? .indigo)
                        .blur(radius: animate ? 0 : 5)

                case .wipe:
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#6466FA") ?? .indigo)
                        .scaleEffect(x: animate ? 1.0 : 0.0, y: 1.0, anchor: .leading)

                case .zoomIn:
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#6466FA") ?? .indigo)
                        .scaleEffect(animate ? 1.0 : 0.2)

                case .zoomOut:
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#6466FA") ?? .indigo)
                        .scaleEffect(animate ? 0.2 : 1.0)

                case .dissolve:
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: "#6466FA") ?? .indigo)
                        .opacity(animate ? 1.0 : 0.0)
                        .blur(radius: animate ? 0 : 4)
                }
            }
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: animate)
        }
        .id(type)
        .onAppear { animate = true }
    }
}

// MARK: - Large Transition Preview (for panel)

private struct LargeTransitionPreview: View {
    let type: TransitionType
    let duration: Double
    let intensity: Double
    let direction: TransitionDirection

    @State private var animate = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.15))

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.08))
                .overlay(
                    Text("Clip 1")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                )

            contentView
                .animation(.easeInOut(duration: max(0.3, min(duration, 2.0))).repeatForever(autoreverses: true), value: animate)
        }
        .id(type)
        .onAppear { animate = true }
    }

    @ViewBuilder
    private var contentView: some View {
        switch type {
        case .fade:
            previewBox
                .opacity(animate ? 1.0 : 0.0)

        case .slideDown:
            previewBox
                .offset(y: -200 * intensity * (animate ? 0 : 1))
                .opacity(0.3 + 0.7 * (animate ? 1 : 0))

        case .slideUp:
            previewBox
                .offset(y: 200 * intensity * (animate ? 0 : 1))
                .opacity(0.3 + 0.7 * (animate ? 1 : 0))

        case .blur:
            previewBox
                .blur(radius: 20 * intensity * (animate ? 0 : 1))
                .opacity(0.3 + 0.7 * (animate ? 1 : 0))

        case .wipe:
            previewBox
                .mask(
                    GeometryReader { geo in
                        let fraction = CGFloat(animate ? 1 : 0)
                        Rectangle()
                            .frame(width: geo.size.width * fraction)
                            .offset(x: direction == .left ? geo.size.width * (1 - fraction) : 0)
                    }
                )

        case .zoomIn:
            let scale = 1.0 - (0.7 * intensity * (animate ? 0 : 1))
            previewBox
                .scaleEffect(scale)
                .opacity(animate ? 1 : 0)

        case .zoomOut:
            let scale = 1.0 + (0.7 * intensity * (animate ? 0 : 1))
            previewBox
                .scaleEffect(scale)
                .opacity(animate ? 1 : 0)

        case .dissolve:
            previewBox
                .opacity(animate ? 1 : 0)
                .blur(radius: 10 * intensity * (animate ? 0 : 1))
                .scaleEffect(1.0 + 0.1 * intensity * (animate ? 0 : 1))
        }
    }

    private var previewBox: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(hex: "#6466FA") ?? .indigo)
            .overlay(
                Text("Clip 2")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            )
    }
}
