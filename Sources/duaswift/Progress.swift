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

/// Renders a single self-updating status line to stderr while a scan runs.
final class ProgressMonitor {
    private let counter: ProgressCounter
    private let interval: useconds_t = 80_000   // 80 ms
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private let start = Date()

    private let runLock = NSLock()
    private var running = true
    private let finished = DispatchSemaphore(value: 0)

    init(counter: ProgressCounter) { self.counter = counter }

    private func isRunning() -> Bool {
        runLock.lock(); defer { runLock.unlock() }; return running
    }

    func begin() {
        Thread {
            var tick = 0
            while self.isRunning() {
                self.render(tick)
                tick += 1
                usleep(self.interval)
            }
            self.renderFinal()
            self.finished.signal()
        }.start()
    }

    func finish() {
        runLock.lock(); running = false; runLock.unlock()
        finished.wait()   // let the monitor clear/print its final line first
    }

    private func render(_ tick: Int) {
        let s = counter.snapshot()
        let frame = frames[tick % frames.count]
        let line = "\r\u{1b}[K\(frame) scanning… \(grouped(s.files)) files · "
            + "\(formatMetric(s.bytes)) · \(String(format: "%.1fs", -start.timeIntervalSinceNow))  "
            + truncatePath(s.current)
        fputs(line, stderr)
        fflush(stderr)
    }

    private func renderFinal() {
        let s = counter.snapshot()
        let line = "\r\u{1b}[K✓ scanned \(grouped(s.files)) files · "
            + "\(formatMetric(s.bytes)) in \(String(format: "%.2fs", -start.timeIntervalSinceNow))\n"
        fputs(line, stderr)
        fflush(stderr)
    }
}

