import XCTest
import Foundation
@testable import duaswift

final class DiskScannerTests: XCTestCase {

    /// Creates a unique temporary directory; caller scans it.
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("duaswift-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ url: URL, bytes: Int) throws {
        try Data(count: bytes).write(to: url)
    }

    /// The scanner descends into sub-directories and sums regular-file apparent
    /// sizes. Two trees with identical structure (same entry names) where only
    /// one file's *size* differs differ in apparent total by exactly that
    /// difference — the directory inode sizes are identical because the entries
    /// match, so they cancel. (Adding/removing a file would instead perturb the
    /// containing directory's own st_size, e.g. +32 bytes on APFS.)
    func testApparentSizeAggregatesNestedFiles() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        // Tree A: root/sub/data.bin (4096 bytes)
        let treeA = base.appendingPathComponent("a")
        try FileManager.default.createDirectory(at: treeA.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        try writeFile(treeA.appendingPathComponent("sub/data.bin"), bytes: 4096)

        // Tree B: identical names, but data.bin is 8192 bytes.
        let treeB = base.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: treeB.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        try writeFile(treeB.appendingPathComponent("sub/data.bin"), bytes: 8192)

        let scanner = DiskScanner(apparent: true, countHardLinks: false, threadCount: 4)
        let a = scanner.scan(treeA.path)
        let b = scanner.scan(treeB.path)

        XCTAssertEqual(b.size - a.size, 4096, "a file 4096 bytes larger should raise the apparent total by exactly 4096")
        XCTAssertEqual(a.entries, 3, "root dir + sub dir + data.bin = 3 entries (proves nested descent)")
        XCTAssertEqual(b.entries, 3)
    }

    /// With a hard link present, counting links adds the file's size a second
    /// time; de-duplicating (the default) does not.
    func testHardLinkDeduplication() throws {
        let base = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: base) }

        let f = base.appendingPathComponent("f.bin")
        try writeFile(f, bytes: 8192)
        let g = base.appendingPathComponent("g.bin")
        try FileManager.default.linkItem(at: f, to: g)   // hard link, nlink == 2

        let dedup = DiskScanner(apparent: true, countHardLinks: false, threadCount: 4)
        let counted = DiskScanner(apparent: true, countHardLinks: true, threadCount: 4)

        let dedupResult = dedup.scan(base.path)
        let countedResult = counted.scan(base.path)

        XCTAssertEqual(countedResult.size - dedupResult.size, 8192,
                       "counting hard links should add the 8192-byte file a second time")
    }

    /// A non-existent path scans to zero rather than crashing.
    func testMissingPathIsZero() {
        let scanner = DiskScanner(apparent: true, countHardLinks: false, threadCount: 4)
        let r = scanner.scan("/no/such/path/duaswift-\(UUID().uuidString)")
        XCTAssertEqual(r.size, 0)
        XCTAssertEqual(r.entries, 0)
    }
}
