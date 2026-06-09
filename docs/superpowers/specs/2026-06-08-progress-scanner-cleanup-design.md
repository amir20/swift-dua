# duaswift cleanup: modern concurrency primitives + declarative flags

**Date:** 2026-06-08
**Status:** Approved (design); pending spec review

## Goal

Clean up the `duaswift` target by removing hand-assembled concurrency
primitives and hand-rolled argument parsing, using the latest Swift toolchain
and idioms. Behavior of the tool (output, scan semantics) is unchanged — this
is a refactor, not a feature change.

## Scope

In scope (the `duaswift` target only):

- `main.swift` — replace hand-rolled flag parsing with swift-argument-parser.
- `Progress.swift` — `ProgressCounter` and `ProgressMonitor` cleanup.
- `Scanner.swift` — encapsulate the work-stack condition variable; swap the
  inode-dedup lock for `Mutex`.
- Add a test target (none exists today).

Out of scope:

- The separate `ProgressApp` target — left untouched.
- Any change to scan semantics, output formatting, or CLI surface (same flags,
  same results).
- Full async/await / `TaskGroup` rewrite of the scanner (explicitly rejected —
  blocking `opendir`/`readdir`/`lstat` syscalls do not belong on the
  cooperative thread pool, and actor hops on the per-directory hot path risk a
  performance regression for a tool whose whole job is fast scanning).

## Environment (verified)

- Swift toolchain: **6.3.2** (installed; used automatically).
- macOS / SDK: **26.5**.
- swift-argument-parser latest: **1.8.2** (requires Swift 6).
- `Synchronization` module (`Mutex`, `Atomic`): available (floor macOS 15).

## Decisions

- **Approach:** modernize the synchronization primitives while keeping the
  proven GCD `concurrentPerform` parallel model. (Approaches considered: full
  structured-concurrency rewrite — rejected for the perf/anti-pattern reasons
  above; minimal Progress-only — rejected, under-delivers on chosen scope.)
- **Deployment floor:** `.macOS(.v26)` (personal tool, run locally; no
  functional gain vs. 15 but matches the machine and is "maximally latest").
- **Language/tools version:** `swift-tools-version:6.0`, which enables Swift 6
  language mode (strict data-race checking on). The toolchain itself is 6.3.2.
- **`@unchecked Sendable`** is acceptable in exactly two encapsulated, commented
  spots (`DirectoryQueue`, `Accum`), each with a one-line invariant. Preferred
  over scattering `nonisolated(unsafe)`.

## Design by component

### 1. Package manifest

- `swift-tools-version:6.0`.
- `platforms: [.macOS(.v26)]`.
- Add `.package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2")`.
- Link `ArgumentParser` product into the `duaswift` target only.
- Add a test target `duaswiftTests` depending on `duaswift`.
- `ProgressApp` target and the `BundleApp` plugin unchanged.

### 2. `main.swift` → `ParsableCommand`

Replace the `while`/`switch` parse loop and the `helpText` string with a
declarative command. The hand-rolled help text is deleted (argument-parser
generates `--help`).

```swift
import ArgumentParser

enum ByteFormat: String, ExpressibleByArgument { case metric, bytes }

@main
struct Duaswift: ParsableCommand {
    @Flag(name: [.customShort("A"), .long],
          help: "Use apparent size (st_size) instead of disk usage")
    var apparentSize = false

    @Flag(name: [.customShort("l"), .long],
          help: "Count hard-linked files each time they are seen")
    var countHardLinks = false

    @Option(name: [.short, .long], help: "Worker threads (default: logical CPU count)")
    var threads = ProcessInfo.processInfo.activeProcessorCount

    @Option(name: [.short, .long], help: "Byte format: metric or bytes")
    var format: ByteFormat = .metric

    @Flag(name: .customLong("no-progress"), help: "Disable the live progress line on stderr")
    var noProgress = false

    @Argument(help: "Paths to aggregate (default: entries of the current directory)")
    var paths: [String] = []

    func run() throws { /* existing run logic, made flag-explicit */ }
}
```

- `threads` is clamped with `max(1, threads)` inside `run()` (argument-parser
  has no min-value validator we need; a one-line clamp preserves current
  behavior). Invalid non-integer input is rejected by the parser automatically.
- `format` as an `enum: ExpressibleByArgument` gives free validation + a clear
  error on bad values, replacing the silently-ignored bad `--format` today.
- The "no paths → list current directory" fallback stays, moved into `run()`.
- Formatting helpers (`formatMetric`, `renderSize`, `leftPad`, `grouped`,
  `truncatePath`) stay, but `renderSize` takes the `ByteFormat` explicitly
  instead of reading a global `format` var. `formatMetric` is unchanged.
- Program stays **synchronous** (`run()` is sync); the scan still drives
  `concurrentPerform`.

### 3. `ProgressCounter` → `Mutex`

```swift
import Synchronization

final class ProgressCounter: Sendable {
    private struct State { var files = 0; var bytes: Int64 = 0; var current = "" }
    private let state = Mutex(State())

    func update(files: Int, bytes: Int64, current: String) {
        state.withLock { $0.files += files; $0.bytes += bytes; $0.current = current }
    }
    func snapshot() -> (files: Int, bytes: Int64, current: String) {
        state.withLock { ($0.files, $0.bytes, $0.current) }
    }
}
```

