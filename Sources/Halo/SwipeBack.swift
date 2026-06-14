import AppKit
import SwiftUI

/// Catches a horizontal two-finger trackpad swipe-left and fires `onSwipeLeft`,
/// giving Halo the same "swipe to go back" feel as Finder and Safari. Implemented
/// in AppKit because SwiftUI has no trackpad-swipe gesture on macOS.
///
/// We can't catch the swipe with an `NSView.scrollWheel` override: the donut's
/// `.onContinuousHover` / `.onTapGesture` / `.contextMenu` install SwiftUI host
/// views *in front* of this one, so scroll events hit them and bubble up the
/// responder chain — a background sibling never sees them. Instead we watch the
/// window's scroll stream with a local event monitor, which is independent of
/// z-order. (We don't gate on the cursor's location: SwiftUI positions hosted
/// `NSView`s with layer transforms, so `convert(_:from:)` doesn't map the cursor
/// back to the donut — and a window-wide back-swipe is the behaviour we want.)
///
/// Only horizontal-dominant *trackpad* gestures count (precise deltas, and the
/// net horizontal travel must beat the vertical), so the rail's vertical scroll
/// and ordinary mouse-wheel scrolling pass straight through. We accumulate
/// `scrollingDeltaX` across the gesture and fire once — latched until the gesture
/// ends — when the leftward travel crosses `triggerDistance`.
struct SwipeBackView: NSViewRepresentable {
    /// Invoked once per leftward swipe that crosses the trigger threshold.
    var onSwipeLeft: @MainActor () -> Void

    func makeNSView(context: Context) -> SwipeCatcher {
        let view = SwipeCatcher()
        view.onSwipeLeft = onSwipeLeft
        return view
    }

    func updateNSView(_ nsView: SwipeCatcher, context: Context) {
        nsView.onSwipeLeft = onSwipeLeft
    }

    static func dismantleNSView(_ nsView: SwipeCatcher, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class SwipeCatcher: NSView {
        var onSwipeLeft: (@MainActor () -> Void)?

        /// Net leftward travel (points) that commits the gesture. Deliberate
        /// swipes accumulate this within the first few frames; small horizontal
        /// drift while scrolling never gets close.
        private let triggerDistance: CGFloat = 60

        private var monitor: Any?
        private var travelX: CGFloat = 0
        private var travelY: CGFloat = 0
        private var fired = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stopMonitoring() } else { startMonitoring() }
        }

        private func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event  // never consume — vertical scroll must still work
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            // Trackpad gestures only, and only those aimed at our own window (so a
            // swipe over a sheet, say, doesn't navigate the donut behind it).
            guard event.hasPreciseScrollingDeltas, event.window === window else { return }

            switch event.phase {
            case .began:
                travelX = 0
                travelY = 0
                fired = false
            case .changed:
                travelX += event.scrollingDeltaX
                travelY += event.scrollingDeltaY
                // With natural scrolling, a fingers-left swipe reports positive dx.
                // Require the gesture to be horizontal-dominant so vertical and
                // diagonal scrolls never trip it.
                guard !fired,
                    travelX >= triggerDistance,
                    abs(travelX) > abs(travelY)
                else { return }
                fired = true
                MainActor.assumeIsolated { onSwipeLeft?() }
            case .ended, .cancelled:
                fired = false
            default:
                break
            }
        }
    }
}
