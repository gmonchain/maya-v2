import SwiftUI

/// Applies visual transition effects based on transition type and progress.
/// Progress 0.0 = start of transition, 1.0 = end of transition.
struct TransitionModifier: ViewModifier {
    let type: TransitionType
    let progress: Double
    var intensity: Double = 0.8
    var direction: TransitionDirection = .right

    func body(content: Content) -> some View {
        let p = max(0, min(1, progress))
        let k = intensity

        switch type {
        case .fade:
            content
                .opacity(p)

        case .slideDown:
            let offsetValue: CGFloat = {
                switch direction {
                case .down: return -300 * k * (1 - p)
                case .up: return 300 * k * (1 - p)
                case .left, .right: return 0
                }
            }()
            content
                .offset(y: offsetValue)
                .opacity(0.3 + 0.7 * p)

        case .slideUp:
            let offsetValue: CGFloat = {
                switch direction {
                case .up: return 300 * k * (1 - p)
                case .down: return -300 * k * (1 - p)
                case .left, .right: return 0
                }
            }()
            content
                .offset(y: offsetValue)
                .opacity(0.3 + 0.7 * p)

        case .blur:
            content
                .blur(radius: 25 * k * (1 - p))
                .opacity(0.3 + 0.7 * p)

        case .wipe:
            let widthFraction: CGFloat = {
                switch direction {
                case .right, .down: return p
                case .left, .up: return 1 - p
                }
            }()
            content
                .mask(
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: geo.size.width * widthFraction)
                            .offset(x: direction == .left ? geo.size.width * (1 - widthFraction) : 0)
                    }
                )

        case .zoomIn:
            let scale = 1.0 - (0.7 * k * (1 - p))
            content
                .scaleEffect(scale)
                .opacity(p)

        case .zoomOut:
            let scale = 1.0 + (0.7 * k * (1 - p))
            content
                .scaleEffect(scale)
                .opacity(p)

        case .dissolve:
            content
                .opacity(p)
                .blur(radius: 12 * k * (1 - p))
                .scaleEffect(1.0 + 0.1 * k * (1 - p))
        }
    }
}

extension View {
    func transitionEffect(
        _ type: TransitionType,
        progress: Double,
        intensity: Double = 0.8,
        direction: TransitionDirection = .right
    ) -> some View {
        modifier(TransitionModifier(type: type, progress: progress, intensity: intensity, direction: direction))
    }
}
