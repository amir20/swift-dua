# duaswift Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hand-rolled flag parsing and hand-assembled concurrency primitives in the `duaswift` target with swift-argument-parser and `Synchronization.Mutex` + a `DispatchSourceTimer`, under Swift 6 language mode, with no change to CLI behavior or scan results.

**Architecture:** Keep the proven GCD `concurrentPerform` parallel scan. Modernize only the synchronization primitives beneath it: `Mutex` replaces both `NSLock`s, a `DispatchSourceTimer` replaces the monitor's `Thread`+`runLock`+`semaphore`, and the work-stack `NSCondition` is encapsulated behind a single-purpose `DirectoryQueue`. Build stays green throughout by staging the language-mode flip to the final task.

**Tech Stack:** Swift 6.3 toolchain, Swift 6 language mode, macOS 26 deployment floor, `Synchronization` (`Mutex`), Dispatch (`DispatchSourceTimer`), swift-argument-parser 1.8.2, XCTest.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `Package.swift` | Manifest: tools 6.0, macOS 26, argument-parser dep, test target | Modify |
| `Sources/duaswift/Duaswift.swift` | `@main ParsableCommand` entry + run logic (was `main.swift`) | Rename + rewrite |
| `Sources/duaswift/Formatting.swift` | Pure formatting helpers (`grouped`, `truncatePath`, `formatMetric`, `renderSize`, `leftPad`) + `ByteFormat` | Create |
| `Sources/duaswift/Progress.swift` | `ProgressCounter` (Mutex), `ProgressRenderer`, `ProgressMonitor` (timer) | Modify |
| `Sources/duaswift/DirectoryQueue.swift` | Blocking work-stack (encapsulated `NSCondition`) | Create |
| `Sources/duaswift/Scanner.swift` | Parallel POSIX walker; `Mutex` inode set; `Accum` | Modify |
| `Tests/duaswiftTests/FormattingTests.swift` | Unit tests for formatting + `ByteFormat` | Create |
| `Tests/duaswiftTests/DiskScannerTests.swift` | Characterization tests for the scanner | Create |
| `Tests/duaswiftTests/ProgressCounterTests.swift` | Unit test for the counter | Create |

`grouped` and `truncatePath` currently live in `Progress.swift` (lines 85–101); they move to `Formatting.swift`. `formatMetric`, `renderSize`, `leftPad` currently live in `main.swift`; they move to `Formatting.swift`, and `renderSize` gains an explicit `format:` parameter (no more global).

---

## Task 1: Manifest bump + test scaffold (staged to Swift 5 mode)

**Files:**
- Modify: `Package.swift`
- Create: `Tests/duaswiftTests/ScaffoldTests.swift`

- [ ] **Step 1: Rewrite `Package.swift`**

```swift
// swift-tools-version:6.2
import PackageDescription   // 6.2 (not 6.0): .macOS(.v26) requires PackageDescription 6.2

let package = Package(
    name: "ProgressApp",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "ProgressApp", targets: ["ProgressApp"]),
        .executable(name: "duaswift", targets: ["duaswift"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2")
    ],
    targets: [
        .executableTarget(
            name: "ProgressApp",
            path: "Sources/ProgressApp"
        ),
        .executableTarget(
            name: "duaswift",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/duaswift",
            // TEMPORARY: staged to Swift 5 mode so the existing code keeps
            // building during the refactor. Removed in the final task to turn
            // on Swift 6 strict data-race checking.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "duaswiftTests",
            dependencies: ["duaswift"],
            path: "Tests/duaswiftTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .plugin(
            name: "BundleApp",
            capability: .command(
                intent: .custom(
                    verb: "bundle-app",
                    description: "Build a release binary and package it into a double-clickable .app bundle"
                ),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "Write the generated ProgressApp.app bundle into the project directory"
                    )
                ]
            )
        )
    ]
)
```

- [ ] **Step 2: Create a trivial passing test so the test target builds**

`Tests/duaswiftTests/ScaffoldTests.swift`:

