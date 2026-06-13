# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Halo** — a native SwiftUI disk-space visualizer for macOS. It scans a directory tree, classifies what's using space, and renders an interactive donut with two lenses (**by folder** / **by type**) plus a synced breakdown sidebar. Built on **DiskKit**, a small library that does the parallel filesystem walk and builds a classified tree.

Pure SwiftPM package with exactly **one external dependency: Sparkle** (auto-update), linked into the Halo target only — DiskKit has none. Targets **macOS 26+ / Swift 6.2 (Xcode 26)** and builds in **Swift 6 language mode with strict data-race checking**.

## Commands

A `Makefile` is the front door — run `make` to list targets.

```sh
make build   # release build of the Halo binary (swift build -c release --product Halo)
make test    # swift test
make run     # build & launch the app from source
make app     # -> Halo.app  (release binary + Info.plist + icon + ad-hoc signature)
make dmg     # -> Halo.dmg  (drag-to-install; depends on `app`)
make icon    # regenerate Icons/AppIcon.icns (only if Icons/make-icon.swift changed)
make clean
```

Run a single test by `Suite/test` or by suite:

```sh
swift test --filter HaloTests.ScanModelTests/testDonutHoverHitsTheArcUnderTheCursor
swift test --filter DiskKitTests          # whole target
```

