import XCTest
@testable import CSGOHelperCore

final class PatternTests: XCTestCase {
    func testAllProfilesLoadAndValidate() throws {
        let store = try makePatternStore()
        XCTAssertEqual(store.weapons.count, 33)
        XCTAssertEqual(Set(store.weapons.map(\.id)), Set(SelfTest.expectedWeaponIDs))
        XCTAssertGreaterThanOrEqual(store.measuredCount, 15)
        XCTAssertEqual(store.measuredCount + store.heuristicCount, 33)
    }

    func testEveryPatternStartsWithFirstBulletAtZero() throws {
        let store = try makePatternStore()
        for weapon in store.weapons {
            XCTAssertEqual(weapon.cumulativeDegrees.count, weapon.magazine, weapon.id)
            XCTAssertEqual(weapon.cumulativeDegrees.first, PatternPoint(x: 0, y: 0), weapon.id)
            XCTAssertEqual(weapon.perShotDegrees.count, weapon.cumulativeDegrees.count - 1, weapon.id)
        }
    }

    func testAKInterpolation() throws {
        let store = try makePatternStore()
        let ak = try XCTUnwrap(store.weapon(id: "ak47"))
        XCTAssertEqual(ak.cumulative(at: 0), PatternPoint(x: 0, y: 0))
        XCTAssertEqual(ak.cumulative(at: ak.shotInterval), ak.cumulativeDegrees[1])
        let mid = ak.cumulative(at: ak.shotInterval * 0.5)
        XCTAssertEqual(mid.x, ak.cumulativeDegrees[1].x / 2, accuracy: 1e-9)
        XCTAssertEqual(mid.y, ak.cumulativeDegrees[1].y / 2, accuracy: 1e-9)
        XCTAssertEqual(ak.cumulative(at: 999), ak.cumulativeDegrees.last)
    }

    func testAliasesAndCycling() throws {
        let store = try makePatternStore()
        XCTAssertEqual(store.weapon(id: "weapon_ak47")?.id, "ak47")
        XCTAssertEqual(store.weapon(id: "m4a1_silencer")?.id, "m4a1s")
        let first = store.weapons[0]
        let next = store.next(after: first.id)
        XCTAssertEqual(store.previous(before: next.id).id, first.id)
    }

    func testHeuristicProvenanceIsExplicit() throws {
        let store = try makePatternStore()
        for weapon in store.weapons {
            if weapon.isMeasured {
                XCTAssertTrue(weapon.patternSource.lowercased().contains("spray.training"), weapon.id)
            } else {
                XCTAssertTrue(weapon.patternSource.lowercased().contains("fallback"), weapon.id)
                XCTAssertEqual(weapon.quality, .heuristic)
            }
        }
    }
}
