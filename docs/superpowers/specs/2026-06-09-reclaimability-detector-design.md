# Evidence-based reclaimability detector — design

**Date:** 2026-06-09
**Status:** Approved, ready to plan

## Problem

Reclaimable directories are currently identified by a hand-curated name switch in
`DiskKit/Classifier.swift` (`node_modules`, `Caches`, `.next`, …). A name list is
both **incomplete** — every new tool's cache dir is invisible until someone adds
it — and **weak on safety**: a user folder literally named `build` or `cache` gets
flagged with zero evidence it is regenerable. Since real move-to-Trash purging is
on the roadmap, false positives mean lost user data, so the bar must go *up*.

## Approach

Flag on **evidence of regenerability**, not names alone, from three signal tiers,
and carry a **confidence + reason** on every flag so a future purge flow can
require strong evidence and explain itself.

Decisions taken during design:
- Signals in v1: **CACHEDIR.TAG + manifest evidence + curated fallback** (no
  `isExcludedFromBackup` yet).
- Detection drives **both** a folder's category *and* its reclaim mark.
- Real purging is planned → **strict**: ambiguous evidence stays medium, and a
  confidence level is carried for a later delete gate.

## 1. Data model (`DiskKit`)

Replace `DirNode.isReclaimable: Bool` with an optional, self-describing mark:

```swift
public enum ReclaimSignal: Sendable {
    case cachedirTag                 // verified CACHEDIR.TAG inside the dir
    case manifest(String)            // regenerable by a sibling, e.g. "package.json"
    case knownName                   // curated name match
}
public enum ReclaimConfidence: Sendable { case high, medium }
public struct ReclaimMark: Sendable {
    public let confidence: ReclaimConfidence
    public let signal: ReclaimSignal
    public let reason: String        // human-readable, for the purge UI
}
```

`DirNode.reclaim: ReclaimMark?` (nil = keep). A computed
`var isReclaimable: Bool { reclaim != nil }` keeps existing *read* consumers
working unchanged:
- `Derive.reclaimBytes` / `Derive.reclaimRoots` (use `isReclaimable`)
- `Derive.typeReclaim` (groups reclaim roots by category)
- `RailView` "free" badges, `ScanModel.reclTotal` / `reclaimTargets`

**Construction ripple.** `DirNode.init` changes from `isReclaimable: Bool` to
`reclaim: ReclaimMark?`. Call sites that build nodes without real detection — the
streaming **placeholders** in `TreeScanner.scanStreaming`, `ScanModel.rebuildRoot`,
`MockTree`, and `ScanModelTests` — are updated. To keep those terse, `DirNode` also
gets a convenience initializer taking `isReclaimable: Bool` that maps `true` → a
generic `ReclaimMark(.high, .knownName)` and `false` → `nil`. Placeholders pass
`nil` (they are never reclaimable).

A future move-to-Trash flow reads `reclaim.confidence` / `reason` and can require
`.high`.

## 2. The detector — three tiers, strongest first

