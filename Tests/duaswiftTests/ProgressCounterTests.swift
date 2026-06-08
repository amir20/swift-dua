import XCTest
@testable import duaswift

final class ProgressCounterTests: XCTestCase {
    func testAccumulatesAndSnapshots() {
        let c = ProgressCounter()
        c.update(files: 3, bytes: 100, current: "/a")
        c.update(files: 2, bytes: 50, current: "/b")
        let s = c.snapshot()
        XCTAssertEqual(s.files, 5)
        XCTAssertEqual(s.bytes, 150)
        XCTAssertEqual(s.current, "/b")
    }

    func testConcurrentUpdatesAreConsistent() {
        let c = ProgressCounter()
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            c.update(files: 1, bytes: 1, current: "/x")
        }
        let s = c.snapshot()
        XCTAssertEqual(s.files, 1000)
        XCTAssertEqual(s.bytes, 1000)
    }
}