```swift
import XCTest
@testable import duaswift

final class ScaffoldTests: XCTestCase {
    func testScaffold() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 3: Resolve dependencies and build**

Run: `swift build`
Expected: builds successfully; `swift-argument-parser` is fetched. A `Package.resolved` appears.

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: PASS — `testScaffold` passes.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Package.resolved Tests/duaswiftTests/ScaffoldTests.swift
git commit -m "build: add argument-parser dep and test target (staged to Swift 5 mode)"
```

---

## Task 2: Characterization tests for the scanner (guard the refactor)

These tests pin the *existing* scanner's behavior before we touch it. They use apparent-size **deltas** and hard-link **deltas** so assertions don't depend on the filesystem's block size or directory inode sizes.

**Files:**
- Create: `Tests/duaswiftTests/DiskScannerTests.swift`

- [ ] **Step 1: Write the characterization tests**

`Tests/duaswiftTests/DiskScannerTests.swift`:

```swift
import XCTest
import Foundation
@testable import duaswift

final class DiskScannerTests: XCTestCase {

    /// Creates a unique temporary directory; caller scans it.
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("duaswift-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ url: URL, bytes: Int) throws {
        try Data(count: bytes).write(to: url)
    }

    /// The scanner descends into sub-directories and sums regular-file apparent
    /// sizes. Two trees with identical structure (same entry names) where only
    /// one file's *size* differs differ in apparent total by exactly that
    /// difference — the directory inode sizes are identical because the entries
    /// match, so they cancel. (Adding/removing a file would instead perturb the
    /// containing directory's own st_size, e.g. +32 bytes on APFS.)
    func testApparentSizeAggregatesNestedFiles() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        // Tree A: root/sub/data.bin (4096 bytes)
        let treeA = base.appendingPathComponent("a")
        try FileManager.default.createDirectory(at: treeA.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        try writeFile(treeA.appendingPathComponent("sub/data.bin"), bytes: 4096)

        // Tree B: identical names, but data.bin is 8192 bytes.
        let treeB = base.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: treeB.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        try writeFile(treeB.appendingPathComponent("sub/data.bin"), bytes: 8192)

        let scanner = DiskScanner(apparent: true, countHardLinks: false, threadCount: 4)
        let a = scanner.scan(treeA.path)
        let b = scanner.scan(treeB.path)

        XCTAssertEqual(b.size - a.size, 4096, "a file 4096 bytes larger should raise the apparent total by exactly 4096")
        XCTAssertEqual(a.entries, 3, "root dir + sub dir + data.bin = 3 entries (proves nested descent)")
        XCTAssertEqual(b.entries, 3)
    }

    /// With a hard link present, counting links adds the file's size a second
    /// time; de-duplicating (the default) does not.
    func testHardLinkDeduplication() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        let f = base.appendingPathComponent("f.bin")
        try writeFile(f, bytes: 8192)
        let g = base.appendingPathComponent("g.bin")
        try FileManager.default.linkItem(at: f, to: g)   // hard link, nlink == 2

        let dedup = DiskScanner(apparent: true, countHardLinks: false, threadCount: 4)
        let counted = DiskScanner(apparent: true, countHardLinks: true, threadCount: 4)

        let dedupResult = dedup.scan(base.path)
        let countedResult = counted.scan(base.path)

        XCTAssertEqual(countedResult.size - dedupResult.size, 8192,
                       "counting hard links should add the 8192-byte file a second time")
    }

    /// A non-existent path scans to zero rather than crashing.
    func testMissingPathIsZero() {
        let scanner = DiskScanner(apparent: true, countHardLinks: false, threadCount: 4)
        let r = scanner.scan("/no/such/path/duaswift-\(UUID().uuidString)")
        XCTAssertEqual(r.size, 0)
        XCTAssertEqual(r.entries, 0)
    }
}
```

- [ ] **Step 2: Run the tests against the existing scanner**

Run: `swift test --filter DiskScannerTests`
Expected: PASS — these characterize current behavior, so they pass before any scanner change.

- [ ] **Step 3: Commit**

```bash
git add Tests/duaswiftTests/DiskScannerTests.swift
git commit -m "test: characterization tests for DiskScanner before refactor"
```

---

## Task 3: Extract formatting helpers into `Formatting.swift`

