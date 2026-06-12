import XCTest

@testable import DiskKit
@testable import Halo

/// Lifecycle of real (filesystem-backed) scans driven through `ScanModel`:
/// supersession, error surfacing, and the unreadable-dir disclosure.
@MainActor
final class ScanLifecycleTests: XCTestCase {

    private func makeTempDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("halo-scan-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func waitForScanToFinish(
        _ model: ScanModel,
        timeout: TimeInterval = 15
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while model.scanning {
            if Date() > deadline { return XCTFail("scan did not finish in \(timeout)s") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Starting a second scan while one is in flight must supersede the first:
    /// the first scan's late events (including its `finishScan`) must not
    /// clobber the second scan's tree. The first root is made big enough that
    /// it is still mid-walk when the second, tiny scan completes.
    func testSecondScanSupersedesFirst() async throws {
        let fm = FileManager.default
        let big = try makeTempDir("big")
        for i in 0..<40 {
            let dir = big.appendingPathComponent("d\(i)/sub/deep")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(count: 2_000).write(to: dir.appendingPathComponent("f.bin"))
        }
        let small = try makeTempDir("small")
        try Data(count: 1_000).write(to: small.appendingPathComponent("only.bin"))

        let model = ScanModel()
        model.scan(path: big.path)
        model.scan(path: small.path)

        try await waitForScanToFinish(model)
        // Give the superseded scan's stragglers every chance to (wrongly) land.
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(
            model.root?.name, small.lastPathComponent,
            "the second scan's tree must win")
        XCTAssertEqual(
            model.currentURL.path, small.path,
            "the model must point at the second scan's root")
        XCTAssertFalse(model.scanning)
    }

    /// A real scan leads the crumbs with the root's *actual* volume name, and
    /// breadcrumb navigation accounts for that extra leading crumb.
    func testCrumbsLeadWithRealVolumeName() async throws {
        let base = try makeTempDir("vol")
        try FileManager.default.createDirectory(
            at: base.appendingPathComponent("sub"),
            withIntermediateDirectories: true)
        try Data(count: 1_000).write(to: base.appendingPathComponent("sub/f.bin"))

        let model = ScanModel()
        model.scan(path: base.path)
        try await waitForScanToFinish(model)

        let volume = try XCTUnwrap(
            try base.resourceValues(forKeys: [.volumeNameKey]).volumeName,
            "the temp dir lives on a named volume")
        XCTAssertEqual(model.crumbs.first, volume, "the leading crumb is the real volume")
        XCTAssertEqual(model.crumbs.count, 2, "volume + scan root")

        // Drill in, then navigate back via the crumb *after* the volume crumb.
        let sub = model.current!.children.first { $0.name == "sub" }!
        model.jump(to: sub)
        XCTAssertEqual(model.crumbs.count, 3)
        model.goTo(crumb: 1)
        XCTAssertEqual(
            model.current?.name, model.root?.name,
            "crumb 1 (after the volume) is the scan root")
    }

    /// `rescan()` re-reads the same root from disk and restores the navigation
    /// scope, picking up changes made since the last scan.
    func testRescanPicksUpChangesAndKeepsScope() async throws {
        let fm = FileManager.default
        let base = try makeTempDir("rescan")
        let sub = base.appendingPathComponent("sub")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data(count: 4_000).write(to: sub.appendingPathComponent("a.bin"))

        let model = ScanModel()
        model.scan(path: base.path)
        try await waitForScanToFinish(model)
        model.jump(to: model.current!.children.first { $0.name == "sub" }!)
        let sizeBefore = model.current!.size

        try Data(count: 8_000).write(to: sub.appendingPathComponent("b.bin"))
        model.rescan()
        try await waitForScanToFinish(model)

        XCTAssertEqual(model.current?.name, "sub", "scope survives the rescan")
        XCTAssertGreaterThan(model.current!.size, sizeBefore, "the new file is counted")
    }

    /// An unreadable scan root must surface as `scanError`, not as a silent
    /// empty donut.
    func testUnreadableRootSurfacesScanError() async throws {
        let fm = FileManager.default
        let locked = try makeTempDir("locked")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: locked.path)
        }

        let model = ScanModel()
        model.scan(path: locked.path)
        try await waitForScanToFinish(model)

        XCTAssertNotNil(model.scanError, "an unreadable root must be reported")
    }

    /// Unreadable directories inside the tree must be disclosed via
    /// `skippedDirs` so the UI can hint at Full Disk Access.
    func testSkippedDirsAreExposed() async throws {
        let fm = FileManager.default
        let base = try makeTempDir("skips")
        let locked = base.appendingPathComponent("locked")
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(count: 3_000).write(to: base.appendingPathComponent("readable.bin"))
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: locked.path)
        }

        let model = ScanModel()
        model.scan(path: base.path)
        try await waitForScanToFinish(model)

        XCTAssertEqual(model.skippedDirs, 1, "the unreadable dir is disclosed")
        XCTAssertNil(model.scanError, "a partial scan is not an error")
    }
}