- **CACHEDIR.TAG (high).** A directory containing a `CACHEDIR.TAG` file whose
  contents begin with the standard `Signature: 8a477f597d28d172789f06886806bc55`
  (per <https://bford.info/cachedir/>; written by Cargo, honored by backup tools).
  The signature is **verified** (read ~43 bytes), not just the filename. →
  category `.cache`, reclaimable. Zero-maintenance; catches tools we don't know.
- **Manifest evidence (high).** A regenerable directory *with its rebuilder
  present beside it*:
  - `node_modules` ↔ `package.json`
  - `target` ↔ `Cargo.toml`
  - `Pods` ↔ `Podfile`
  - `.venv` / `venv` / `__pycache__` ↔ `pyproject.toml` / `requirements.txt` / `setup.py`
  - `build` / `.gradle` ↔ `build.gradle` / `settings.gradle`
  - `vendor` ↔ `go.mod` / `composer.json`
  - `dist` / `.next` / `out` ↔ `package.json`
- **Curated name fallback (high or medium).** For reclaimable dirs with no local
  manifest (system caches, trash, derived data):
  - **Unambiguous** names (`node_modules`, `.venv`, `site-packages`,
    `DerivedData`, `.Trash`, `.next`, `.turbo`, `Pods`) → **high**.
  - **Ambiguous** names that could be real user data (`build`, `dist`, `out`,
    `target`, `cache`, `Caches`, `.cache`, `vendor`) → **medium**, *elevated to
    high* when a marker or manifest corroborates.

The curated list survives, but as a *fallback* split by name ambiguity — the
day-to-day flagging is evidence-driven. Detection sets category too (a CACHEDIR.TAG
dir is `.cache`; a `Cargo.toml`-backed `target` is `.build`), preserving the
existing `overridesChildren` rollup (a reclaim root's whole subtree attributes to
its category and is not separately descended).

**Signal precedence.** A directory can match more than one tier — Cargo writes
`CACHEDIR.TAG` *into* `target/`, which also matches the `Cargo.toml`+`target`
manifest rule. For **confidence**, take the strongest (both are high here). For
**category**, the more specific signal wins: **manifest > CACHEDIR.TAG > name**
(so `target` reads as `.build`, not the generic `.cache`). The `reason` records
the signal that set the category.

## 3. Scan integration — classification moves into `list()`

Today `Classifier.classifyDir(name)` runs in `BuildNode.init`, when a *parent
discovers a child by name* — too early for the new signals, which need a dir's
**own contents** (`CACHEDIR.TAG`) and its **siblings** (manifests sit next to the
dir they regenerate). Classification therefore moves into `TreeScanner.list()`.

Per directory, `list()` now:
1. one readdir pass → file bytes (as today) **+** the set of **manifest
   filenames** present **+** whether a `CACHEDIR.TAG` entry exists;
2. finalize *this* node's `category` / `filesAs` / `reclaim` from its `name` + the
   **hint its parent passed at creation** + its own `CACHEDIR.TAG` (signature
   verified here, only if the entry exists);
3. create children, each carrying a `hint` computed from the manifest set just
   seen (e.g. saw `package.json` → the `node_modules` child's hint is
   `manifest("package.json")`).

**Single-writer invariant preserved.** Each node's classification is written
exactly once, by its own lister. The parent contributes only an *immutable hint*
at child creation (exactly like `inherited` today), published across threads by
the existing `NodeQueue` barrier. `BuildNode` changes:
- gains an immutable `hint` (parent-supplied evidence),
- its `category` / `filesAs` / `reclaim` become **set once in `list()`** instead
  of at `init`. `filesAs` is finalized in step 2, before step 3 needs it for
  children's `inherited`.

**Cost** is negligible: the CACHEDIR.TAG name-check and manifest spotting happen
in the readdir loop already running; the signature read fires only when a
`CACHEDIR.TAG` entry actually appears (rare). Streaming and blocking scans stay
byte-identical in size; only classification gains precision.

## 4. Testing

Pure detector (no filesystem):
- ambiguous name alone → medium; + matching manifest → high; + valid
  `CACHEDIR.TAG` → high.
- unambiguous name alone → high.
- an **invalid** CACHEDIR.TAG signature → **not** flagged.
- category is set by the winning signal (CACHEDIR.TAG → `.cache`, `Cargo.toml`+
  `target` → `.build`).

Temp-tree integration (extends `TreeScannerTests`):
- `package.json` + `node_modules` → node_modules `.high` via `.manifest`.
- lone `node_modules` (no manifest) → `.high` via `.knownName` (unambiguous).
- lone `build` (no manifest) → `.medium`.
- `Cargo.toml` + `target/` containing a real `CACHEDIR.TAG` → `.high`.
- reclaim totals (`Derive.reclaimBytes`) and tree sizes unchanged vs. today for a
  tree with no new signals.

## 5. Scope boundary

This spec delivers the **detection + data model** and surfaces
`confidence`/`reason`. The actual move-to-Trash UI and the "require high
confidence" delete gate are a **separate future spec** — this work only makes that
flow possible and safe.

## Files touched

`DiskKit/DirNode.swift` (reclaim mark + computed `isReclaimable`), new
`DiskKit/Reclaim.swift` (the signal/confidence/mark types), `DiskKit/Classifier.swift`
(evidence-based detector + child-hint helper), `DiskKit/TreeScanner.swift`
(`BuildNode.hint`, classification in `list()`), plus `Tests/DiskKitTests`.
The Halo UI is unchanged except wherever it may later choose to show
confidence/reason (out of scope here).
