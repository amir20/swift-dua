import AppKit
import SwiftUI

/// Draws a determinate progress bar across the bottom of the app's Dock icon
/// while a scan runs. macOS has no system Dock-progress API — Finder and Safari
/// render their own — so we install a custom view as `NSApp.dockTile.contentView`:
/// the normal app icon with a rounded bar overlaid, redrawn whenever the fraction
/// moves. Set `fraction` to a value in 0...1 to show it, or `nil` to restore the
/// plain icon.
///
/// Updates are driven from `ScanModel`'s 10 Hz poll on the main actor; the
/// scanner threads only ever touch lock-free counters, never AppKit.
@MainActor
final class DockProgress {
    static let shared = DockProgress()

    private lazy var view = DockTileProgressView()

    private init() {}

    /// Progress in 0...1, or `nil` to hide the bar and show the plain icon.
    /// Idempotent: re-setting the same value (rounded to the visible resolution)
    /// skips the redraw, so the 10 Hz poll doesn't repaint the tile needlessly.
    var fraction: Double? {
        didSet {
            let new = fraction.map { ($0 * 200).rounded() / 200 }  // ~0.5% steps
            let old = oldValue.map { ($0 * 200).rounded() / 200 }
            guard new != old else { return }
            // No running NSApplication (unit tests / headless) → no Dock tile.
            guard let tile = NSApp?.dockTile else { return }
            if let new {
                view.fraction = min(max(new, 0), 1)
                if tile.contentView !== view { tile.contentView = view }
            } else {
                tile.contentView = nil
            }
            tile.display()
        }
    }
}

/// The Dock tile's content: the app icon with a rounded progress bar near the
/// bottom edge. Geometry is in fractions of the tile so it scales with the Dock.
private final class DockTileProgressView: NSView {
    var fraction: Double = 0

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(
            in: bounds, from: .zero, operation: .sourceOver, fraction: 1)

        let inset = bounds.width * 0.14
        let height = bounds.height * 0.12
        let track = NSRect(
            x: inset, y: bounds.height * 0.10,
            width: bounds.width - inset * 2, height: height)
        let radius = height / 2

        // Dark, semi-transparent track so the bar reads on any icon.
        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        // The filled portion — floored to a full cap-width so even tiny progress
        // shows a rounded nub rather than a sliver.
        var fill = track
        fill.size.width = max(height, track.width * CGFloat(fraction))
        NSColor(Palette.progress).setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()

        // Hairline highlight to lift the track off the icon.
        NSColor.white.withAlphaComponent(0.25).setStroke()
        let border = NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        border.stroke()
    }
}