**Files:**
- Create: `Sources/duaswift/Formatting.swift`
- Create: `Tests/duaswiftTests/FormattingTests.swift`
- Modify: `Sources/duaswift/Progress.swift` (remove `grouped`, `truncatePath`)
- Modify: `Sources/duaswift/main.swift` (remove `formatMetric`, `renderSize`, `leftPad`)

- [ ] **Step 1: Write the failing tests**

`Tests/duaswiftTests/FormattingTests.swift`:

```swift
import XCTest
@testable import duaswift

final class FormattingTests: XCTestCase {
    func testGrouped() {
        XCTAssertEqual(grouped(0), "0")
        XCTAssertEqual(grouped(999), "999")
        XCTAssertEqual(grouped(1000), "1,000")
        XCTAssertEqual(grouped(1234567), "1,234,567")
    }

    func testFormatMetric() {
        XCTAssertEqual(formatMetric(0), "0 B")
        XCTAssertEqual(formatMetric(999), "999 B")
        XCTAssertEqual(formatMetric(1000), "1.00 KB")
        XCTAssertEqual(formatMetric(1_500_000), "1.50 MB")
    }

    func testRenderSizeRespectsFormat() {
        XCTAssertEqual(renderSize(1000, format: .metric), "1.00 KB")
        XCTAssertEqual(renderSize(1000, format: .bytes), "1000 b")
    }

    func testTruncatePath() {
        XCTAssertEqual(truncatePath("short", max: 44), "short")
        let long = String(repeating: "a", count: 50)
        let truncated = truncatePath(long, max: 44)
        XCTAssertEqual(truncated.count, 44)
        XCTAssertTrue(truncated.hasPrefix("…"))
    }

    func testLeftPad() {
        XCTAssertEqual(leftPad("7", to: 4), "   7")
        XCTAssertEqual(leftPad("12345", to: 4), "12345")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FormattingTests`
Expected: FAIL to compile — `renderSize(_:format:)` and `ByteFormat` don't exist yet; `formatMetric`/`renderSize`/`leftPad` aren't visible to tests (they live in the `@main`/top-level file today).

- [ ] **Step 3: Create `Formatting.swift` with all helpers + `ByteFormat`**

`Sources/duaswift/Formatting.swift`:

```swift
import Foundation
import ArgumentParser

/// Byte-size output format selected by `--format`.
enum ByteFormat: String, ExpressibleByArgument {
    case metric
    case bytes
}

/// Inserts thousands separators: 1234567 -> "1,234,567".
func grouped(_ n: Int) -> String {
    let digits = String(n)
    guard n >= 1000 else { return digits }
    var out = ""
    var count = 0
    for ch in digits.reversed() {
        if count != 0 && count % 3 == 0 { out.append(",") }
        out.append(ch)
        count += 1
    }
    return String(out.reversed())
}

/// Truncates a path to `max` characters, prefixing an ellipsis when shortened.
func truncatePath(_ path: String, max: Int = 44) -> String {
    guard path.count > max else { return path }
    return "…" + path.suffix(max - 1)
}

/// Human-readable metric byte size (1.00 KB, 1.50 MB, …); raw bytes under 1000.
func formatMetric(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB", "PB"]
    var value = Double(bytes)
    var unit = 0
    while value >= 1000 && unit < units.count - 1 {
        value /= 1000
        unit += 1
    }
    return unit == 0 ? "\(bytes) B" : String(format: "%.2f %@", value, units[unit])
}

/// Renders a size in the chosen format.
func renderSize(_ bytes: Int64, format: ByteFormat) -> String {
    switch format {
    case .bytes:  return "\(bytes) b"
    case .metric: return formatMetric(bytes)
    }
}

/// Right-aligns `s` within `width` columns.
func leftPad(_ s: String, to width: Int) -> String {
    s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
}
```

- [ ] **Step 4: Remove `grouped` and `truncatePath` from `Progress.swift`**

In `Sources/duaswift/Progress.swift`, delete the entire `// MARK: - Small formatting helpers` section (the `grouped(_:)` and `truncatePath(_:max:)` functions, lines 83–101 of the original).

