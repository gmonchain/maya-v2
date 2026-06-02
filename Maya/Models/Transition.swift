import Foundation
import SwiftUI

// MARK: - Transition Direction

enum TransitionDirection: String, CaseIterable, Identifiable, Codable, Sendable {
    case left
    case right
    case up
    case down

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: "Trái"
        case .right: "Phải"
        case .up: "Lên"
        case .down: "Xuống"
        }
    }

    var systemImage: String {
        switch self {
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .up: "arrow.up"
        case .down: "arrow.down"
        }
    }
}

// MARK: - Transition Type

enum TransitionType: String, CaseIterable, Identifiable, Codable, Sendable {
    case fade
    case slideDown
    case slideUp
    case blur
    case wipe
    case zoomIn
    case zoomOut
    case dissolve

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fade: "Fade"
        case .slideDown: "Slide Down"
        case .slideUp: "Slide Up"
        case .blur: "Blur"
        case .wipe: "Wipe"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .dissolve: "Dissolve"
        }
    }

    var systemImage: String {
        switch self {
        case .fade: "circle.lefthalf.filled"
        case .slideDown: "arrow.down.to.line"
        case .slideUp: "arrow.up.to.line"
        case .blur: "drop.blur"
        case .wipe: "rectangle.righthalf.filled"
        case .zoomIn: "arrow.up.left.and.arrow.down.right"
        case .zoomOut: "arrow.down.right.and.arrow.up.left"
        case .dissolve: "sparkles"
        }
    }

    var description: String {
        switch self {
        case .fade: "Clip mờ dần rồi hiện ra"
        case .slideDown: "Kéo xuống rồi hiện lên từ dưới"
        case .slideUp: "Trượt lên từ dưới"
        case .blur: "Mờ nhoè rồi rõ dần"
        case .wipe: "Quét ngang từ trái sang phải"
        case .zoomIn: "Phóng to từ xa"
        case .zoomOut: "Thu nhỏ dần"
        case .dissolve: "Tan dần rồi hiện ra"
        }
    }

    var supportsDirection: Bool {
        switch self {
        case .slideDown, .slideUp, .wipe: return true
        default: return false
        }
    }
}

// MARK: - Transition

struct Transition: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    /// ID of the clip before this transition (outgoing clip).
    var clipBeforeID: UUID
    /// ID of the clip after this transition (incoming clip).
    var clipAfterID: UUID
    /// Type of transition effect.
    var type: TransitionType
    /// Duration of the transition in seconds.
    var duration: Double
    /// Animation curve for easing.
    var curve: AnimationCurve
    /// Intensity/strength of the effect (0.0 to 1.0).
    var intensity: Double
    /// Direction for slide/wipe transitions.
    var direction: TransitionDirection

    static let defaultDuration: Double = 0.5
    static let durationRange: ClosedRange<Double> = 0.1...2.0
    static let intensityRange: ClosedRange<Double> = 0.2...1.0

    init(
        id: UUID = UUID(),
        clipBeforeID: UUID,
        clipAfterID: UUID,
        type: TransitionType = .fade,
        duration: Double = Transition.defaultDuration,
        curve: AnimationCurve = .smooth,
        intensity: Double = 0.8,
        direction: TransitionDirection = .right
    ) {
        self.id = id
        self.clipBeforeID = clipBeforeID
        self.clipAfterID = clipAfterID
        self.type = type
        self.duration = duration
        self.curve = curve
        self.intensity = intensity
        self.direction = direction
    }
}
