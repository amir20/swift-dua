import AppKit
import DiskKit
import SwiftUI

/// One ring slice / rail row in either lens.
struct Segment: Identifiable {
    let id: String
    let label: String
    let category: FileCategory
    let size: Int64
    let recl: Int64
    let node: DirNode?  // folder lens: the directory this slice represents
    let isType: Bool
    let drillable: Bool
    /// The slice/swatch color: a distinct per-folder hue in the folder lens, the
    /// semantic category color in the type lens. Resolved once at build time so
    /// the donut and rail always agree.
    let color: Color

    func recolored(_ c: Color) -> Segment {
        Segment(
            id: id, label: label, category: category, size: size, recl: recl,
            node: node, isType: isType, drillable: drillable, color: c)
    }
}

/// A `Segment` placed on the ring (angles in radians, 12 o'clock = -π/2).
struct Arc: Identifiable {
    let seg: Segment
    let a0: Double
    let a1: Double
    let gap: Double
    var id: String { seg.id }
}

enum Lens { case folder, type }

/// One scan callback, carried through an `AsyncStream` so the main actor
/// consumes them strictly in the order the scanner produced them (root →
/// children → done). Unstructured per-callback `Task` hops carried no ordering
/// guarantee — an early `child` could beat `root` and be dropped.
enum ScanEvent: Sendable {
    case root(DirNode)
    case child(Int, DirNode)
    case done
}

/// Summary of a completed reclaim, for a brief confirmation note. `trashed` and
/// `deleted` are kept apart because items already in the Trash are removed
/// permanently (not moved), so the note can say so honestly.
struct ReclaimOutcome {
    let trashed: Int
    let deleted: Int
    let failed: Int
}

/// One reviewable row in the reclaim confirmation dialog.
struct ReclaimItem: Identifiable {
    let id: ObjectIdentifier  // the source node's identity
    let name: String
    let url: URL
    let size: Int64
    let confidence: ReclaimConfidence
    /// Short evidence token (`package.json`, `CACHEDIR.TAG`, or the category).
    let signalLabel: String
    /// Full human justification, for a secondary line / tooltip.
    let reason: String
    /// Whether it starts checked — high-confidence targets do.
    let preselected: Bool
    /// True when the target is already in the Trash, so reclaiming it means a
    /// permanent delete (`removeItem`) — `trashItem` can't move trash to trash.
    let permanentDelete: Bool
}

@MainActor
@Observable
final class ScanModel {
    var root: DirNode?
    var path: [DirNode] = []
    var mode: Lens = .folder
    var hover: String?
    var expanded: FileCategory?
    var scanning = true
    var scanError: String?
    /// Bumped on every scope change to retrigger the donut's sweep animation.
    var sweepKey = 0
    /// Live counters polled from the scanner while a scan is in flight.
    var liveFiles = 0
    var liveBytes: Int64 = 0
    /// Directories the walk couldn't read (missing Full Disk Access, others'
    /// home dirs…). Disclosed so an incomplete picture is never silent.
    private(set) var skippedDirs = 0
    /// Whether the scanning activity ring is shown. Gated behind a short delay so
    /// a fast scan never flashes it.
    var showRing = false
    /// Whether the app holds Full Disk Access. Re-probed when the app becomes
    /// active. When false, the scan can't see inside other apps' data and macOS
    /// nags once per app, so a banner offers to grant it.
    var fullDiskAccess = FullDiskAccess.isGranted
    /// Set when the user dismisses the Full Disk Access banner this session.
    var fdaBannerDismissed = false
    /// Whether to surface the Full Disk Access banner: only when access is missing
    /// and the user hasn't waved it away.
    var showFDABanner: Bool { !fullDiskAccess && !fdaBannerDismissed }
    /// Monotonic scan progress estimate in 0...1. Drives the determinate progress
    /// ring and the Dock-icon bar. The walk's true size isn't known until it ends,
    /// so this is an estimate (see `ScanProgress.fractionDone`) — but it only ever
    /// moves forward.
    private(set) var scanFraction: Double = 0
    /// State of the auto-generated overview for the current scope. Reset whenever
    /// the scope changes (in `refresh()`), so a stale summary never lingers over
    /// a different folder. Generation is kicked off automatically — there is no
    /// user-facing control for it.
    private(set) var summaryState: SummaryState = .idle
    /// Bumped on every scope change; lets an in-flight summary request detect
    /// that its scope is gone and drop its result instead of overwriting a newer
    /// one (or a folder it no longer describes).
    private var summaryEpoch = 0
    /// The in-flight summary request, cancelled when a newer scope supersedes it
    /// so rapid drill-through never piles up concurrent on-device inferences.
    private var summaryTask: Task<Void, Never>?
    /// Drives the reclaim confirmation sheet.
    var showReclaimSheet = false
    /// Result of the most recent reclaim, for a brief footer note.
    var lastReclaim: ReclaimOutcome?
    /// Scope (folder names below root) to re-enter once the post-reclaim rescan
    /// finishes, so the user isn't bounced back to the root.
    private var pendingScopeNames: [String]?
    /// Reclaim outcome to surface once the post-reclaim rescan finishes (the
    /// rescan clears `lastReclaim`, so it's re-applied at the end).
    private var pendingReclaim: ReclaimOutcome?

