import XCTest
@testable import CSGOHelperCore

final class SmokeTests: XCTestCase {
    func testDefaultsValidate() throws {
        let config = try HelperConfig().validated()
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.recoil.weapon, "ak47")
    }
}
