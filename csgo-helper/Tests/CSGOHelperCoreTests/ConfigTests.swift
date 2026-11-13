import XCTest
@testable import CSGOHelperCore

final class ConfigTests: XCTestCase {
    func testExampleConfigLoadsAndValidates() throws {
        let data = try Data(contentsOf: TestPaths.configExample)
        let config = try JSONDecoder().decode(HelperConfig.self, from: data)
        let validated = try config.validated()
        XCTAssertEqual(validated.recoil.weapon, "ak47")
        XCTAssertEqual(validated.hotkeys.toggleAll, "shift+i")
        XCTAssertEqual(validated.bunnyHop.tickRate, 128)
    }

    func testMinimalConfigUsesDefaults() throws {
        let data = Data(#"{"version":1,"sensitivity":3.0}"#.utf8)
        let config = try JSONDecoder().decode(HelperConfig.self, from: data)
        XCTAssertEqual(config.mYaw, 0.022)
        XCTAssertEqual(config.snapTap.holdMs, 22)
        XCTAssertEqual(config.feedback.textMode, .keycode)
        XCTAssertEqual(config.logging.level, .info)
        XCTAssertNoThrow(try config.validated())
    }

    func testRoundTrip() throws {
        let config = try HelperConfig().validated()
        let data = try config.jsonData()
        let decoded = try JSONDecoder().decode(HelperConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testInvalidValuesRejected() throws {
        var config = HelperConfig()
        config.sensitivity = 0
        XCTAssertThrowsError(try config.validated())
        config = HelperConfig()
        config.bunnyHop.tickRate = 100
        XCTAssertThrowsError(try config.validated())
        config = HelperConfig()
        config.snapTap.holdMs = 1
        XCTAssertThrowsError(try config.validated())
        config = HelperConfig()
        config.hotkeys.recoil = config.hotkeys.toggleAll
        XCTAssertThrowsError(try config.validated())
    }

    func testConfigStoreCreatesAndReloads() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("csgo-helper-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ConfigStore(url: url)
        let loaded = try store.loadOrCreate()
        XCTAssertTrue(loaded.created)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let second = try store.loadOrCreate()
        XCTAssertFalse(second.created)
        XCTAssertEqual(second.config, loaded.config)
    }

    func testHotkeys() throws {
        let hotkey = try Hotkey.parse("shift+i")
        XCTAssertTrue(hotkey.matches(keyCode: KeyCode.i, flags: .maskShift))
        XCTAssertFalse(hotkey.matches(keyCode: KeyCode.i, flags: []))
        XCTAssertFalse(hotkey.matches(keyCode: KeyCode.i, flags: [.maskShift, .maskControl]))
        XCTAssertThrowsError(try Hotkey.parse("i"))
        XCTAssertThrowsError(try Hotkey.parse("shift+not-a-key"))
        let set = try HotkeyParser.parseAll(HotkeyConfig())
        XCTAssertEqual(set.nextWeapon.keyCode, KeyCode.rightBracket)
        XCTAssertTrue(set.nextWeapon.shift)
    }

    func testCoordinateConversion() {
        let injector = EventInjector(sensitivity: 2.5, mYaw: 0.022, mPitch: 0.022, dryRun: true)
        XCTAssertEqual(injector.counts(forDegreesX: 1, y: 1).x, 18.181818, accuracy: 1e-4)
        let config = HelperConfig()
        XCTAssertEqual(config.sensitivity, 2.5)
    }
}
