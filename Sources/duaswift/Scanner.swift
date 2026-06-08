import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Per-worker accumulator. A reference type so each worker can own one slot
/// and mutate it lock-free (no inout-across-threads).
final class Accum {
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
final class DiskScanner {
    let apparent: Bool
    let countHardLinks: Bool
    let threadCount: Int

    /// Shared work-stack of directories left to traverse. `pending` counts dirs
    /// enqueued-but-not-yet-finished so idle workers know when the scan is done.
    private let cond = NSCondition()
    private var dirStack: [String] = []
    private var pending = 0

    /// Hard-link de-dup: only consulted for regular files with > 1 link, so the
    /// lock is essentially uncontended on normal trees.
    private struct INode: Hashable { let dev: Int32; let ino: UInt64 }
    private let inodeLock = NSLock()
    private var seen = Set<INode>()

    init(apparent: Bool, countHardLinks: Bool, threadCount: Int) {
        self.apparent = apparent
        self.countHardLinks = countHardLinks
        self.threadCount = max(1, threadCount)
    }

    @inline(__always)
    private func accumulate(_ st: stat, into acc: Accum) {
        acc.entries += 1
        let fmt = UInt32(st.st_mode) & UInt32(S_IFMT)
        if !countHardLinks && fmt == UInt32(S_IFREG) && st.st_nlink > 1 {
            let key = INode(dev: st.st_dev, ino: st.st_ino)
            inodeLock.lock()
            let isNew = seen.insert(key).inserted
            inodeLock.unlock()
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

    private func workerLoop(_ acc: Accum) {
        while true {
            cond.lock()
            while dirStack.isEmpty && pending > 0 { cond.wait() }
            if dirStack.isEmpty {            // pending == 0 → everything is done
                cond.broadcast()            // wake the other idle workers to exit
                cond.unlock()
                break
            }
            let dir = dirStack.removeLast()
            cond.unlock()

            let subdirs = processDirectory(dir, into: acc)

            cond.lock()
            if !subdirs.isEmpty {
                dirStack.append(contentsOf: subdirs)
                pending += subdirs.count
            }
            pending -= 1
            cond.broadcast()
            cond.unlock()
        }
    }

    func scan(_ root: String) -> ScanResult {
        seen.removeAll(keepingCapacity: true)

        let rootAccum = Accum()
        var st = stat()
        guard root.withCString({ lstat($0, &st) }) == 0 else {
            return ScanResult(size: 0, entries: 0)
        }
        accumulate(st, into: rootAccum)
        if (UInt32(st.st_mode) & UInt32(S_IFMT)) != UInt32(S_IFDIR) {
            return ScanResult(size: rootAccum.size, entries: rootAccum.entries)
        }

        dirStack = [root]
        pending = 1

        let accums = (0..<threadCount).map { _ in Accum() }
        DispatchQueue.concurrentPerform(iterations: threadCount) { idx in
            self.workerLoop(accums[idx])
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