- [ ] **Step 5: Remove the moved helpers from `main.swift`**

In `Sources/duaswift/main.swift`, delete `formatMetric(_:)`, `renderSize(_:)`, and `leftPad(_:to:)` (the `// MARK: - Formatting` section, lines 59–78 of the original). They now live in `Formatting.swift`. (The call site in the print loop still references the old `renderSize(_:)`; it is rewritten in Task 5 when `main.swift` becomes the command.)

> **Execution note (revised):** Removing the old `renderSize(_:)` breaks the
> `duaswift` module, and because the test target `@testable import`s that
> module, the test target can't build either until Task 4 rewrites `main.swift`.
> Therefore **Tasks 3 and 4 are executed together as one unit** with a single
> green build/test endpoint. The separate "run only FormattingTests" checkpoint
> originally suggested here does not work and is superseded. The two commits
> below may be collapsed into the Task 4 commit to avoid a broken intermediate
> commit.

- [ ] **Step 6: Run formatting tests**

Run: `swift test --filter FormattingTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/duaswift/Formatting.swift Sources/duaswift/Progress.swift Sources/duaswift/main.swift Tests/duaswiftTests/FormattingTests.swift
git commit -m "refactor: extract formatting helpers and ByteFormat into Formatting.swift"
```

---

## Task 4: Convert the entry point to a `ParsableCommand`

**Files:**
- Rename: `Sources/duaswift/main.swift` → `Sources/duaswift/Duaswift.swift`
- Rewrite: `Sources/duaswift/Duaswift.swift`

> `@main` is not permitted in a file literally named `main.swift`, so the file is renamed first.

- [ ] **Step 1: Rename the file**

Run: `git mv Sources/duaswift/main.swift Sources/duaswift/Duaswift.swift`

- [ ] **Step 2: Replace the file contents with the command**

`Sources/duaswift/Duaswift.swift`:

```swift
import Foundation
import ArgumentParser
#if canImport(Darwin)
import Darwin
#endif

@main
struct Duaswift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "duaswift",
        abstract: "A tiny Swift reimplementation of `dua aggregate`.",
        discussion: "With no PATH, aggregates each entry in the current directory."
    )

    @Flag(name: [.customShort("A"), .long],
          help: "Use apparent size (st_size) instead of disk usage.")
    var apparentSize = false

    @Flag(name: [.customShort("l"), .long],
          help: "Count hard-linked files each time they are seen.")
    var countHardLinks = false

    @Option(name: [.short, .long],
            help: "Worker threads (default: logical CPU count).")
    var threads = ProcessInfo.processInfo.activeProcessorCount

    @Option(name: [.short, .long],
            help: "Byte format: metric or bytes.")
    var format: ByteFormat = .metric

    @Flag(name: .customLong("no-progress"),
          help: "Disable the live progress line on stderr.")
    var noProgress = false

    @Argument(help: "Paths to aggregate (default: entries of the current directory).")
    var paths: [String] = []

    func run() throws {
        let threadCount = max(1, threads)

        var inputs = paths
        if inputs.isEmpty {
            let cwd = FileManager.default.currentDirectoryPath
            inputs = (try? FileManager.default.contentsOfDirectory(atPath: cwd))?.sorted() ?? ["."]
        }

        // Show live progress only when stderr is an interactive terminal.
        let showProgress = !noProgress && isatty(STDERR_FILENO) != 0
        let counter = showProgress ? ProgressCounter() : nil
        let monitor = counter.map { ProgressMonitor(counter: $0) }

        let scanner = DiskScanner(apparent: apparentSize,
                                  countHardLinks: countHardLinks,
                                  threadCount: threadCount,
                                  progress: counter)

        monitor?.begin()
        var results: [(path: String, size: Int64)] = []
        var grandTotal: Int64 = 0
        for input in inputs {
            let r = scanner.scan(input)
            results.append((input, r.size))
            grandTotal += r.size
        }
        monitor?.finish()

        results.sort { $0.size < $1.size }   // ascending, like dua

        let width = max(10, results.map { renderSize($0.size, format: format).count }.max() ?? 10)
        for r in results {
            print("\(leftPad(renderSize(r.size, format: format), to: width)) \(r.path)")
        }
        if results.count > 1 {
            print("\(leftPad(renderSize(grandTotal, format: format), to: width)) total")
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 4: Smoke-test the CLI**

Run: `swift run duaswift --help`
Expected: argument-parser-generated usage listing `-A/--apparent-size`, `-l/--count-hard-links`, `-t/--threads`, `-f/--format`, `--no-progress`, and `paths`.

Run: `swift run duaswift -f bytes Sources`
Expected: a size line per entry in `Sources/`, ascending, ending in a `total` line, sizes in raw `b`.

Run: `swift run duaswift -f nonsense Sources`
Expected: a parser error naming the invalid `--format` value and a non-zero exit (this is the new validation that the old code lacked).

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: PASS — all existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: replace hand-rolled flag parsing with swift-argument-parser"
```

