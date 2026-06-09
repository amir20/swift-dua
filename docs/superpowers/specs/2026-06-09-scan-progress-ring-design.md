# Scan progress ring — design

**Date:** 2026-06-09
**Status:** Shipped as an **indeterminate** activity ring (see Revision below)

## Revision — indeterminate, not a percentage

The first cut drove the ring from a **directories-drained** fraction
(`dirsDone / dirsFound`). On a real home directory this proved misleading:
`~` is thousands of tiny directories (every `node_modules`, cache, etc.) plus a
handful of *enormous* files (`.ollama` 25 GB, …). Directory count completes long
before the bytes/time do, so the fraction raced to ~99% and the display rounded
it to a flat **"100%"** while the scan was still grinding — a worse experience
than no bar.

A true byte-percentage is impossible to show early (the total isn't known until a
full walk finishes; `du` is just a second, slower walk). Rather than fake it, the
ring is now **indeterminate**: a short blue arc that rotates continuously while a
scan runs, conveying *activity* without claiming progress. The live byte + file
counter in the donut's center carries the real "how far along" signal.

All the DiskKit counter machinery from the first cut (`dirsDone`/`dirsFound`,
`addDirs`, the seeding in `TreeScanner`) was **reverted** — an indeterminate ring
needs no scanner changes. What shipped:

- `Halo/ScanModel.swift` — `showRing: Bool`, revealed by a 0.3s delay timer
  (so quick scans never flash it), faded out in `finishScan`.
- `Halo/DonutView.swift` — `progressRing`: a `TimelineView(.animation)`-driven
  `Circle().trim(...).stroke(lineCap: .round)` at radius ~115 (hugging the hole
  edge), rotated continuously; shown only while `showRing`.
- `Halo/Palette.swift` — `Palette.progress` blue (kept).

The original directory-drain design is preserved below for the record.

---

**Original status:** Approved, implementing

## Goal

Show live progress while a directory is being scanned, rendered as a thin **blue
inner arc** that hugs the inside edge of the donut and sweeps 0 → 100% as the
scan proceeds. The center readout keeps showing live bytes, with the percent
folded into the subtitle.

## Why not `du`

The original idea was to run `du -sh` for a denominator and show
`bytesScanned / duTotal`. Rejected: on APFS there is no stored directory size, so
a byte total is only knowable by walking the whole tree. `du` is a *second*,
single-threaded walk on top of Halo's own parallel walk, so its number arrives
*after* Halo's scan has already finished — extra I/O for a value that lands a
beat too late. It cannot be made fast.

## Chosen source — directories drained

The scanner already pulls directory nodes off a shared work-stealing queue. We
track two monotonic counters and drive the arc from their ratio:

- `dirsFound` — directories ever discovered (enqueued for listing)
- `dirsDone` — directories whose listing has finished

`progress = dirsDone / dirsFound`, available live from `t=0` at zero extra
filesystem cost. It is a folder-count estimate (not bytes), but it is smooth,
free, and converges to exactly 1.0.

## Components

### 1. `DiskKit/ScanProgress.swift`

Extend the existing lock-guarded state from `(files, bytes)` to
`(files, bytes, dirsDone, dirsFound)`. Keep `add(files:bytes:)`. Add:

```swift
func addDirs(done: Int, found: Int)   // one lock, bumps both counters
```

`snapshot()` returns the 4-tuple (named fields, so existing `s.files`/`s.bytes`
readers are unaffected).

### 2. `DiskKit/TreeScanner.swift`

Counting rule — every directory is *found once* and *done once*; the root is
discovered at launch:

- Seed `addDirs(done: 0, found: 1)` at the start of **both** `scan` and
  `scanStreaming` (the root counts as the first discovered directory).
- After each node is processed (the synchronous `list(root)` in streaming, and
  every node popped in the worker loops of `scanStreaming` and `drain`), call
  `addDirs(done: 1, found: node.children.count)`.

The done bump lives in the **worker loop**, not inside `list()`, so a directory
that fails `opendir` (permission denied) still counts as done with zero children
— otherwise unreadable dirs would leave progress stuck below 100%.

Result at completion: `dirsDone == dirsFound ==` total directory count, so the
ratio is exactly 1.0.

### 3. `Halo/ScanModel.swift`

- `liveProgress: Double` (0…1) — updated by the existing 0.1s poll timer via a
  pure, testable free function:

  ```swift
  func clampedProgress(previous: Double, done: Int, found: Int) -> Double
  ```

  **Monotonic:** never decreases. Early in a scan, discovery outruns completion
  so the raw ratio dips; the displayed value holds (the ring pauses rather than
  reverses). Clamped to [0, 1]. Returns `previous` when `found == 0`.

- `showRing: Bool` — gated by a **0.3s non-repeating delay timer** started at
  scan begin. If the scan finishes first (small folder), the timer is
  invalidated and the ring never appears → no flash on fast scans.

- On `finishScan`: invalidate both timers, animate `liveProgress → 1.0`, and
  fade `showRing → false` so the ring completes then dissolves as the real
  wedges take over. Both reset on each new `scan()`.

### 4. `Halo/DonutView.swift`

- New layer above `hole`: a thin filled wedge via the existing `ArcShape`, radii
  **113 → 118** (just inside `r0 = 122`, over the hole edge), from `-π/2`
  sweeping `liveProgress · 2π`, filled `Palette.progress`. Shown only when
  `showRing`, with `.transition(.opacity)` and `.animation(value: liveProgress)`
  to smooth the 0.1s steps. At progress 0 the arc is empty (ArcShape draws
  nothing), which is correct.
- Subtitle while scanning: `scanning… {pct}% · {files} files`. Big number stays
  live bytes.

### 5. `Halo/Palette.swift`

Add `static let progress = Color(oklch: 0.62, 0.16, 256)` — a clear blue,
authored in oklch like the rest of the palette, distinct from the muted category
blues and the amber reclaim arc.

## Testing

The ring's visuals/fade stay human-verified (GUI can't be smoke-tested), but the
logic is unit-tested:

- **`HaloTests`** — `clampedProgress`: monotonic (holds when the raw ratio dips),
  clamps to [0, 1], returns `previous` when `found == 0`, equals 1 when
  `done == found` (and when `done > found`).
- **`DiskKitTests`** — scan a temp dir tree of known directory count; assert the
  final snapshot has `dirsDone == dirsFound ==` that count, so the ring reaches
  exactly 100%. Include an unreadable (chmod 000) subdirectory to prove progress
  still completes.

## Files touched

`ScanProgress.swift`, `TreeScanner.swift`, `ScanModel.swift`, `DonutView.swift`,
`Palette.swift`, plus `DiskKitTests.swift` and `ScanModelTests.swift`.
