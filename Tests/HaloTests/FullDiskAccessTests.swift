import XCTest

@testable import Halo

@MainActor
final class FullDiskAccessTests: XCTestCase {
    func testBannerShowsOnlyWhenDeniedAndNotDismissed() {
        let model = ScanModel()

        model.fullDiskAccess = false
        model.fdaBannerDismissed = false
        XCTAssertTrue(model.showFDABanner, "denied + not dismissed should show the banner")

        model.fullDiskAccess = true
        XCTAssertFalse(model.showFDABanner, "granted access hides the banner")

        model.fullDiskAccess = false
        model.dismissFDABanner()
        XCTAssertFalse(model.showFDABanner, "dismissing hides it even while still denied")
    }

    func testSettingsURLTargetsFullDiskAccessPane() {
        XCTAssertEqual(
            FullDiskAccess.settingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }
}
