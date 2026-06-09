import Foundation
import Synchronization
#if canImport(Darwin)
import Darwin
#endif

/// Per-worker accumulator. A reference type so each worker can own one slot
/// and mutate it lock-free (no inout-across-threads). `@unchecked Sendable`:
/// each instance is owned by exactly one worker for the duration of a scan
/// (single-writer invariant), so the `accums` array can cross into
/// `concurrentPerform` under strict concurrency checking.
final class Accum: @unchecked Sendable {
    var size: Int64 = 0
    var entries: Int = 0
}

struct ScanResult {
    var size: Int64
    var entries: Int
}

/// Reads a `dirent`'s name without allocating an intermediate copy of the
/// fixed-size C char tuple.
@inline(__always)
func direntName(_ entp: UnsafeMutablePointer<dirent>) -> String {
    return withUnsafePointer(to: &entp.pointee.d_name) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: Int(entp.pointee.d_namlen) + 1) {
            String(cString: $0)
        }
    }
}

/// A parallel, raw-POSIX directory scanner that mirrors `dua aggregate`'s
/// default semantics: disk usage (allocated blocks), hard-link de-duplication,
/// symlinks not followed.
final class DiskScanner: Sendable {
    let apparent: Bool
    let countHardLinks: Bool
    let threadCount: Int
    let progress: ProgressCounter?

    /// Hard-link de-dup: only consulted for regular files with > 1 link, so the
    /// lock is essentially uncontended on normal trees.
    private struct INode: Hashable { let dev: Int32; let ino: UInt64 }
    private let seen = Mutex(Set<INode>())

    init(apparent: Bool, countHardLinks: Bool, threadCount: Int, progress: ProgressCounter? = nil) {
        self.apparent = apparent
        self.countHardLinks = countHardLinks
        self.threadCount = max(1, threadCount)
        self.progress = progress
    }

    @inline(__always)
    private func accumulate(_ st: stat, into acc: Accum) {
        acc.entries += 1
        let fmt = UInt32(st.st_mode) & UInt32(S_IFMT)
        if !countHardLinks && fmt == UInt32(S_IFREG) && st.st_nlink > 1 {
            let key = INode(dev: st.st_dev, ino: st.st_ino)
            let isNew = seen.withLock { $0.insert(key).inserted }
            if !isNew { return }
        }
        if apparent {
            acc.size += Int64(st.st_size)
        } else {
            acc.size += Int64(st.st_blocks) * 512
        }
    }

    /// Lists one directory, sizing each entry and returning its sub-directories.
    private func processDirectory(_ path: String, into acc: Accum) -> [String] {
        guard let dirp = opendir(path) else { return [] }
        defer { closedir(dirp) }
        var subdirs: [String] = []
        while let entp = readdir(dirp) {
            let name = direntName(entp)
            if name == "." || name == ".." { continue }
            let full = path + "/" + name
            var st = stat()
            if full.withCString({ lstat($0, &st) }) != 0 { continue }
            accumulate(st, into: acc)
            if (UInt32(st.st_mode) & UInt32(S_IFMT)) == UInt32(S_IFDIR) {
                subdirs.append(full)
            }
        }
        return subdirs
    }

    private func workerLoop(_ acc: Accum, _ queue: DirectoryQueue) {
        while let dir = queue.pop() {
            let beforeEntries = acc.entries
            let beforeSize = acc.size
            let subdirs = processDirectory(dir, into: acc)
            progress?.update(files: acc.entries - beforeEntries,
                             bytes: acc.size - beforeSize,
                             current: dir)
            queue.push(subdirs)   // push children before finishing this dir so
            queue.finishOne()     // `pending` never hits zero prematurely
        }
    }

    func scan(_ root: String) -> ScanResult {
        seen.withLock { $0.removeAll(keepingCapacity: true) }

        let rootAccum = Accum()
        var st = stat()
        guard root.withCString({ lstat($0, &st) }) == 0 else {
            return ScanResult(size: 0, entries: 0)
        }
        accumulate(st, into: rootAccum)
        progress?.update(files: rootAccum.entries, bytes: rootAccum.size, current: root)
        if (UInt32(st.st_mode) & UInt32(S_IFMT)) != UInt32(S_IFDIR) {
            return ScanResult(size: rootAccum.size, entries: rootAccum.entries)
        }

        let queue = DirectoryQueue(root: root)
        let accums = (0..<threadCount).map { _ in Accum() }
        DispatchQueue.concurrentPerform(iterations: threadCount) { idx in
            self.workerLoop(accums[idx], queue)
        }

        var total = rootAccum.size
        var entries = rootAccum.entries
        for a in accums {
            total += a.size
            entries += a.entries
        }
        return ScanResult(size: total, entries: entries)
    }
}
