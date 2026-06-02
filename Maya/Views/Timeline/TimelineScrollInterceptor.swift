import AppKit
import SwiftUI

/// Intercepts scrollWheel events at the application level when the mouse is over
/// the timeline, routing them as zoom/pan deltas. Uses `NSEvent.addLocalMonitorForEvents`
/// to catch events before they hit any view — this avoids the hit-testing issues
/// that come with a plain NSView approach.
struct TimelineScrollInterceptor: NSViewRepresentable {
    /// Called with (zoomDelta, panDelta, anchorX) where:
    /// - zoomDelta: scaled dy delta for zoom computation
    /// - panDelta: scaled dx delta in pixels
    /// - anchorX: cursor x position relative to viewport left edge
    let onScroll: (CGFloat, CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.onScroll = onScroll
    }

    /// A minimal NSView whose only job is to register/deregister a local event
    /// monitor tied to its view lifecycle. It checks whether the mouse is inside
    /// its bounds and forwards matching scrollWheel events.
    class AnchorView: NSView {
        var onScroll: ((CGFloat, CGFloat, CGFloat) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                // Prevent SwiftUI from routing scroll events away from us into
                // any ancestor ScrollView — we consume them here.
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    self?.handleScrollWheel(event) ?? event
                }
            } else {
                removeMonitor()
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                removeMonitor()
            }
        }

        deinit { removeMonitor() }

        private func removeMonitor() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
            guard let onScroll = onScroll else { return event }

            // Only intercept when mouse is inside our bounds — pass through otherwise.
            let localPoint = convert(event.locationInWindow, from: nil)
            guard bounds.contains(localPoint) else { return event }

            let isTrackpad = event.hasPreciseScrollingDeltas
            let dy = event.scrollingDeltaY
            let dx = event.scrollingDeltaX

            // Sensitivity: trackpad has smaller, precise deltas; mouse wheel has
            // large line-based deltas that need different scaling.
            let zoomSensitivity: CGFloat = isTrackpad ? 0.0006 : 0.006
            let panSensitivity: CGFloat = isTrackpad ? 1.0 : 2.0

            // Anchor point: cursor x relative to viewport left edge, clamped to bounds.
            let anchorX = max(0, min(localPoint.x, bounds.width))

            onScroll(
                dy * zoomSensitivity,   // zoomDelta
                dx * panSensitivity,    // panDelta (px)
                anchorX
            )

            return nil  // Consume the event — don't let it reach other views.
        }
    }
}
