import XCTest
@testable import MenuMateCore

final class DeclutterTests: XCTestCase {
    func testAppleAndMenuMateAreNotThirdParty() {
        XCTAssertFalse(Declutter.isThirdParty(bundleID: "com.apple.Preview",
                                              bundlePath: "/System/Applications/Preview.app"))
        XCTAssertFalse(Declutter.isThirdParty(bundleID: "com.menumate.app.FinderExtension", bundlePath: nil))
        XCTAssertFalse(Declutter.isThirdParty(bundleID: nil,
                                              bundlePath: "/System/Library/Services/X.service"))
    }

    func testThirdPartyDetected() {
        XCTAssertTrue(Declutter.isThirdParty(bundleID: "com.dropbox.xxx", bundlePath: "/Applications/Dropbox.app"))
        XCTAssertTrue(Declutter.isThirdParty(bundleID: nil, bundlePath: "/Applications/Foo.app"))
    }

    func testUnknownNotPreselected() {
        XCTAssertFalse(Declutter.isThirdParty(bundleID: nil, bundlePath: nil))
    }
}
