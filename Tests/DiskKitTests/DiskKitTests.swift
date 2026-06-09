import XCTest
import Foundation
@testable import DiskKit

/// Thread-safe sink for the streaming scan's callbacks, which fire on scanner
/// threads. Reads are safe once `scanStreaming` (synchronous) has returned.
private final class StreamSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _root: DirNode?
    private var _children: [Int: DirNode] = [:]
    private var _doneCount = 0

    var root: DirNode? { lock.withLock { _root } }
    var children: [Int: DirNode] { lock.withLock { _children } }
    var doneCount: Int { lock.withLock { _doneCount } }

    func setRoot(_ n: DirNode) { lock.withLock { _root = n } }
    func addChild(_ i: Int, _ n: DirNode) { lock.withLock { _children[i] = n } }
    func finish() { lock.withLock { _doneCount += 1 } }
}

final class ClassifierTests: XCTestCase {
    /// Classify `name` as if it were a child of a directory containing
    /// `siblings`, with an optional inherited override / CACHEDIR.TAG.
    private func classify(_ name: String, siblings: Set<String> = [],
                          inherited: FileCategory? = nil, tag: Bool = false) -> Classifier.DirClass {
        let hint = Classifier.hint(forChild: name, siblings: siblings)
        return Classifier.classify(name: name, inherited: inherited, hint: hint, hasCachedirTag: tag)
    }

    func testUnambiguousNamesAreHighByName() {
        let nm = classify("node_modules")
        XCTAssertEqual(nm.category, .deps)
        XCTAssertEqual(nm.filesAs, .deps)
        XCTAssertEqual(nm.reclaim?.confidence, .high)
        XCTAssertEqual(nm.reclaim?.signal, .knownName)

        XCTAssertEqual(classify(".Trash").reclaim?.confidence, .high)
        XCTAssertEqual(classify("DerivedData").category, .build)
        XCTAssertEqual(classify("DerivedData").reclaim?.confidence, .high)
    }

    func testAmbiguousNameAloneIsMedium() {
        let b = classify("build")
        XCTAssertEqual(b.category, .build)
        XCTAssertEqual(b.reclaim?.confidence, .medium)
        XCTAssertEqual(classify("cache").reclaim?.confidence, .medium)
    }

    func testManifestSiblingLiftsToHigh() {
        let nm = classify("node_modules", siblings: ["package.json"])
        XCTAssertEqual(nm.reclaim?.confidence, .high)
        XCTAssertEqual(nm.reclaim?.signal, .manifest("package.json"))

        let target = classify("target", siblings: ["cargo.toml"])
        XCTAssertEqual(target.category, .build)
        XCTAssertEqual(target.reclaim?.signal, .manifest("cargo.toml"))
    }

    func testCachedirTagFlagsAsCache() {
        let c = classify("weird-cache", tag: true)
        XCTAssertEqual(c.category, .cache)
        XCTAssertEqual(c.reclaim?.confidence, .high)
        XCTAssertEqual(c.reclaim?.signal, .cachedirTag)
    }

    func testManifestBeatsCachedirTagForCategory() {
        // target with Cargo.toml beside it AND a CACHEDIR.TAG inside → build.
        let target = classify("target", siblings: ["cargo.toml"], tag: true)
        XCTAssertEqual(target.category, .build)
        XCTAssertEqual(target.reclaim?.signal, .manifest("cargo.toml"))
    }

    func testInheritedDescendantIsNotItsOwnTarget() {
        let child = classify("anything", inherited: .deps)
        XCTAssertEqual(child.category, .deps)
        XCTAssertNil(child.reclaim, "a descendant of a reclaim root is not separately reclaimable")
    }

    func testNonReclaimableNames() {
        XCTAssertNil(classify("Library").reclaim)
        XCTAssertNil(classify("Documents").reclaim)
        XCTAssertNil(classify("Movies").reclaim)
    }

    func testFileExtensionCategories() {
        XCTAssertEqual(Classifier.classifyFile(ext: "mp4"), .media)
        XCTAssertEqual(Classifier.classifyFile(ext: "swift"), .code)
        XCTAssertEqual(Classifier.classifyFile(ext: "pdf"), .docs)
        XCTAssertEqual(Classifier.classifyFile(ext: "xyz"), .other)
    }
}