    var current: DirNode? { path.last }

    /// Absolute filesystem path the scan was rooted at. Joined with the names of
    /// the navigated `path` to recover the real directory under the breadcrumb.
    private var scanRootPath = ""

    /// Name of the volume the scan root lives on (e.g. "Macintosh HD"), for the
    /// leading breadcrumb and the donut subtitle. `nil` for in-memory trees.
    private(set) var volumeName: String?
    var volumeLabel: String { volumeName ?? "this volume" }

    // Pieces kept so the root can be rebuilt as top-level subtrees stream in.
    private var rootName = "~"
    private var rootCategory: FileCategory = .other
    private var rootReclaim: ReclaimMark?
    private var rootFiles: [FileCategory: Int64] = [:]
    private var liveChildren: [DirNode] = []
    private var progress: ScanProgress?
    private var pollTimer: Timer?
    /// Fires once, 0.3s into a scan, to reveal the progress ring. Invalidated if
    /// the scan finishes first, so quick scans never show it.
    private var ringDelayTimer: Timer?
    /// Cancels the in-flight walk when a new scan supersedes it.
    private var scanToken: ScanToken?
    /// The single ordered consumer of the in-flight scan's events.
    private var scanConsumer: Task<Void, Never>?
    /// Bumped whenever a scan starts (or a tree is loaded), so events from a
    /// superseded scan are recognized and dropped.
    private var scanEpoch = 0

    // MARK: - Loading