---

## Task 5: `ProgressCounter` → `Mutex`

**Files:**
- Modify: `Sources/duaswift/Progress.swift`
- Create: `Tests/duaswiftTests/ProgressCounterTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/duaswiftTests/ProgressCounterTests.swift`:

```swift
import XCTest
@testable import duaswift

final class ProgressCounterTests: XCTestCase {
    func testAccumulatesAndSnapshots() {
        let c = ProgressCounter()
        c.update(files: 3, bytes: 100, current: "/a")
        c.update(files: 2, bytes: 50, current: "/b")
        let s = c.snapshot()
        XCTAssertEqual(s.files, 5)
        XCTAssertEqual(s.bytes, 150)
        XCTAssertEqual(s.current, "/b")
    }

    func testConcurrentUpdatesAreConsistent() {
        let c = ProgressCounter()
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            c.update(files: 1, bytes: 1, current: "/x")
        }
        let s = c.snapshot()
        XCTAssertEqual(s.files, 1000)
        XCTAssertEqual(s.bytes, 1000)
    }
}
```

- [ ] **Step 2: Run to verify it passes against the current implementation**

Run: `swift test --filter ProgressCounterTests`
Expected: PASS — the current `NSLock` implementation already satisfies this. (This test is the safety net for the swap that follows.)

- [ ] **Step 3: Replace `ProgressCounter`'s body with `Mutex`**

In `Sources/duaswift/Progress.swift`, replace the `ProgressCounter` class (original lines 8–27) with:

```swift
import Synchronization

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
```

