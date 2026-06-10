import XCTest
@testable import Halo
@testable import DiskKit

@MainActor
final class ScanModelReclaimTests: XCTestCase {
    private let GB: Int64 = 1_073_741_824
    private let MB: Int64 = 1_048_576

    /// alex/{Library/Caches[high], Projects/app/{node_modules[high], build[medium]}}
    private func makeTree() -> DirNode {
        let caches = DirNode(name: "Caches", category: .cache,
            reclaim: ReclaimMark(confidence: .high, signal: .knownName, reason: "macOS cache directory"),
            fileBytes: [.cache: 200 * GB], children: [])
        let library = DirNode(name: "Library", category: .other, reclaim: nil, fileBytes: [:], children: [caches])
        let nodeModules = DirNode(name: "node_modules", category: .deps,
            reclaim: ReclaimMark(confidence: .high, signal: .manifest("package.json"), reason: "regenerable"),
            fileBytes: [.deps: 1 * GB], children: [])
        let build = DirNode(name: "build", category: .build,
            reclaim: ReclaimMark(confidence: .medium, signal: .knownName, reason: "known build dir"),
            fileBytes: [.build: 300 * MB], children: [])
        let app = DirNode(name: "app", category: .other, reclaim: nil, fileBytes: [:], children: [nodeModules, build])
        let projects = DirNode(name: "Projects", category: .other, reclaim: nil, fileBytes: [:], children: [app])
        return DirNode(name: "alex", category: .other, reclaim: nil, fileBytes: [:], children: [library, projects])
    }

    private func find(_ n: DirNode, _ name: String) -> DirNode? {
        n.name == name ? n : n.children.lazy.compactMap { self.find($0, name) }.first
    }

    func testAbsoluteURLReconstructsFromScanRoot() {
        let model = ScanModel()
        let root = makeTree()
        model.load(root, rootPath: "/Users/alex")
        XCTAssertEqual(model.absoluteURL(for: root).path, "/Users/alex")
        XCTAssertEqual(model.absoluteURL(for: find(root, "Caches")!).path, "/Users/alex/Library/Caches")
        XCTAssertEqual(model.absoluteURL(for: find(root, "node_modules")!).path,
                       "/Users/alex/Projects/app/node_modules")
    }

    func testReclaimPlanSortedWithPreselectionAndLabels() {
        let model = ScanModel()
        model.load(makeTree(), rootPath: "/Users/alex")
        let plan = model.reclaimPlan
        XCTAssertEqual(plan.map(\.name), ["Caches", "node_modules", "build"], "sorted by size desc")
        XCTAssertEqual(plan.map(\.preselected), [true, true, false], "high pre-selected, medium not")
        XCTAssertEqual(plan.map(\.signalLabel), ["Caches", "package.json", "Build output"])
        XCTAssertEqual(plan[0].url.path, "/Users/alex/Library/Caches")
        XCTAssertEqual(plan[0].confidence, .high)
        XCTAssertEqual(plan[0].size, 200 * GB)
    }

    /// After a rescan we re-follow the old folder names from the new root so the
    /// user stays where they were — stopping at the first name that's gone (e.g.
    /// a folder we just trashed).
    func testResolvePathFollowsNamesAndStopsAtMissing() {
        let root = makeTree()
        XCTAssertEqual(ScanModel.resolvePath(from: root, names: []).map(\.name), ["alex"])
        XCTAssertEqual(ScanModel.resolvePath(from: root, names: ["Library", "Caches"]).map(\.name),
                       ["alex", "Library", "Caches"])
        XCTAssertEqual(ScanModel.resolvePath(from: root, names: ["Library", "Gone", "Deeper"]).map(\.name),
                       ["alex", "Library"], "stops at the first missing component")
    }

    /// Drilled into a subtree, the plan only covers that subtree's targets.
    func testReclaimPlanIsScopedToCurrentView() {
        let model = ScanModel()
        let root = makeTree()
        model.load(root, rootPath: "/Users/alex")
        model.jump(to: find(root, "app")!)
        XCTAssertEqual(Set(model.reclaimPlan.map(\.name)), ["node_modules", "build"])
    }

