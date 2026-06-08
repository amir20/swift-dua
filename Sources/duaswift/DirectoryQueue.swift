import Foundation

/// Shared blocking work-stack of directories left to traverse.
///
/// `pending` counts directories enqueued-but-not-yet-finished so idle workers
/// know when the whole scan is done. `@unchecked Sendable` is safe because the
/// `NSCondition` serializes every access to `stack` and `pending`.
final class DirectoryQueue: @unchecked Sendable {
    private let cond = NSCondition()
    private var stack: [String]
    private var pending: Int

    init(root: String) {
        stack = [root]
        pending = 1
    }

    /// Blocks until a directory is available, or returns `nil` once the scan is
    /// finished (stack empty AND nothing pending). Wakes peers so they exit too.
    func pop() -> String? {
        cond.lock()
        defer { cond.unlock() }
        while stack.isEmpty && pending > 0 {
            cond.wait()
        }
        if stack.isEmpty {            // pending == 0 → everything is done
            cond.broadcast()          // wake the other idle workers to exit
            return nil
        }
        return stack.removeLast()
    }

    /// Adds discovered sub-directories and bumps the pending count.
    func push(_ dirs: [String]) {
        guard !dirs.isEmpty else { return }
        cond.lock()
        stack.append(contentsOf: dirs)
        pending += dirs.count
        cond.broadcast()
        cond.unlock()
    }

    /// Marks the directory just processed as finished.
    func finishOne() {
        cond.lock()
        pending -= 1
        cond.broadcast()
        cond.unlock()
    }
}
