import XCTest
@testable import MenuMateCore

final class SmokeTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(MenuMateCoreInfo.version, "0.1.0")
    }
}