The app bundle is produced by the `bundle-app` **package plugin** (not a script): `make app` runs `swift package --disable-sandbox --allow-writing-to-package-directory bundle-app Halo`. The plugin builds release, writes a **binary** `Info.plist` via `PropertyListSerialization` (stamping `VERSION`, default `0.0.0`, plus Sparkle's `SUFeedURL`/`SUPublicEDKey`), copies `Icons/AppIcon.icns`, embeds `Sparkle.framework` into `Contents/Frameworks` (adding the `@executable_path/../Frameworks` rpath), **re-signs Sparkle's nested XPC services/Autoupdate/Updater.app deepest-first** (library validation under the hardened runtime requires nested code signed by our team), then signs the app. CI (`.github/workflows/ci.yml`, macos-26 runner) builds + tests and uploads `Halo.dmg` as an artifact on every push/PR.

**Auto-update (Sparkle).** Installed apps poll `SUFeedURL` = `https://github.com/amir20/Halo.app/releases/latest/download/appcast.xml`. The CI `release` job (on `v*` tags) EdDSA-signs the notarized DMG with `sign_update` (key from the `SPARKLE_PRIVATE_KEY` secret; tools ship inside the Sparkle SPM artifact under `.build/artifacts/sparkle/Sparkle/bin/`) and attaches a single-item `appcast.xml` to the release — `releases/latest/download/` keeps the feed current with no hosting. The updater only starts when running from a real `.app` bundle, so `swift run`/tests are unaffected.

> The GUI is a SwiftUI `App`, so it can't be smoke-tested headlessly here — hover/visual behavior must be verified by a human running the app. Logic that *can* be tested lives in `HaloTests` (the executable target is `@testable`-importable).

## Architecture

Two modules: **DiskKit** (scan engine + model, no UI) and **Halo** (SwiftUI, depends on DiskKit). The data flows scanner → `DirNode` tree → `ScanModel` (view-model) → views.

### Scanning (`DiskKit/TreeScanner.swift`)
Parallel walk over a single shared `NodeQueue` (LIFO stack + pending counter guarded by `NSCondition`) with N workers via `DispatchQueue.concurrentPerform`. **All directories share one queue** — this is deliberate, so a single huge subtree (`~/Library`, a giant `node_modules`) can't bottleneck the scan. Workers fill a mutable `BuildNode` tree (each node written by exactly one worker — the single-writer invariant behind its `@unchecked Sendable`), which is frozen into the immutable `DirNode` tree at the end. The walk counts hard-linked inodes once (like `du`), never crosses onto another device (mount points/firmlinks), and counts unreadable dirs in `ScanProgress.skipped` so the UI can disclose the blind spot.

`scanStreaming` is what the GUI uses: it reports the root with size-0 **placeholder** children immediately, then reports each top-level subtree via `onChild` the moment it finishes (tracked by `SubtreeTracker`'s per-subtree pending counts). A `ScanToken` cancels the walk cooperatively (it drains the queue; `onDone` still fires). `scan` is the blocking whole-tree variant (tests). Both produce byte-identical trees.

### The model (`Halo/ScanModel.swift`) — read this first
`@MainActor @Observable` view-model. **Critical invariant:** the scope-derived properties — `segments`, `arcs`, `reclTotal`, `reclaimTargets`, `expandedLocations` — are **stored**, rebuilt by `refresh()` only when the *scope* changes (`root` / `path` / `mode`, i.e. wherever `sweepKey` is bumped). They are **not** recomputed on `hover`/`expanded`. This is a performance fix: the `Derive` functions are O(subtree), and the views read these inside animated bodies that re-run on every hover/animation frame. **Do not turn them back into computed properties or recompute them on hover.** `focus` stays computed because it's a cheap lookup over cached `segments`.

`scan(path:)` launches `TreeScanner.scanStreaming` on a detached task; its callbacks feed one `AsyncStream<ScanEvent>` consumed in order by a single main-actor task (`installRoot`/`applyChild`/`finishScan`) — per-event unstructured `Task` hops had no ordering guarantee. A new scan **supersedes** an in-flight one: the old walk's `ScanToken` is cancelled and the epoch bump makes its queued events no-ops. Reclaim prunes trashed subtrees out of the tree locally (`Derive.removing`) instead of rescanning. Zero-size children are filtered out of `segments` so streaming placeholders / empty dirs are never shown or hoverable.

### Donut interaction (`Halo/DonutView.swift`)
Hover is resolved **by geometry**: `hitTestArc` maps the cursor's angle to the arc under it, handled once at the `DonutView` level via `onContinuousHover`; slices are `allowsHitTesting(false)`. This replaced per-slice `.onHover`, whose tracking area covered each slice's *full frame* (not its wedge), so the topmost (smallest) slice swallowed every hover. **Don't reintroduce per-slice `.onHover`.** `hitTestArc` is a free function kept pure so it's unit-tested without a live view.

### Scope overview (`Halo/SummaryService.swift`, `SummaryCard.swift`)
A plain-language overview of the current folder, shown at the top of the rail, generated **on-device** by Apple's Foundation Models framework (`import FoundationModels` — a system framework on macOS 26, *not* an SPM dependency, so the "one external dependency" rule still holds). It's deliberately **invisible plumbing**: no button and no AI branding in the UI. `ScanModel.refresh()` auto-kicks `generateSummary()` whenever a scope settles (`!scanning`, non-empty segments); the request runs against `summaryFacts()` — a pure, testable digest of exactly the figures the rail already shows, so the model can never cite a number the user can't see. Guided generation fills a `@Generable SpaceInsight` (headline + reclaim tip). `summaryEpoch` drops results from a scope the user has since left. When the model is unavailable or generation fails, the state stays `.idle` and the rail shows **nothing** — the feature only ever surfaces a finished summary. `summaryFacts` is the only part unit-tested; the model itself can't run headlessly.

### Other DiskKit pieces
- `DirNode` — the tree stores **directories only**; each node aggregates the bytes of files directly inside it, bucketed by `FileCategory` (`fileBytes`). `size` is the bottom-up subtree total. `@unchecked Sendable` (built on a background thread, immutable after).
- `Classifier` — rule-based dir/file → `FileCategory`; flags regenerable dirs (`node_modules`, `Caches`, `DerivedData`, `.Trash`, …) reclaimable, some overriding all descendants' category.
- `Derive` — pure, O(subtree) tree derivations (`reclaimBytes`, `typeSizes`, `typeLocations`, …). The reason `ScanModel` caches.
- `Palette` (Halo) — colors authored in **oklch** and converted to sRGB in code; the same conversion drives the app icon generator (`Icons/make-icon.swift`).

## Conventions

- **Strict concurrency.** Cross-thread types use `@unchecked Sendable` justified by a documented single-writer or lock invariant (`DirNode`, `BuildNode`, `NodeQueue`, `SubtreeTracker`). `@Sendable` closures can't capture mutable `var`s — collect through a `Sendable` reference type (see `StreamSink` in the tests). Follow these patterns rather than reaching for `nonisolated(unsafe)`.
- **macOS 26 Liquid Glass** APIs are in use (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`). The v26 SDK build is the only validation — there's no fallback path.
- Commits are signed via 1Password (`op-ssh-sign`); a commit may need an interactive approval you can't trigger headlessly.
