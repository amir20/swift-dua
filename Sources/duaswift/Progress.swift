import Foundation
import Synchronization
#if canImport(Darwin)
import Darwin
#endif

/// Thread-safe running totals updated by scanner workers (once per directory)
/// and read by the progress monitor.
final class ProgressCounter: Sendable {
    private struct State {
        var files = 0
        var bytes: Int64 = 0
        var current = ""
    }
    private let state = Mutex(State())

    func update(files deltaFiles: Int, bytes deltaBytes: Int64, current path: String) {
        state.withLock {
            $0.files += deltaFiles
            $0.bytes += deltaBytes
            $0.current = path
        }
    }

    func snapshot() -> (files: Int, bytes: Int64, current: String) {
        state.withLock { ($0.files, $0.bytes, $0.current) }
    }
}

/// Pure rendering of a progress snapshot to stderr. Value type so the timer's
/// @Sendable handler can capture it without capturing the monitor.
struct ProgressRenderer: Sendable {
    let counter: ProgressCounter
    let frames: [String]
    let start: Date

    /// Animated in-progress line. Frame is derived from elapsed time so there
    /// is no mutable counter to capture.
    func renderTick() {
        let elapsed = -start.timeIntervalSinceNow
        let frame = frames[Int(elapsed / 0.08) % frames.count]
        let s = counter.snapshot()
        let line = "\r\u{1b}[K\(frame) scanning… \(grouped(s.files)) files · "
            + "\(formatMetric(s.bytes)) · \(String(format: "%.1fs", elapsed))  "
            + truncatePath(s.current)
        fputs(line, stderr)
        fflush(stderr)
    }

    /// Final summary line, printed once when the scan ends.
    func renderFinal() {
        let s = counter.snapshot()
        let line = "\r\u{1b}[K✓ scanned \(grouped(s.files)) files · "
            + "\(formatMetric(s.bytes)) in \(String(format: "%.2fs", -start.timeIntervalSinceNow))\n"
        fputs(line, stderr)
        fflush(stderr)
    }
}

/// Renders a single self-updating status line to stderr while a scan runs.
/// Used single-threaded: `begin()` then `finish()` on the same thread.
final class ProgressMonitor {
    private let renderer: ProgressRenderer
    private let queue = DispatchQueue(label: "duaswift.progress")
    private var timer: DispatchSourceTimer?

    init(counter: ProgressCounter) {
        renderer = ProgressRenderer(
            counter: counter,
            frames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
            start: Date()
        )
    }

    deinit {
        timer?.cancel()
    }

    func begin() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(80))
        let r = renderer
        t.setEventHandler { r.renderTick() }
        timer = t
        t.resume()
    }

    func finish() {
        guard let t = timer else { return }
        let done = DispatchSemaphore(value: 0)
        let r = renderer
        // Cancel handler runs once on `queue` after the last event handler;
        // it prints the final line and releases finish().
        t.setCancelHandler {
            r.renderFinal()
            done.signal()
        }
        t.cancel()
        done.wait()
        timer = nil
    }
}

