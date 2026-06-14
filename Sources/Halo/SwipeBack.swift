import AppKit
import SwiftUI

/// Catches a horizontal two-finger trackpad swipe and fires `onSwipeLeft`, giving
/// Halo the same "swipe to go back" feel as Finder and Safari. Implemented in
/// AppKit because SwiftUI has no trackpad-swipe gesture on macOS.
///
/// Only horizontal-dominant *trackpad* gestures count — precise deltas with
/// `|dx| > |dy|` — so ordinary mouse-wheel scrolling and the rail's vertical
/// scroll pass straight through. The swipe is followed with `NSEvent`'s
/// `trackSwipeEvent`, which coalesces the whole gesture (including inertial
/// momentum) into a single -1…1 amount, so one swipe can only fire `back()` once.
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

    final class SwipeCatcher: NSView {
        var onSwipeLeft: (@MainActor () -> Void)?

        override func scrollWheel(with event: NSEvent) {
            // Begin tracking only on the opening frame of a horizontal trackpad
            // gesture; everything else (vertical scroll, mouse wheel) bubbles up.
            guard event.phase == .began,
                event.hasPreciseScrollingDeltas,
                abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            else {
                super.scrollWheel(with: event)
                return
            }

            var fired = false
            event.trackSwipeEvent(
                options: .lockDirection,
                dampenAmountThresholdMin: -1, max: 1
            ) { [weak self] amount, _, _, _ in
                // Positive amount = swipe right, negative = swipe left. Fire once
                // the leftward swipe passes the halfway point. `trackSwipeEvent`
                // runs its handler synchronously on the main thread.
                guard !fired, amount < -0.5 else { return }
                fired = true
                MainActor.assumeIsolated { self?.onSwipeLeft?() }
            }
        }
    }
}