Keep the existing `import Foundation` / `import Darwin` at the top of the file; add `import Synchronization` alongside them (move the `import Synchronization` shown above to the file's import block rather than mid-file).

- [ ] **Step 4: Run the counter tests + full build**

Run: `swift test --filter ProgressCounterTests`
Expected: PASS.

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 5: Commit**

```bash
git add Sources/duaswift/Progress.swift Tests/duaswiftTests/ProgressCounterTests.swift
git commit -m "refactor: ProgressCounter uses Synchronization.Mutex"
```

---

## Task 6: `ProgressMonitor` → `DispatchSourceTimer`

Replaces the raw `Thread`, the `runLock`/`running` bool, and the busy `usleep` loop with one repeating timer. The render logic moves into a small `Sendable` `ProgressRenderer` struct so the timer's `@Sendable` handler captures it instead of `self` (and the spinner frame is derived from elapsed time, removing the mutable `tick`).

**Files:**
- Modify: `Sources/duaswift/Progress.swift`

- [ ] **Step 1: Replace `ProgressMonitor` with the renderer + timer**

In `Sources/duaswift/Progress.swift`, replace the entire `ProgressMonitor` class (original lines 29–81) with:

```swift
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

    func begin() {
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
```

Notes:
- `Date` is `Sendable`; `ProgressRenderer` is a `Sendable` value, so both `setEventHandler` and `setCancelHandler` closures satisfy the `@Sendable` requirement without capturing `self`.
- The cancel handler is guaranteed to run after any in-flight event handler on the same serial `queue`, preserving "final line prints last."

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 3: Smoke-test progress visually**

Run: `swift run duaswift /usr/lib`
Expected: a spinning `scanning…` line on stderr that updates, then a single `✓ scanned … files · … in …s` final line, then the size table. (Run against a directory large enough to take a moment.)

- [ ] **Step 4: Full test suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/duaswift/Progress.swift
git commit -m "refactor: ProgressMonitor uses a DispatchSourceTimer (drop Thread/lock/semaphore loop)"
```

---

## Task 7: Encapsulate the work-stack into `DirectoryQueue`

**Files:**
- Create: `Sources/duaswift/DirectoryQueue.swift`

- [ ] **Step 1: Create the queue type**

`Sources/duaswift/DirectoryQueue.swift`:

```swift
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
```

- [ ] **Step 2: Build (type is not yet used)**

Run: `swift build`
Expected: builds successfully (the new file compiles; `DiskScanner` adopts it in Task 8).

- [ ] **Step 3: Commit**

```bash
git add Sources/duaswift/DirectoryQueue.swift
git commit -m "feat: add DirectoryQueue encapsulating the scan work-stack"
```

---

## Task 8: Adopt `DirectoryQueue` + `Mutex` inode set in `DiskScanner`

**Files:**
- Modify: `Sources/duaswift/Scanner.swift`

- [ ] **Step 1: Make `Accum` Sendable**

In `Sources/duaswift/Scanner.swift`, replace the `Accum` class (original lines 8–11) with:

```swift
/// Per-worker accumulator. A reference type so each worker can own one slot
/// and mutate it lock-free (no inout-across-threads). `@unchecked Sendable`:
/// each instance is owned by exactly one worker for the duration of a scan
/// (single-writer invariant), so the `accums` array can cross into
/// `concurrentPerform` under strict concurrency checking.
final class Accum: @unchecked Sendable {
    var size: Int64 = 0
    var entries: Int = 0
}
```

- [ ] **Step 2: Replace the inode lock with a `Mutex`**

In `DiskScanner`, replace the inode-dedup state (original lines 44–48):

```swift
    private let cond = NSCondition()
    private var dirStack: [String] = []
    private var pending = 0

    private struct INode: Hashable { let dev: Int32; let ino: UInt64 }
    private let inodeLock = NSLock()
    private var seen = Set<INode>()
```

with:

```swift
    /// Hard-link de-dup: only consulted for regular files with > 1 link, so the
    /// lock is essentially uncontended on normal trees.
    private struct INode: Hashable { let dev: Int32; let ino: UInt64 }
    private let seen = Mutex(Set<INode>())
```

(The `cond`/`dirStack`/`pending` properties are removed — that state now lives in a per-scan `DirectoryQueue`.)

- [ ] **Step 3: Add `import Synchronization`**

At the top of `Sources/duaswift/Scanner.swift`, add `import Synchronization` to the import block.

- [ ] **Step 4: Update `accumulate` to use the `Mutex`**

In `accumulate(_:into:)`, replace the inode-dedup block (original lines 61–66):

```swift
        if !countHardLinks && fmt == UInt32(S_IFREG) && st.st_nlink > 1 {
            let key = INode(dev: st.st_dev, ino: st.st_ino)
            inodeLock.lock()
            let isNew = seen.insert(key).inserted
            inodeLock.unlock()
            if !isNew { return }
        }
```

with:

```swift
        if !countHardLinks && fmt == UInt32(S_IFREG) && st.st_nlink > 1 {
            let key = INode(dev: st.st_dev, ino: st.st_ino)
            let isNew = seen.withLock { $0.insert(key).inserted }
            if !isNew { return }
        }
```

- [ ] **Step 5: Rewrite `workerLoop` to take a queue**

Replace `workerLoop` (original lines 94–122) with:

```swift
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
```

- [ ] **Step 6: Rewrite `scan` to build a per-scan queue**

Replace `scan(_:)` (original lines 124–153) with:

```swift
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
```

- [ ] **Step 7: Confirm `DiskScanner` is `Sendable`-clean**

`DiskScanner`'s remaining stored properties are all immutable `let`s (`apparent`, `countHardLinks`, `threadCount`, `progress`) plus the `Mutex`-wrapped `seen`. Add the conformance to the class declaration:

```swift
final class DiskScanner: Sendable {
```

(The `self` captured by `concurrentPerform`'s `@Sendable` closure now requires this; it holds because every stored property is `Sendable`.)

- [ ] **Step 8: Build**

Run: `swift build`
Expected: builds successfully.

- [ ] **Step 9: Re-run the characterization tests (the safety net)**

Run: `swift test --filter DiskScannerTests`
Expected: PASS — behavior unchanged by the refactor.

Run: `swift test`
Expected: PASS — entire suite green.

- [ ] **Step 10: Commit**

```bash
git add Sources/duaswift/Scanner.swift
git commit -m "refactor: DiskScanner uses DirectoryQueue and Mutex inode set"
```

---

## Task 9: Turn on Swift 6 language mode

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Remove the staged Swift 5 mode from both targets**

In `Package.swift`, delete the `swiftSettings: [.swiftLanguageMode(.v5)]` lines from **both** the `duaswift` executable target and the `duaswiftTests` test target (and the now-trailing comma / comment). With `swift-tools-version:6.2`, targets default to Swift 6 language mode, so strict data-race checking is now on.

The `duaswift` target becomes:

```swift
        .executableTarget(
            name: "duaswift",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/duaswift"
        ),
```

and the test target:

```swift
        .testTarget(
            name: "duaswiftTests",
            dependencies: ["duaswift"],
            path: "Tests/duaswiftTests"
        ),
```

- [ ] **Step 2: Build under Swift 6 strict checking**

Run: `swift build`
Expected: builds successfully with no concurrency diagnostics. The pieces that make this hold: `ProgressCounter`/`DiskScanner` are `Sendable` via `Mutex`-wrapped state and `let`s; `DirectoryQueue` and `Accum` are `@unchecked Sendable` with documented single-owner/lock invariants; `ProgressMonitor`'s timer closures capture the `Sendable` `ProgressRenderer`, not `self`.

If any diagnostic appears, fix it at its source (do not silence with broad `@unchecked`): the expected shape of any straggler is a closure capturing non-`Sendable` state — resolve by capturing a `Sendable` value instead, as the monitor does.

- [ ] **Step 3: Full test suite under Swift 6 mode**

Run: `swift test`
Expected: PASS — all tests (`ScaffoldTests`, `FormattingTests`, `DiskScannerTests`, `ProgressCounterTests`).

- [ ] **Step 4: Final CLI smoke test**

Run: `swift run duaswift` (no args, in the repo root)
Expected: lists each entry of the current directory with sizes, ascending, plus a `total` line.

Run: `swift build -c release`
Expected: release build succeeds under Swift 6 mode.

- [ ] **Step 5: Remove the scaffold test**

Delete `Tests/duaswiftTests/ScaffoldTests.swift` (it was only there to bootstrap the test target).

Run: `swift test`
Expected: PASS — remaining suites green.

- [ ] **Step 6: Commit**

```bash
git rm Tests/duaswiftTests/ScaffoldTests.swift
git add Package.swift
git commit -m "build: enable Swift 6 language mode (strict concurrency) for duaswift"
```

---

## Self-Review Notes

- **Spec coverage:** manifest/dep (Task 1), flags + `ByteFormat` + help deletion (Tasks 3–4), `ProgressCounter` Mutex (Task 5), `ProgressMonitor` timer (Task 6), `DirectoryQueue` + inode Mutex + `Accum` Sendable (Tasks 7–8), formatting moved to a testable file (Task 3), test target + scanner/formatting/counter tests (Tasks 1–8), Swift 6 mode (Task 9). All spec sections map to a task.
- **`renderSize` signature:** defined as `renderSize(_:format:)` in Task 3 and called as `renderSize(_:format:)` in Tasks 4 and 6 — consistent.
- **`DirectoryQueue` API:** `init(root:)`, `pop() -> String?`, `push(_:)`, `finishOne()` defined in Task 7 and used with those exact names in Task 8.
- **Build-green staging:** Task 3 Step 5 leaves `main.swift` temporarily uncompilable; the plan calls this out and pairs it with Task 4 (and gates the green checkpoint on `swift test --filter FormattingTests`). Every other task ends on a green `swift build`/`swift test`.
```
