import Synchronization

/// Thread-safe running totals updated by the scanner as it walks, and polled by
/// the UI so a long scan shows live activity instead of a frozen spinner.
/// `skipped` counts directories the walk couldn't read — surfaced so an
/// incomplete picture (missing Full Disk Access) is visible, not silent.
///
/// `fractionDone()` is a determinate progress estimate for a walk whose true
/// size isn't known until it ends. The numerator is *entries scanned* (files +
/// directories) — which paces with wall-clock, since the walk only `stat`s
/// entries and never reads file contents, so time tracks the syscall count.
/// The denominator starts at the volume's used-inode count from `statfs`
/// (`setDenominator`): an **external, fixed** anchor. An earlier attempt used the
/// running count of discovered directories as the denominator, but discovery is
/// gated by processing (you only see a dir's children by listing it), so on the
/// deep-narrow trees filesystems actually are it pinned at ~100% instantly.
///
/// A scan of a *subtree* (e.g. the home folder) covers only a fraction of the
/// volume's inodes, so the raw `entries / usedInodes` would top out at that
/// share (~60% for home) and then snap to 1. To close that gap, the denominator
/// **contracts** as the top-level subtrees complete: with `w` = completed/total
/// top-level subtrees, the volume-wide estimate of what's left (`usedInodes −
/// entriesScanned`) is scaled by `(1 − w)`. Early (`w≈0`) the denominator is the
/// safe full-volume count — it can't overshoot; by the end (`w→1`) it has
/// contracted to the real scanned total, so the bar reaches ~100% on its own.
/// Weighting by subtree *count* (not measured size) keeps a single dominant
/// subtree — `~/Library`, often the last to finish — from collapsing the
/// denominator early and re-introducing the pinned-at-100% stall.
public final class ScanProgress: Sendable {
    /// Never report a full bar mid-scan: the contracting denominator can reach
    /// the scanned total a beat before it finishes. The caller snaps to 1 on done.
    private static let cap = 0.99

    private let state = Mutex(
        (
            files: 0, bytes: Int64(0), skipped: 0, dirs: 0,
            denomEntries: Int64(0), denomBytes: Int64(0),
            totalSubtrees: 0, completedSubtrees: 0, lastFraction: 0.0
        ))

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

    /// Records one directory finished listing (part of the progress numerator).
    public func addDir() {
        state.withLock { $0.dirs += 1 }
    }

    /// Sets the progress denominator once, from the scan volume's `statfs`:
    /// `entries` is the used-inode count (the primary anchor), `bytes` the used
    /// bytes (a fallback when a volume reports no usable inode count).
    public func setDenominator(entries: Int64, bytes: Int64) {
        state.withLock {
            $0.denomEntries = entries
            $0.denomBytes = bytes
        }
    }

    /// Records the number of top-level subtrees the scan will report — the
    /// denominator-contraction anchor. Set once, when the root is listed.
    public func setTotalSubtrees(_ n: Int) {
        state.withLock { $0.totalSubtrees = n }
    }

    /// Records one top-level subtree fully finished, contracting the denominator.
    public func addCompletedSubtree() {
        state.withLock { $0.completedSubtrees += 1 }
    }

    /// Monotonic progress in 0...`cap`. With `scanned` = files + dirs and `w` =
    /// completed/total top-level subtrees, the denominator is `scanned +
    /// (usedInodes − scanned)·(1 − w)` — the full-volume estimate of remaining
    /// work, faded out as subtrees complete. Falls back to `bytes / usedBytes`
    /// when no inode count is available. Clamped so it never falls back; 0 until
    /// a denominator is set (never NaN).
    public func fractionDone() -> Double {
        state.withLock {
            let raw: Double
            if $0.denomEntries > 0 {
                let scanned = Double($0.files + $0.dirs)
                let remaining = max(0, Double($0.denomEntries) - scanned)
                let w =
                    $0.totalSubtrees > 0
                    ? Double($0.completedSubtrees) / Double($0.totalSubtrees) : 0
                let denom = scanned + remaining * (1 - w)
                raw = denom > 0 ? scanned / denom : 0
            } else if $0.denomBytes > 0 {
                raw = Double($0.bytes) / Double($0.denomBytes)
            } else {
                return $0.lastFraction
            }
            $0.lastFraction = max($0.lastFraction, min(raw, Self.cap))
            return $0.lastFraction
        }
    }

    public func snapshot() -> (files: Int, bytes: Int64, skipped: Int) {
        state.withLock { ($0.files, $0.bytes, $0.skipped) }
    }
}
