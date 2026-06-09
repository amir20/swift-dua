import XCTest
@testable import Halo
@testable import DiskKit

@MainActor
final class ScanModelTests: XCTestCase {

    /// Hovering a slice must report that segment's real size in the hole.
    /// Reproduces the "hover shows 0 KB" report against a fully-sized tree.
    func testHoverFocusReportsSegmentSize() {
        let model = ScanModel()
        model.load(MockTree.make())

        let segs = model.segments
        XCTAssertFalse(segs.isEmpty, "mock tree should produce folder segments")

        let biggest = segs.max { $0.size < $1.size }!
        XCTAssertGreaterThan(biggest.size, 0)

        model.hover = biggest.id
        XCTAssertEqual(model.focus?.id, biggest.id, "focus resolves the hovered id")
        XCTAssertEqual(model.focus?.size, biggest.size, "focus reports the segment's size")
        XCTAssertGreaterThan(model.focus?.size ?? 0, 0, "hover must not show 0")
    }

    /// Every folder segment must round-trip through hover with its own size.
    func testEveryFolderSegmentFocusesToItsSize() {
        let model = ScanModel()
        model.load(MockTree.make())
        for seg in model.segments {
            model.hover = seg.id
            XCTAssertEqual(model.focus?.size, seg.size, "segment \(seg.label) focus size")
        }
    }

    /// A zero-size child — a not-yet-sized streaming placeholder, or a genuinely
    /// empty directory — must not appear as a segment, so it cannot be hovered
    /// to show a meaningless "0 KB". This reproduces the reported bug where
    /// hovering `.swiftpm` (still a placeholder mid-scan) showed 0.
    func testZeroSizeChildrenAreNotSegments() {
        let GB: Int64 = 1_073_741_824
        let placeholder = DirNode(name: ".swiftpm", category: .other,
                                  isReclaimable: false, fileBytes: [:], children: [])
        let real = DirNode(name: "Movies", category: .media,
                           isReclaimable: false, fileBytes: [.media: 10 * GB], children: [])
        let root = DirNode(name: "alex", category: .other,
                           isReclaimable: false, fileBytes: [:], children: [placeholder, real])

        let model = ScanModel()
        model.load(root)

        XCTAssertNil(model.segments.first { $0.size == 0 },
                     "no zero-size segments should be produced")
        XCTAssertFalse(model.segments.contains { $0.label == ".swiftpm" },
                       "an unsized placeholder must not be shown")
        XCTAssertTrue(model.segments.contains { $0.label == "Movies" })
        XCTAssertTrue(model.arcs.allSatisfy { $0.seg.size > 0 },
                      "no zero-size arcs to hover")
    }

    /// Hovering a point in the donut must resolve to the arc actually under the
    /// cursor. Reproduces "hovering the biggest section showed the smallest":
    /// the old per-slice `.onHover` let the topmost (smallest) slice's full-frame
    /// tracking area swallow every hover.
    func testDonutHoverHitsTheArcUnderTheCursor() {
        let model = ScanModel()
        model.load(MockTree.make())
        let arcs = model.arcs
        XCTAssertFalse(arcs.isEmpty)

        let center: CGFloat = 230, r0: CGFloat = 122, r1: CGFloat = 196
        let rMid = (r0 + r1) / 2

        func point(atAngle a: Double) -> CGPoint {
            CGPoint(x: center + rMid * CGFloat(cos(a)), y: center + rMid * CGFloat(sin(a)))
        }

        for arc in arcs {
            let p = point(atAngle: (arc.a0 + arc.a1) / 2)
            XCTAssertEqual(hitTestArc(at: p, in: arcs, center: center, r0: r0, r1: r1),
                           arc.seg.id, "midpoint of \(arc.seg.label) must hit its own arc")
        }

        // The specific reported failure: the largest slice resolves to itself.
        let biggest = arcs.max { $0.seg.size < $1.seg.size }!
        let smallest = arcs.min { $0.seg.size < $1.seg.size }!
        let hit = hitTestArc(at: point(atAngle: (biggest.a0 + biggest.a1) / 2),
                             in: arcs, center: center, r0: r0, r1: r1)
        XCTAssertEqual(hit, biggest.seg.id)
        XCTAssertNotEqual(hit, smallest.seg.id, "biggest must not resolve to smallest")

        // Inside the hole and outside the ring resolve to nothing.
        XCTAssertNil(hitTestArc(at: CGPoint(x: center, y: center),
                                in: arcs, center: center, r0: r0, r1: r1))
        XCTAssertNil(hitTestArc(at: CGPoint(x: center + 400, y: center),
                                in: arcs, center: center, r0: r0, r1: r1))
    }

    private static let GB: Int64 = 1_073_741_824

    /// Tapping a folder that holds only files (no subdirectories) must still
    /// drill into it. Reproduces "the breadcrumb doesn't work" — `tapSegment`
    /// used to ignore any folder whose `children` were empty, so clicking a
    /// leaf folder did nothing.
    func testTappingLeafFolderDrillsIntoIt() {
        let leaf = DirNode(name: "Caches", category: .cache,
                           isReclaimable: true, fileBytes: [.cache: 5 * Self.GB], children: [])
        let root = DirNode(name: "alex", category: .other,
                           isReclaimable: false, fileBytes: [:], children: [leaf])
        let model = ScanModel()
        model.load(root)

        let seg = model.segments.first { $0.label == "Caches" }!
        model.tapSegment(seg)

        XCTAssertEqual(model.current?.name, "Caches", "tapping a leaf folder drills into it")
        XCTAssertEqual(model.path.count, 2)
    }

    /// `jump(to:)` must land on the requested directory, not bounce up to its
    /// parent when that directory has no subdirectories. Reproduces "clicking a
    /// dir goes to the parent instead".
    func testJumpToLeafDirLandsOnIt() {
        let leaf = DirNode(name: "com.apple.wallpaper.caches", category: .cache,
                           isReclaimable: true, fileBytes: [.cache: 200 * Self.GB], children: [])
        let mid = DirNode(name: "Caches", category: .cache,
                          isReclaimable: true, fileBytes: [:], children: [leaf])
        let root = DirNode(name: "alex", category: .other,
                           isReclaimable: false, fileBytes: [:], children: [mid])
        let model = ScanModel()
        model.load(root)

        model.jump(to: leaf)
        XCTAssertEqual(model.current?.name, "com.apple.wallpaper.caches",
                       "jump lands on the leaf, not its parent")
    }
}
