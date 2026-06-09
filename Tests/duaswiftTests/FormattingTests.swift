import XCTest
@testable import duaswift

final class FormattingTests: XCTestCase {
    func testGrouped() {
        XCTAssertEqual(grouped(0), "0")
        XCTAssertEqual(grouped(999), "999")
        XCTAssertEqual(grouped(1000), "1,000")
        XCTAssertEqual(grouped(1234567), "1,234,567")
    }

    func testFormatMetric() {
        XCTAssertEqual(formatMetric(0), "0 B")
        XCTAssertEqual(formatMetric(999), "999 B")
        XCTAssertEqual(formatMetric(1000), "1.00 KB")
        XCTAssertEqual(formatMetric(1_500_000), "1.50 MB")
    }

    func testRenderSizeRespectsFormat() {
        XCTAssertEqual(renderSize(1000, format: .metric), "1.00 KB")
        XCTAssertEqual(renderSize(1000, format: .bytes), "1000 b")
    }

    func testTruncatePath() {
        XCTAssertEqual(truncatePath("short", max: 44), "short")
        let long = String(repeating: "a", count: 50)
        let truncated = truncatePath(long, max: 44)
        XCTAssertEqual(truncated.count, 44)
        XCTAssertTrue(truncated.hasPrefix("…"))
    }

    func testLeftPad() {
        XCTAssertEqual(leftPad("7", to: 4), "   7")
        XCTAssertEqual(leftPad("12345", to: 4), "12345")
    }
}