/// End-to-end: the detector flags reclaimable directories through a real scan.
final class ReclaimScanTests: XCTestCase {
    private func scanTree(_ build: (URL, FileManager) throws -> Void) throws -> DirNode {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("diskkit-reclaim-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        try build(base, fm)
        return TreeScanner.scan(base.path)
    }

    private func find(_ n: DirNode, _ name: String) -> DirNode? {
        if n.name == name { return n }
        for c in n.children { if let f = find(c, name) { return f } }
        return nil
    }

    func testManifestEvidenceFlagsHigh() throws {
        let root = try scanTree { base, fm in
            try fm.createDirectory(at: base.appendingPathComponent("proj/node_modules"),
                                   withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: base.appendingPathComponent("proj/package.json"))
            try Data(count: 5_000).write(to: base.appendingPathComponent("proj/node_modules/dep.bin"))
        }
        let nm = find(root, "node_modules")
        XCTAssertEqual(nm?.reclaim?.confidence, .high)
        XCTAssertEqual(nm?.reclaim?.signal, .manifest("package.json"))
        XCTAssertEqual(nm?.category, .deps)
    }

    func testUnambiguousNameWithoutManifestIsHigh() throws {
        let root = try scanTree { base, fm in
            try fm.createDirectory(at: base.appendingPathComponent("node_modules"),
                                   withIntermediateDirectories: true)
            try Data(count: 5_000).write(to: base.appendingPathComponent("node_modules/dep.bin"))
        }
        XCTAssertEqual(find(root, "node_modules")?.reclaim?.signal, .knownName)
    }

    func testAmbiguousNameAloneIsMedium() throws {
        let root = try scanTree { base, fm in
            try fm.createDirectory(at: base.appendingPathComponent("build"),
                                   withIntermediateDirectories: true)
            try Data(count: 5_000).write(to: base.appendingPathComponent("build/out.bin"))
        }
        XCTAssertEqual(find(root, "build")?.reclaim?.confidence, .medium)
    }

    func testCachedirTagDetected() throws {
        let root = try scanTree { base, fm in
            let cache = base.appendingPathComponent("weird-cache")
            try fm.createDirectory(at: cache, withIntermediateDirectories: true)
            try Data("Signature: 8a477f597d28d172789f06886806bc55\n# by some tool".utf8)
                .write(to: cache.appendingPathComponent("CACHEDIR.TAG"))
            try Data(count: 5_000).write(to: cache.appendingPathComponent("blob.bin"))
        }
        let c = try XCTUnwrap(find(root, "weird-cache"))
        XCTAssertEqual(c.reclaim?.signal, .cachedirTag)
        XCTAssertEqual(c.category, .cache)
        // blob.bin would be `.other` by extension, but a CACHEDIR.TAG dir rolls
        // every file up to `.cache` (the late-override rebucket path).
        XCTAssertEqual(Set(c.fileBytes.keys), [.cache],
                       "a CACHEDIR.TAG dir's own files attribute to .cache, not their extension")
    }

    /// Exactly the 43-byte signature with no trailing bytes — the common real
    /// CACHEDIR.TAG shape and the zero-margin boundary of `validCachedirTag`.
    func testCachedirTagExactSignatureNoTrailingBytes() throws {
        let root = try scanTree { base, fm in
            let cache = base.appendingPathComponent("tight-cache")
            try fm.createDirectory(at: cache, withIntermediateDirectories: true)
            try Data("Signature: 8a477f597d28d172789f06886806bc55".utf8)
                .write(to: cache.appendingPathComponent("CACHEDIR.TAG"))
            try Data(count: 3_000).write(to: cache.appendingPathComponent("x.bin"))
        }
        XCTAssertEqual(find(root, "tight-cache")?.reclaim?.signal, .cachedirTag)
    }

    /// A reclaim root nested under another must NOT be a separate target —
    /// descendants carry the inherited override, so the accounting a future purge
    /// relies on (`reclaimRoots`/`reclaimBytes`) counts the outer one exactly once.
    func testNestedReclaimRootIsNotDoubleCounted() throws {
        let root = try scanTree { base, fm in
            // An inner node_modules whose own name would otherwise flag high.
            try fm.createDirectory(at: base.appendingPathComponent("node_modules/pkg/node_modules"),
                                   withIntermediateDirectories: true)
            try Data(count: 7_000).write(to: base.appendingPathComponent("node_modules/pkg/node_modules/dep.bin"))
        }
        let outer = try XCTUnwrap(find(root, "node_modules"))
        XCTAssertNotNil(outer.reclaim, "the outer node_modules is the reclaim target")
        func assertNoReclaimBelow(_ n: DirNode) {
            for c in n.children {
                XCTAssertNil(c.reclaim, "\(c.name) under a reclaim root must not be its own target")
                assertNoReclaimBelow(c)
            }
        }
        assertNoReclaimBelow(outer)
        XCTAssertEqual(Derive.reclaimRoots(root).count, 1, "exactly one reclaim target")
        XCTAssertEqual(Derive.reclaimBytes(root), outer.size, "no double counting")
    }

    /// A Ruby `vendor/` beside a `Gemfile` is hand-maintained content, not a
    /// Bundler artifact — it must stay medium, never lifted to high by the manifest.
    func testGemfileDoesNotLiftVendorToHigh() throws {
        let root = try scanTree { base, fm in
            try fm.createDirectory(at: base.appendingPathComponent("rails/vendor"),
                                   withIntermediateDirectories: true)
            try Data("source 'https://rubygems.org'".utf8)
                .write(to: base.appendingPathComponent("rails/Gemfile"))
            try Data(count: 4_000).write(to: base.appendingPathComponent("rails/vendor/asset.bin"))
        }
        let vendor = find(root, "vendor")
        XCTAssertEqual(vendor?.reclaim?.confidence, .medium)
        XCTAssertEqual(vendor?.reclaim?.signal, .knownName)
    }

    func testInvalidCachedirTagIgnored() throws {
        let root = try scanTree { base, fm in
            let dir = base.appendingPathComponent("notes")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("not a real cache tag".utf8).write(to: dir.appendingPathComponent("CACHEDIR.TAG"))
            try Data(count: 5_000).write(to: dir.appendingPathComponent("note.txt"))
        }
        XCTAssertNil(find(root, "notes")?.reclaim, "a bogus CACHEDIR.TAG must not flag the dir")
    }
}

final class DerivationsTests: XCTestCase {
    private let GB: Int64 = 1_073_741_824

