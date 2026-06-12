import Synchronization

/// Thread-safe running totals updated by the scanner as it walks, and polled by
/// the UI so a long scan shows live activity instead of a frozen spinner.
/// `skipped` counts directories the walk couldn't read — surfaced so an
/// incomplete picture (missing Full Disk Access) is visible, not silent.
public final class ScanProgress: Sendable {
    private let state = Mutex((files: 0, bytes: Int64(0), skipped: 0))

    public init() {}

    public func add(files: Int, bytes: Int64) {
        state.withLock {
            $0.files += files
            $0.bytes += bytes
        }
    }

    public func addSkippedDir() {
        state.withLock { $0.skipped += 1 }
    }

    public func snapshot() -> (files: Int, bytes: Int64, skipped: Int) {
        state.withLock { ($0.files, $0.bytes, $0.skipped) }
    }
}