`Mutex` is `Sendable`, so the class is cleanly `Sendable` with no `@unchecked`.
No behavior change.

### 4. `ProgressMonitor` → `DispatchSourceTimer`

Delete the raw `Thread`, the `runLock`/`running` bool, and the
`DispatchSemaphore`. Replace with a repeating `DispatchSourceTimer` on a
dedicated serial queue.

- `begin()` schedules the timer (80 ms repeating); each fire calls `render(tick)`.
- `finish()` calls `timer.cancel()` and waits for the timer's cancel handler to
  run `renderFinal()` exactly once, then returns — preserving the current
  guarantee that the final line is printed before `finish()` returns. A single
  `DispatchSemaphore` *may* be retained solely to await the cancel handler if
  that is the simplest correct way to block until the final render completes;
  the `Thread`, `runLock`, and `running` bool are removed regardless. (Net:
  three hand-assembled primitives collapse to one timer + at most one
  one-shot wait.)
- `start` time, `frames`, `interval`, and both render functions are unchanged.

### 5. `Scanner.swift`

**Encapsulate the work-stack condition variable** into a single-purpose unit:

```swift
final class DirectoryQueue: @unchecked Sendable {   // @unchecked: NSCondition guards all mutable state
    private let cond = NSCondition()
    private var stack: [String]
    private var pending: Int

    init(root: String) { stack = [root]; pending = 1 }

    /// Blocks until a directory is available, or returns nil when the whole
    /// scan is finished (stack empty AND nothing pending). Wakes peers to exit.
    func pop() -> String?
    /// Adds discovered sub-directories and bumps the pending count.
    func push(_ dirs: [String])
    /// Marks the directory just processed as done.
    func finishOne()
}
```

`workerLoop` collapses to:

```swift
private func workerLoop(_ acc: Accum) {
    while let dir = queue.pop() {
        let before = (acc.entries, acc.size)
        let subdirs = processDirectory(dir, into: acc)
        progress?.update(files: acc.entries - before.0,
                         bytes: acc.size - before.1, current: dir)
        queue.push(subdirs)
        queue.finishOne()
    }
}
```

Note: ordering — `push` before `finishOne` so `pending` never transiently hits
zero while children are still being enqueued (preserves current correctness).

**Inode dedup** → `Mutex`:

```swift
private let seen = Mutex(Set<INode>())
// in accumulate():
let isNew = seen.withLock { $0.insert(key).inserted }
if !isNew { return }
```

`seen.withLock { $0.removeAll(keepingCapacity: true) }` at the top of `scan()`.

**`Accum`** gains `@unchecked Sendable` with a comment: each instance is owned
by exactly one worker for the duration of a scan (single-writer invariant),
which is what lets the `accums` array be captured by `concurrentPerform` under
Swift 6 strict checking.

`DiskScanner` stores `let queue` per-scan (constructed inside `scan()` rather
than as a mutable property, so the type stays `Sendable` without `@unchecked`).
The `apparent`/`countHardLinks`/`threadCount`/`progress` stored properties are
already immutable `let`s.

### Data flow (unchanged)

`Duaswift.run()` → builds `ProgressCounter?` + `ProgressMonitor?` →
`DiskScanner.scan(path)` per input → workers pull dirs from `DirectoryQueue`,
size entries into per-worker `Accum`, push children, report deltas to
`ProgressCounter` → monitor timer renders snapshots to stderr → results sorted
ascending and printed to stdout, grand total if >1 input.

### Error handling

- Unreadable directories / failed `lstat`: skipped, same as today.
- Bad flag values: now reported by argument-parser with a usage message and
  non-zero exit, instead of being silently ignored (`--format`) or partially
  handled.
- Non-existent root path: `scan` returns size 0 (unchanged).

## Testing

New target `Tests/duaswiftTests` (XCTest). TDD where practical (formatting and
fixture-based scanner tests written before/with the refactor):

- `grouped`: 0, 999, 1000, 1234567 → `"0"`, `"999"`, `"1,000"`, `"1,234,567"`.
- `formatMetric` / `renderSize`: boundary at 1000, `bytes` vs `metric` format.
- `truncatePath`: under, at, and over the max length.
- `ByteFormat` parsing: `"metric"`, `"bytes"` parse; junk fails.
- `DiskScanner` against a temp directory tree with known file sizes and a
  hard-linked file: verify dedup on/off (`countHardLinks`) and
  apparent-vs-disk sizing, plus nested-subdirectory aggregation. This exercises
  `DirectoryQueue`, the inode `Mutex`, and `Accum` indirectly.

Formatting helpers move to a location importable by tests (e.g. remain
top-level in the module; tests use `@testable import duaswift`). Because
`@main`/top-level-code files can't always be `@testable`-imported cleanly, the
pure helpers and `DiskScanner` must live in files **other than** the `@main`
entry file (they already do for the scanner; the formatting helpers in
`main.swift` move to a small `Formatting.swift` so they are testable).

## Risks / notes

- `DispatchSourceTimer` final-render coordination must guarantee exactly-once
  `renderFinal()` and a happens-before with `finish()` returning — covered by
  the cancel-handler + one-shot wait described above.
- Swift 6 strict-concurrency may surface additional `Sendable` requirements at
  build time; the two `@unchecked` escape hatches plus `Mutex`-wrapped state
  are expected to cover them, but the build is the source of truth.
- `from: "1.8.2"` pins a floor; `Package.resolved` will be committed.