    func testReclaimBytesCountsReclaimableSubtrees() {
        let root = MockTree.make()
        let recl = Derive.reclaimBytes(root)
        // node_modules (8+6) + .next (3) + dist (1) + .venv (4) + wandb (2)
        // + Caches (11) + DerivedData (16) + docker build cache (9) + .Trash (5)
        XCTAssertEqual(recl, (8 + 6 + 3 + 1 + 4 + 2 + 11 + 16 + 9 + 5) * GB)
    }

    func testTypeSizesSumToTotal() {
        let root = MockTree.make()
        let sizes = Derive.typeSizes(root)
        XCTAssertEqual(sizes.values.reduce(0, +), root.size,
                       "every leaf byte is attributed to exactly one category")
    }

    func testDepsAggregatedAcrossProjects() {
        let root = MockTree.make()
        let sizes = Derive.typeSizes(root)
        // node_modules (8 + 6) + .venv (4) all roll up to deps.
        XCTAssertEqual(sizes[.deps], (8 + 6 + 4) * GB)
    }

    func testTypeLocationsFindsEveryNodeModules() {
        let root = MockTree.make()
        let locs = Derive.typeLocations(root, .deps)
        let names = Set(locs.map { $0.node.name })
        XCTAssertTrue(names.contains("node_modules"))
        XCTAssertTrue(names.contains(".venv"))
        // sorted descending by size
        let sizes = locs.map { $0.size }
        XCTAssertEqual(sizes, sizes.sorted(by: >))
    }