    /// Streams a real scan: the donut appears immediately and fills in as each
    /// top-level subtree completes, with a live counter throughout. Starting a
    /// scan supersedes any in-flight one — its walk is cancelled and any events
    /// it still emits are dropped.
    func scan(path scanPath: String) {
        supersedeInFlightScan()
        scanRootPath = scanPath
        volumeName = try? URL(fileURLWithPath: scanPath)
            .resourceValues(forKeys: [.volumeNameKey]).volumeName
        scanning = true
        scanError = nil
        liveFiles = 0
        liveBytes = 0
        skippedDirs = 0
        showRing = false
        scanFraction = 0
        // Don't carry a prior reclaim's footer note into an unrelated scan; a
        // post-reclaim rescan re-applies it from `pendingReclaim` in finishScan.
        lastReclaim = nil
        let prog = ScanProgress()
        progress = prog
        ringDelayTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) {
            [weak self] _ in
            Task { @MainActor in
                guard let self, self.scanning else { return }
                withAnimation(.easeOut(duration: 0.25)) { self.showRing = true }
            }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let s = prog.snapshot()
                self.liveFiles = s.files
                self.liveBytes = s.bytes
                self.skippedDirs = s.skipped
                self.scanFraction = prog.fractionDone()
                // Show the Dock bar only once the ring is up, so a quick scan
                // never flashes the icon; cleared in finishScan / supersede.
                if self.showRing { DockProgress.shared.fraction = self.scanFraction }
            }
        }
        let token = ScanToken()
        scanToken = token
        let (events, sink) = AsyncStream.makeStream(of: ScanEvent.self)
        Task.detached(priority: .userInitiated) {
            TreeScanner.scanStreaming(
                scanPath, progress: prog, token: token,
                onRoot: { sink.yield(.root($0)) },
                onChild: { sink.yield(.child($0, $1)) },
                onDone: {
                    sink.yield(.done)
                    sink.finish()
                }
            )
        }
        let epoch = scanEpoch
        scanConsumer = Task { [weak self] in
            for await event in events {
                guard let self, self.scanEpoch == epoch else { return }
                switch event {
                case .root(let node): self.installRoot(node)
                case .child(let i, let node): self.applyChild(i, node)
                case .done: self.finishScan()
                }
            }
        }
    }

    /// Rescans the current root from disk, restoring the navigation scope once
    /// the fresh tree arrives.
    func rescan() {
        guard !scanRootPath.isEmpty else { return }
        let scope = path.dropFirst().map(\.name)
        scan(path: scanRootPath)
        pendingScopeNames = scope
    }

    /// Stops the in-flight scan (if any) from reaching this model again: its
    /// walk is cancelled, its timers die, and the epoch bump makes its already-
    /// queued events no-ops.
    private func supersedeInFlightScan() {
        scanToken?.cancel()
        scanToken = nil
        scanConsumer?.cancel()
        scanConsumer = nil
        scanEpoch += 1
        pollTimer?.invalidate()
        pollTimer = nil
        ringDelayTimer?.invalidate()
        ringDelayTimer = nil
        DockProgress.shared.fraction = nil  // a superseded scan leaves no bar
    }

    // The three scan-event handlers below are internal (not private) so tests
    // can drive a streaming scan's event sequence deterministically.

    func installRoot(_ node: DirNode) {
        rootName = node.name
        rootCategory = node.category
        rootReclaim = node.reclaim
        rootFiles = node.fileBytes
        liveChildren = node.children
        root = node
        path = [node]
        refresh()
        sweepKey += 1
    }

    func applyChild(_ index: Int, _ node: DirNode) {
        guard index < liveChildren.count else { return }
        liveChildren[index] = node
        // Only restitch the root view while the user is still at the top level.
        guard path.count == 1, let rebuilt = rebuildRoot() else { return }
        withAnimation(.easeOut(duration: 0.5)) {
            root = rebuilt
            path = [rebuilt]
            refresh()
        }
    }

    func finishScan() {
        pollTimer?.invalidate()
        pollTimer = nil
        ringDelayTimer?.invalidate()
        ringDelayTimer = nil
        if let s = progress?.snapshot() {
            liveFiles = s.files
            liveBytes = s.bytes
            skippedDirs = s.skipped
        }
        // Always restitch on completion: `applyChild` stops rebuilding while the
        // user is drilled in, so without this the root would freeze at the last
        // top-level restitch and show stale placeholders after navigating back.
        // The drilled-into subtrees are shared instances, so the path re-resolves
        // into the rebuilt tree by name without losing the user's scope.
        if root != nil, let rebuilt = rebuildRoot() {
            let names = path.dropFirst().map(\.name)
            root = rebuilt
            path = Self.resolvePath(from: rebuilt, names: names)
        }
        // An empty tree from a root we can't read is an error, not a clean
        // result — say so instead of presenting a silent empty donut.
        if let r = root, r.children.isEmpty, r.fileBytes.isEmpty,
            !FileManager.default.isReadableFile(atPath: scanRootPath)
        {
            scanError = "Couldn't read \(scanRootPath)"
        }
        // Restore the scope we were in before a post-reclaim rescan.
        if let names = pendingScopeNames, let r = root {
            pendingScopeNames = nil
            path = Self.resolvePath(from: r, names: names)
        }
        // Surface the reclaim result that triggered this rescan.
        if let outcome = pendingReclaim {
            pendingReclaim = nil
            lastReclaim = outcome
        }
        scanning = false
        scanFraction = 1
        DockProgress.shared.fraction = nil  // walk done — restore the plain icon
        // Fade the activity ring out as the real wedges take over.
        withAnimation(.easeOut(duration: 0.4)) { showRing = false }
        refresh()
        sweepKey += 1
    }

    private func rebuildRoot() -> DirNode? {
        // Preserve the root's full mark (confidence/signal/reason), not a Bool —
        // otherwise the streaming restitch would launder a medium-confidence root
        // up to high via the Bool convenience initializer.
        DirNode(
            name: rootName, category: rootCategory, reclaim: rootReclaim,
            fileBytes: rootFiles, children: liveChildren)
    }

    /// Loads an in-memory tree immediately (previews / tests). `rootPath` is the
    /// absolute path the root represents, so `absoluteURL(for:)` can reconstruct
    /// real paths in tests just as a live scan does.
    func load(_ tree: DirNode, rootPath: String = "") {
        supersedeInFlightScan()
        scanRootPath = rootPath
        volumeName = nil
        root = tree
        path = [tree]
        scanning = false
        scanError = nil
        skippedDirs = 0
        refresh()
        sweepKey += 1
    }

    // MARK: - Derived

    var total: Int64 { max(current?.size ?? 0, 1) }

    /// Scope-dependent derivations. Each is an O(subtree) computation, so they
    /// are cached here and rebuilt only when the *scope* changes (`root` /
    /// `path` / `mode`) via `refresh()` — never on `hover` or per animation
    /// frame. Highlighting a slice then costs a stored-array read instead of
    /// several full-tree walks, which is what kept hover smooth on big scans.
    private(set) var segments: [Segment] = []
    private(set) var arcs: [Arc] = []
    private(set) var reclTotal: Int64 = 0
    private(set) var reclaimTargets: [DirNode] = []
    /// Where the currently expanded type lives (type lens, drill-down rows).
    private(set) var expandedLocations: [(node: DirNode, size: Int64, recl: Int64)] = []

    /// The slice currently focused (hovered, or expanded type). Cheap — a lookup
    /// over the cached `segments` — so it may depend on `hover` freely.
    var focus: Segment? {
        if let h = hover { return segments.first { $0.id == h } }
        if mode == .type, let e = expanded { return segments.first { $0.category == e } }
        return nil
    }

    /// Rebuilds every scope-dependent derivation. Call on any change to `root`,
    /// `path`, or `mode` — i.e. wherever `sweepKey` is bumped.
    private func refresh() {
        segments = computeSegments()
        arcs = computeArcs(segments)
        if let cur = current, path.contains(where: \.isReclaimable) {
            // Viewing inside (or at) a reclaim root: everything here is purgable —
            // even when `reclaim` is nil, because the mark lives on an ancestor.
            // Offer the current folder's children so they can be reviewed and
            // selected individually (matching the sidebar breakdown); a childless
            // folder falls back to offering itself.
            let kids = cur.children.filter { $0.size > 0 }
            reclaimTargets = kids.isEmpty ? [cur] : kids
            reclTotal = reclaimTargets.reduce(0) { $0 + $1.size }
        } else {
            reclTotal = current.map(Derive.reclaimBytes) ?? 0
            reclaimTargets = current.map(Derive.reclaimRoots) ?? []
        }
        refreshExpandedLocations()
        // The scope changed, so any summary now describes a stale folder. Drop it,
        // invalidate any in-flight request (see `summaryEpoch`), then auto-generate
        // a fresh overview for the new scope — no user action required. Skipped
        // while a scan is still streaming (the picture isn't settled yet) and when
        // there's nothing to describe.
        summaryState = .idle
        summaryEpoch += 1
        if !scanning, !segments.isEmpty {
            generateSummary()
        }
    }

    /// Recomputes only the expanded-type drill-down rows. Cheaper than a full
    /// `refresh()`, for when just `expanded` toggles (no scope change).
    private func refreshExpandedLocations() {
        guard mode == .type, let e = expanded, let cur = current else {
            expandedLocations = []
            return
        }
        expandedLocations = Derive.typeLocations(cur, e)
    }

    private func computeSegments() -> [Segment] {
        guard let cur = current else { return [] }
        if mode == .folder {
            // Skip zero-byte children: during a streaming scan these are
            // not-yet-sized placeholders (and otherwise just empty dirs). They
            // contribute no arc, but the slice geometry still floors them to a
            // hoverable sliver — which is what surfaced "0 KB" on hover.
            var segs = cur.children.filter { $0.size > 0 }.map { c in
                Segment(
                    id: Self.nid(c), label: c.name, category: c.category,
                    size: c.size, recl: Derive.reclaimBytes(c),
                    node: c, isType: false, drillable: !c.children.isEmpty, color: .clear)
            }
            let loose = cur.fileBytes.values.reduce(0, +)
            if loose > 0 {
                let cat = cur.fileBytes.max { $0.value < $1.value }!.key
                segs.append(
                    Segment(
                        id: "files:" + Self.nid(cur), label: "Files in this folder",
                        category: cat, size: loose, recl: 0,
                        node: nil, isType: false, drillable: false, color: .clear))
            }
            // Color folders by size rank so the biggest, most-glanced-at slices
            // get the first, most-distinct hues. (The placeholder `.clear` above
            // is always overwritten here.)
            return segs.sorted { $0.size > $1.size }
                .enumerated().map { i, s in s.recolored(Palette.folderHue(i)) }
        } else {
            let sizes = Derive.typeSizes(cur)
            let recl = Derive.typeReclaim(cur)
            return sizes.map { (cat, size) in
                Segment(
                    id: "type:\(cat.rawValue)", label: cat.label, category: cat,
                    size: size, recl: recl[cat] ?? 0, node: nil, isType: true,
                    drillable: false, color: Palette.color(cat))
            }.sorted { $0.size > $1.size }
        }
    }

    private func computeArcs(_ segs: [Segment]) -> [Arc] {
        let gap = 0.020
        var a = -Double.pi / 2
        let t = Double(total)
        return segs.map { s in
            let ang = Double(s.size) / t * .pi * 2
            let arc = Arc(seg: s, a0: a, a1: a + ang, gap: gap)
            a += ang
            return arc
        }
    }

    /// Breadcrumb labels: the scan root's real volume name (when known — an
    /// in-memory tree has none), then the navigated path.
    var crumbs: [String] {
        let names = path.map { displayName($0.name) }
        return volumeName.map { [$0] + names } ?? names
    }

    /// Index of the first *path* crumb (0, or 1 when a volume crumb leads).
    private var crumbOffset: Int { volumeName == nil ? 0 : 1 }

    func displayName(_ name: String) -> String {
        name == homeLeaf ? "~" : name
    }

    /// Top-down full path string for a node, with the scan root shown as `~`.
    func fullPath(_ node: DirNode) -> String {
        let comps = Derive.pathTo(node).map { $0.name }
        guard comps.count > 1 else { return "~" }
        return "~/" + comps.dropFirst().joined(separator: "/")
    }

    private var homeLeaf: String { root?.name ?? "~" }

    /// Real filesystem URL of the directory currently shown in the breadcrumb.
    var currentURL: URL {
        current.map(absoluteURL(for:)) ?? URL(fileURLWithPath: scanRootPath)
    }

    /// Asks for a directory via the standard open panel and scans it. Modal and
    /// user-driven — exercised by hand, not headlessly testable.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        panel.message = "Choose a folder for Halo to scan"
        if panel.runModal() == .OK, let url = panel.url {
            scan(path: url.path)
        }
    }

    /// Opens a Finder window showing the current directory's contents.
    /// Uses the file-viewer API (not `NSWorkspace.open`, which routes through
    /// LaunchServices' *open-as-document* path and pops a "no app" dialog for
    /// anything Finder doesn't treat as a plain folder).
    func openInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: currentURL.path)
    }

    // MARK: - Full Disk Access

    /// Re-probe Full Disk Access — called when the app reactivates, e.g. after
    /// the user visits System Settings to grant it. On a denied→granted
    /// transition, rescan so the dirs the walk had to skip fill in.
    ///
    /// The probe (`open()`) runs on a background thread so the main actor is
    /// never blocked. The animation for the banner fade-out is applied here,
    /// after the probe completes, so the caller doesn't need a `withAnimation`
    /// wrapper. The rescan is deferred past the animation transaction via `Task`
    /// so scan-state resets (`scanning = true`, `showRing = false`, …) aren't
    /// caught by the easeOut curve.
    func refreshFullDiskAccess() {
        let wasDenied = !fullDiskAccess
        Task.detached(priority: .utility) {
            let granted = FullDiskAccess.isGranted
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.fullDiskAccess = granted
                }
                if granted && wasDenied {
                    self.fdaBannerDismissed = false
                    if !self.scanRootPath.isEmpty {
                        Task { self.rescan() }
                    }
                }
            }
        }
    }

    /// Opens the Full Disk Access settings pane so the user can add Halo.
    func openFullDiskAccessSettings() {
        FullDiskAccess.openSettings()
    }

    /// Hides the Full Disk Access banner for the rest of this session.
    func dismissFDABanner() {
        fdaBannerDismissed = true
    }

    // MARK: - Reclaim

    /// Absolute filesystem URL of any node in the tree: the scan root joined with
    /// the node's name chain (the root itself maps to the scan root).
    func absoluteURL(for node: DirNode) -> URL {
        var url = URL(fileURLWithPath: scanRootPath)
        for n in Derive.pathTo(node).dropFirst() { url.append(component: n.name) }
        return url
    }

    /// The safe targets in the current scope as reviewable rows, largest first,
    /// with high-confidence targets pre-selected.
    var reclaimPlan: [ReclaimItem] {
        reclaimTargets.compactMap { node in
            guard let mark = effectiveMark(for: node) else { return nil }
            return ReclaimItem(
                id: ObjectIdentifier(node), name: node.name,
                url: absoluteURL(for: node), size: node.size,
                confidence: mark.confidence,
                signalLabel: Self.signalLabel(mark.signal, category: node.category),
                reason: mark.reason, preselected: mark.confidence == .high,
                permanentDelete: node.category == .trash)
        }.sorted { $0.size > $1.size }
    }

    /// The reclaim mark governing `node`: its own, or the nearest reclaimable
    /// ancestor's (a node inside a reclaim root carries no mark of its own but is
    /// still purgable under that root's evidence).
    private func effectiveMark(for node: DirNode) -> ReclaimMark? {
        if let m = node.reclaim { return m }
        var p = node.parent
        while let x = p {
            if let m = x.reclaim { return m }
            p = x.parent
        }
        return nil
    }

    /// Move the chosen targets to the Trash, then prune them out of the local
    /// tree. Trashing runs off the main actor; results hop back to update.
    func performReclaim(_ items: [ReclaimItem]) {
        guard !items.isEmpty else { return }
        showReclaimSheet = false
        Task.detached(priority: .userInitiated) {
            // Items already in the Trash can't be moved to the Trash — they're
            // permanently removed instead. Everything else moves to the Trash.
            let toTrash = items.filter { !$0.permanentDelete }
            let toDelete = items.filter(\.permanentDelete)
            let trashResult = Reclaimer.moveToTrash(toTrash.map(\.url))
            let deleteResult = Reclaimer.delete(toDelete.map(\.url))
            let goneURLs = Set(trashResult.trashed).union(deleteResult.removed)
            let ids = Set(items.filter { goneURLs.contains($0.url) }.map(\.id))
            let outcome = ReclaimOutcome(
                trashed: trashResult.trashed.count,
                deleted: deleteResult.removed.count,
                failed: trashResult.failed.count + deleteResult.failed.count)
            await MainActor.run { self.applyReclaimResult(trashedIDs: ids, outcome: outcome) }
        }
    }

    /// Applies a finished reclaim by pruning the trashed subtrees out of the
    /// tree in place — ancestor sizes recompute on the rebuild — so the donut
    /// updates instantly instead of paying for a full rescan. Falls back to a
    /// rescan only when none of the node identities are found anymore (the tree
    /// was restitched by a still-streaming scan since the sheet was built).
    func applyReclaimResult(trashedIDs: Set<ObjectIdentifier>, outcome: ReclaimOutcome) {
        lastReclaim = outcome
        guard let r = root, !trashedIDs.isEmpty else { return }
        let pruned = Derive.removing(trashedIDs, from: r)
        if let pruned, pruned === r {
            pendingReclaim = outcome
            pendingScopeNames = path.dropFirst().map(\.name)
            scan(path: scanRootPath)
            return
        }
        let names = path.dropFirst().map(\.name)
        // A trashed scan root leaves an empty tree of the same name.
        let newRoot =
            pruned
            ?? DirNode(
                name: r.name, category: r.category,
                reclaim: nil, fileBytes: [:], children: [])
        root = newRoot
        path = Self.resolvePath(from: newRoot, names: names)
        hover = nil
        refresh()
        sweepKey += 1
    }

    /// Re-derive a path from `root` by following child `names`, stopping at the
    /// first name that no longer exists. Used to restore the user's scope after a
    /// rescan, even if some folders along the way were just trashed.
    static func resolvePath(from root: DirNode, names: [String]) -> [DirNode] {
        var result = [root]
        var node = root
        for name in names {
            guard let next = node.children.first(where: { $0.name == name }) else { break }
            result.append(next)
            node = next
        }
        return result
    }

    private static func signalLabel(_ s: ReclaimSignal, category: FileCategory) -> String {
        switch s {
        case .cachedirTag: return "CACHEDIR.TAG"
        case .manifest(let m): return m
        case .knownName: return category.label
        }
    }

    // MARK: - Summary

    /// A compact, model-readable description of the current scope: the largest
    /// items (in whichever lens is active), their share, and what's reclaimable.
    /// Kept pure and internal so it can be unit-tested without the language model
    /// (which can't run headlessly). Mirrors exactly what the rail already shows,
    /// so the summary can never reference a figure the user can't see.
    func summaryFacts() -> String {
        let scope = displayName(current?.name ?? "~")
        var lines: [String] = []
        lines.append("Folder: \(scope)")
        lines.append("Total size: \(formatSize(total))")
        lines.append(
            mode == .type
                ? "Breakdown by file type (largest first):"
                : "Largest items inside (largest first):")
        for s in segments.prefix(8) {
            var line = "- \(s.label): \(formatSize(s.size)) (\(percent(s.size, of: total).clean)%)"
            if s.recl > 0 { line += ", \(formatSize(s.recl)) reclaimable" }
            lines.append(line)
        }
        if reclTotal > 0 {
            let n = reclaimTargets.count
            lines.append(
                "Safely reclaimable in total: \(formatSize(reclTotal)) "
                    + "across \(n) target\(n == 1 ? "" : "s") (caches, build output, dependencies, trash)."
            )
        } else {
            lines.append("Nothing here is flagged as safely reclaimable.")
        }
        return lines.joined(separator: "\n")
    }

    /// Kick off an on-device overview of the current scope. Called automatically
    /// from `refresh()`; not user-invoked. Stays silent (`.idle`, so the rail
    /// shows nothing) when the model can't run or generation fails — the feature
    /// only ever surfaces a finished summary, never an error or a prompt.
    private func generateSummary() {
        guard SummaryService.isAvailable else {
            summaryState = .idle
            return
        }
        let facts = summaryFacts()
        let epoch = summaryEpoch
        summaryState = .loading
        summaryTask?.cancel()
        summaryTask = Task {
            let insight = try? await SummaryService.summarize(facts)
            // A navigation/rescan since we started moved us off this scope.
            guard !Task.isCancelled, self.summaryEpoch == epoch else { return }
            self.summaryState = insight.map(SummaryState.ready) ?? .idle
        }
    }

    // MARK: - Navigation

    func tapSegment(_ s: Segment) {
        if mode == .folder {
            // Drill into any real folder — including a leaf that holds only files
            // (it then shows its "Files in this folder" breakdown). The loose-files
            // pseudo-segment carries no node, so it stays a no-op.
            if let node = s.node {
                hover = nil
                expanded = nil
                path.append(node)
                refresh()
                sweepKey += 1
            }
        } else {
            expanded = (expanded == s.category) ? nil : s.category
            refreshExpandedLocations()
        }
    }

    func jump(to node: DirNode) {
        mode = .folder
        hover = nil
        expanded = nil
        path = Derive.pathTo(node)
        refresh()
        sweepKey += 1
    }

    func goTo(crumb index: Int) {
        // The leading volume crumb (when present) is decorative, not navigable.
        let i = index - crumbOffset
        guard i >= 0, i < path.count else { return }
        hover = nil
        expanded = nil
        path = Array(path.prefix(i + 1))
        refresh()
        sweepKey += 1
    }

    func back() {
        guard path.count > 1 else { return }
        hover = nil
        expanded = nil
        path.removeLast()
        refresh()
        sweepKey += 1
    }

    func setMode(_ m: Lens) {
        guard m != mode else { return }
        mode = m
        hover = nil
        expanded = nil
        refresh()
        sweepKey += 1
    }

    /// Stable segment id: the node's name-path from the root. Identity-based ids
    /// died on every streaming restitch (all-new nodes), dropping the hovered
    /// slice mid-scan; sibling names are unique within a directory, so the path
    /// is collision-free.
    private static func nid(_ node: DirNode) -> String {
        Derive.pathTo(node).map(\.name).joined(separator: "/")
    }
}
