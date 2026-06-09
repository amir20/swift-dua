import SwiftUI
import AppKit
import DiskKit

/// One ring slice / rail row in either lens.
struct Segment: Identifiable {
    let id: String
    let label: String
    let category: FileCategory
    let size: Int64
    let recl: Int64
    let node: DirNode?      // folder lens: the directory this slice represents
    let isType: Bool
    let drillable: Bool
    /// The slice/swatch color: a distinct per-folder hue in the folder lens, the
    /// semantic category color in the type lens. Resolved once at build time so
    /// the donut and rail always agree.
    let color: Color

    func recolored(_ c: Color) -> Segment {
        Segment(id: id, label: label, category: category, size: size, recl: recl,
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
    /// Whether the scanning activity ring is shown. Gated behind a short delay so
    /// a fast scan never flashes it.
    var showRing = false

    var current: DirNode? { path.last }

    /// Absolute filesystem path the scan was rooted at. Joined with the names of
    /// the navigated `path` to recover the real directory under the breadcrumb.
    private var scanRootPath = ""

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

    // MARK: - Loading

    /// Streams a real scan: the donut appears immediately and fills in as each
    /// top-level subtree completes, with a live counter throughout.
    func scan(path scanPath: String) {
        scanRootPath = scanPath
        scanning = true
        scanError = nil
        liveFiles = 0; liveBytes = 0
        showRing = false
        let prog = ScanProgress()
        progress = prog
        ringDelayTimer?.invalidate()
        ringDelayTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
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
            }
        }
        Task.detached(priority: .userInitiated) {
            TreeScanner.scanStreaming(
                scanPath, progress: prog,
                onRoot:  { node in Task { @MainActor in self.installRoot(node) } },
                onChild: { i, node in Task { @MainActor in self.applyChild(i, node) } },
                onDone:  { Task { @MainActor in self.finishScan() } }
            )
        }
    }

    private func installRoot(_ node: DirNode) {
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

    private func applyChild(_ index: Int, _ node: DirNode) {
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

    private func finishScan() {
        pollTimer?.invalidate(); pollTimer = nil
        ringDelayTimer?.invalidate(); ringDelayTimer = nil
        if path.count == 1, let rebuilt = rebuildRoot() {
            root = rebuilt
            path = [rebuilt]
        }
        scanning = false
        // Fade the activity ring out as the real wedges take over.
        withAnimation(.easeOut(duration: 0.4)) { showRing = false }
        refresh()
        sweepKey += 1
    }

    private func rebuildRoot() -> DirNode? {
        // Preserve the root's full mark (confidence/signal/reason), not a Bool —
        // otherwise the streaming restitch would launder a medium-confidence root
        // up to high via the Bool convenience initializer.
        DirNode(name: rootName, category: rootCategory, reclaim: rootReclaim,
                fileBytes: rootFiles, children: liveChildren)
    }

    /// Loads an in-memory tree immediately (previews / tests).
    func load(_ tree: DirNode) {
        root = tree
        path = [tree]
        scanning = false
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
        reclTotal = current.map(Derive.reclaimBytes) ?? 0
        reclaimTargets = current.map(Derive.reclaimRoots) ?? []
        refreshExpandedLocations()
    }

    /// Recomputes only the expanded-type drill-down rows. Cheaper than a full
    /// `refresh()`, for when just `expanded` toggles (no scope change).
    private func refreshExpandedLocations() {
        guard mode == .type, let e = expanded, let cur = current else {
            expandedLocations = []; return
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
                Segment(id: Self.nid(c), label: c.name, category: c.category,
                        size: c.size, recl: Derive.reclaimBytes(c),
                        node: c, isType: false, drillable: !c.children.isEmpty, color: .clear)
            }
            let loose = cur.fileBytes.values.reduce(0, +)
            if loose > 0 {
                let cat = cur.fileBytes.max { $0.value < $1.value }!.key
                segs.append(Segment(id: "files:" + Self.nid(cur), label: "Files in this folder",
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
                Segment(id: "type:\(cat.rawValue)", label: cat.label, category: cat,
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

    var crumbs: [String] {
        ["Macintosh HD"] + path.map { displayName($0.name) }
    }

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

    /// Real filesystem URL of the directory currently shown in the breadcrumb:
    /// the scan root joined with each navigated subdirectory's name.
    var currentURL: URL {
        var url = URL(fileURLWithPath: scanRootPath)
        for node in path.dropFirst() { url.append(component: node.name) }
        return url
    }

    /// Opens a Finder window showing the current directory's contents.
    /// Uses the file-viewer API (not `NSWorkspace.open`, which routes through
    /// LaunchServices' *open-as-document* path and pops a "no app" dialog for
    /// anything Finder doesn't treat as a plain folder).
    func openInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: currentURL.path)
    }

    // MARK: - Navigation

    func tapSegment(_ s: Segment) {
        if mode == .folder {
            // Drill into any real folder — including a leaf that holds only files
            // (it then shows its "Files in this folder" breakdown). The loose-files
            // pseudo-segment carries no node, so it stays a no-op.
            if let node = s.node {
                hover = nil; expanded = nil
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
        mode = .folder; hover = nil; expanded = nil
        path = Derive.pathTo(node)
        refresh()
        sweepKey += 1
    }

    func goTo(crumb index: Int) {
        // crumbs[0] is "Macintosh HD"; crumbs[1...] map to path[0...].
        guard index >= 1, index - 1 < path.count else { return }
        hover = nil; expanded = nil
        path = Array(path.prefix(index))
        refresh()
        sweepKey += 1
    }

    func back() {
        guard path.count > 1 else { return }
        hover = nil; expanded = nil
        path.removeLast()
        refresh()
        sweepKey += 1
    }

    func setMode(_ m: Lens) {
        guard m != mode else { return }
        mode = m; hover = nil; expanded = nil
        refresh()
        sweepKey += 1
    }

    private static func nid(_ node: DirNode) -> String { String(UInt(bitPattern: ObjectIdentifier(node).hashValue)) }
}