    func testPathToRoot() {
        let root = MockTree.make()
        let library = root.children.first { $0.name == "Library" }!
        let caches = library.children.first { $0.name == "Caches" }!
        let path = Derive.pathTo(caches).map { $0.name }
        XCTAssertEqual(path, ["alex", "Library", "Caches"])
    }
}

final class TreeScannerTests: XCTestCase {
    func testScansRealTempTree() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskkit-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: base.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try Data(count: 20_000).write(to: base.appendingPathComponent("node_modules/dep.bin"))
        try Data(count: 8_000).write(to: base.appendingPathComponent("readme.md"))
        defer { try? FileManager.default.removeItem(at: base) }

        let root = TreeScanner.scan(base.path)
        XCTAssertGreaterThan(root.size, 0)

        let nm = root.children.first { $0.name == "node_modules" }
        XCTAssertNotNil(nm)
        XCTAssertEqual(nm?.category, .deps)
        XCTAssertEqual(nm?.isReclaimable, true)

        // The .md file in the root is categorized as docs by extension.
        let sizes = Derive.typeSizes(root)
        XCTAssertNotNil(sizes[.docs])
        XCTAssertNotNil(sizes[.deps])
    }

    func testFormatSize() {
        XCTAssertEqual(formatSize(0), "0 KB")
        XCTAssertEqual(formatSize(2 * 1_073_741_824), "2.0 GB")
        XCTAssertTrue(formatSize(5 * 1_048_576).hasSuffix("MB"))
    }

    /// The streaming scan must report every top-level subtree exactly once and,
    /// once reassembled, match the blocking scan byte-for-byte. This exercises
    /// the shared work-stealing queue and the per-subtree completion tracker.
    func testStreamingMatchesBlockingScan() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("diskkit-stream-\(UUID().uuidString)")
        let fm = FileManager.default
        // A deliberately lopsided tree: nested dirs, an override dir, an empty
        // dir, and a loose top-level file (which belongs to the root, not a
        // subtree).
        try fm.createDirectory(at: base.appendingPathComponent("alpha/sub/deep"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: base.appendingPathComponent("beta/node_modules"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: base.appendingPathComponent("gamma"),
                               withIntermediateDirectories: true)
        try Data(count: 30_000).write(to: base.appendingPathComponent("alpha/sub/deep/a.bin"))
        try Data(count: 10_000).write(to: base.appendingPathComponent("alpha/b.bin"))
        try Data(count: 50_000).write(to: base.appendingPathComponent("beta/node_modules/dep.bin"))
        try Data(count: 5_000).write(to: base.appendingPathComponent("loose.md"))
        defer { try? fm.removeItem(at: base) }

        let blocking = TreeScanner.scan(base.path)

        // Collect the streamed pieces (callbacks fire on scanner threads). The
        // scan is synchronous, so everything is in by the time it returns.
        let sink = StreamSink()
        TreeScanner.scanStreaming(
            base.path, progress: ScanProgress(),
            onRoot:  { node in sink.setRoot(node) },
            onChild: { i, node in sink.addChild(i, node) },
            onDone:  { sink.finish() }
        )

        let rootNode = try XCTUnwrap(sink.root)
        let placeholders = rootNode.children
        XCTAssertEqual(sink.doneCount, 1, "onDone fires exactly once")
        XCTAssertEqual(placeholders.count, blocking.children.count,
                       "one placeholder per top-level directory")
        XCTAssertEqual(Set(sink.children.keys), Set(0..<placeholders.count),
                       "every top-level subtree reported exactly once, no gaps or repeats")

        // Reassemble in placeholder order and compare to the blocking scan.
        let ordered = (0..<placeholders.count).map { sink.children[$0]! }
        let streamed = DirNode(name: rootNode.name, category: rootNode.category,
                               isReclaimable: rootNode.isReclaimable,
                               fileBytes: rootNode.fileBytes, children: ordered)
        XCTAssertEqual(streamed.size, blocking.size,
                       "streamed tree totals the same as the blocking scan")

        // Per-subtree sizes line up by name (order may differ between the two).
        let streamedByName = Dictionary(uniqueKeysWithValues: streamed.children.map { ($0.name, $0.size) })
        for c in blocking.children {
            XCTAssertEqual(streamedByName[c.name], c.size, "subtree \(c.name) sizes match")
        }
        // The override dir's contents roll up to .deps in both.
        XCTAssertEqual(Derive.typeSizes(streamed)[.deps], Derive.typeSizes(blocking)[.deps])
    }
}