    /// alex/.cache[reclaimable]/uv/archive — `uv` is reclaimable only by
    /// inheritance (`reclaim == nil`). Navigating *into* `uv` must still treat the
    /// whole folder as a safe target, with the confidence of the enclosing root.
    private func makeCacheTree() -> DirNode {
        let archive = DirNode(name: "archive-v0", category: .cache,
                              reclaim: nil, fileBytes: [.cache: 8 * GB], children: [])
        let uv = DirNode(name: "uv", category: .cache, reclaim: nil, fileBytes: [:], children: [archive])
        let cache = DirNode(name: ".cache", category: .cache,
            reclaim: ReclaimMark(confidence: .medium, signal: .knownName, reason: "known cache directory"),
            fileBytes: [:], children: [uv])
        return DirNode(name: "alex", category: .other, reclaim: nil, fileBytes: [:], children: [cache])
    }

    func testReclaimRecognizedWhenViewingInsideAReclaimRoot() {
        let model = ScanModel()
        let root = makeCacheTree()
        model.load(root, rootPath: "/Users/alex")
        model.jump(to: find(root, "uv")!)

        XCTAssertEqual(model.current?.name, "uv")
        XCTAssertEqual(model.reclTotal, find(root, "uv")!.size,
                       "the whole current folder is reclaimable when inside a reclaim root")
        XCTAssertEqual(model.reclaimPlan.map(\.name), ["uv"])
        XCTAssertEqual(model.reclaimPlan.first?.confidence, .medium,
                       "confidence is inherited from the enclosing .cache root")
        XCTAssertEqual(model.reclaimPlan.first?.url.path, "/Users/alex/.cache/uv")
    }

    /// Clicking a breadcrumb navigates to *that* directory, not its parent.
    /// crumbs = ["Macintosh HD", "~", "Library", "Caches"]; crumb 2 is "Library".
    func testGoToCrumbLandsOnThatDirectory() {
        let model = ScanModel()
        let root = makeTree()
        model.load(root, rootPath: "/Users/alex")
        model.jump(to: find(root, "Caches")!)   // path: alex / Library / Caches
        model.goTo(crumb: 2)
        XCTAssertEqual(model.current?.name, "Library", "crumb 2 is Library, not its parent")
        model.goTo(crumb: 1)
        XCTAssertEqual(model.current?.name, "alex", "crumb 1 is the home root")
    }
}

final class ReclaimerTests: XCTestCase {
    /// A URL that doesn't exist must be reported as failed, not silently dropped,
    /// and must not abort the batch.
    func testNonexistentURLIsReportedFailed() {
        let missing = URL(fileURLWithPath: "/nope/\(UUID().uuidString)/gone")
        let result = Reclaimer.moveToTrash([missing])
        XCTAssertTrue(result.trashed.isEmpty)
        XCTAssertEqual(result.failed.count, 1)
        XCTAssertEqual(result.failed.first?.url, missing)
    }

    /// A real file is moved out of its original location and reported trashed.
    /// (Cleans up after itself so it doesn't litter the user's Trash.)
    func testRealFileIsMovedToTrash() throws {
        let fm = FileManager.default
        let name = "halo-reclaim-test-\(UUID().uuidString).bin"
        let file = fm.temporaryDirectory.appendingPathComponent(name)
        try Data(count: 1_000).write(to: file)
        XCTAssertTrue(fm.fileExists(atPath: file.path))

        let result = Reclaimer.moveToTrash([file])

        XCTAssertEqual(result.trashed, [file])
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: file.path), "the file must be gone from its origin")

        // Best-effort cleanup: the unique name can't collide, so it lands in
        // ~/.Trash under the same name.
        if let trash = try? fm.url(for: .trashDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: false) {
            try? fm.removeItem(at: trash.appendingPathComponent(name))
        }
    }
}
