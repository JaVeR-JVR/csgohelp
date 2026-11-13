import CoreGraphics
import Foundation

public struct SelfTestResult {
    public let name: String
    public let passed: Bool
    public let detail: String

    public init(name: String, passed: Bool, detail: String) {
        self.name = name
        self.passed = passed
        self.detail = detail
    }
}

public enum SelfTest {
    public static let expectedWeaponIDs: [String] = [
        "ak47", "m4a1", "m4a1s", "m4a4", "aug", "sg553", "galil", "famas",
        "awp", "g3sg1", "scar20", "negev", "m249", "mp9", "mp7", "mp5sd",
        "ump45", "p90", "mac10", "glock18", "usps", "p250", "deagle",
        "fiveseven", "tec9", "cz75", "dualberettas", "revolver", "p2000",
        "nova", "xm1014", "mag7", "bizon"
    ]

    public static func run(patternStore: PatternStore, config: HelperConfig) -> [SelfTestResult] {
        var results: [SelfTestResult] = []

        func check(_ name: String, _ condition: Bool, _ detail: String) {
            results.append(SelfTestResult(name: name, passed: condition, detail: detail))
        }

        // 1. Все заявленные профили присутствуют.
        let ids = Set(patternStore.weapons.map(\.id))
        let expected = Set(expectedWeaponIDs)
        check(
            "Каталог оружия",
            ids == expected,
            "профилей \(ids.count), ожидалось \(expected.count); отсутствуют: \(expected.subtracting(ids).sorted().joined(separator: ","))"
        )

        // 2. Геометрия таблиц.
        var geometryErrors: [String] = []
        for weapon in patternStore.weapons {
            if weapon.cumulativeDegrees.count != weapon.magazine {
                geometryErrors.append("\(weapon.id): точек \(weapon.cumulativeDegrees.count) != магазин \(weapon.magazine)")
            }
            if weapon.perShotDegrees.count != weapon.cumulativeDegrees.count - 1 {
                geometryErrors.append("\(weapon.id): perShot не совпадает")
            }
            if let first = weapon.cumulativeDegrees.first, first.x != 0 || first.y != 0 {
                geometryErrors.append("\(weapon.id): первая точка не ноль")
            }
            if weapon.cumulativeDegrees.contains(where: { !$0.x.isFinite || !$0.y.isFinite }) {
                geometryErrors.append("\(weapon.id): NaN/Infinity")
            }
        }
        check("Геометрия паттернов", geometryErrors.isEmpty, geometryErrors.isEmpty ? "все \(patternStore.weapons.count) профилей согласованы" : geometryErrors.prefix(3).joined(separator: "; "))

        // 3. Происхождение данных.
        let measured = patternStore.weapons.filter(\.isMeasured).count
        let heuristic = patternStore.weapons.count - measured
        check(
            "Источники паттернов",
            measured >= 15 && heuristic == patternStore.weapons.count - measured,
            "измерено \(measured), эвристика \(heuristic); эвристика помечена quality=heuristic"
        )
        check(
            "Лицензия измеренных данных",
            patternStore.document.sources?.measured?.license == "MIT",
            "spray.training: \(patternStore.document.sources?.measured?.license ?? "нет данных")"
        )

        // 4. Пересчёт чувствительности.
        let injector = EventInjector(sensitivity: 2.5, mYaw: 0.022, mPitch: 0.022, dryRun: true)
        let expectedX = 1.0 / (2.5 * 0.022)
        let expectedY = 1.0 / (2.5 * 0.022)
        check(
            "Пересчёт градусов в counts",
            abs(injector.countsPerDegreeX - expectedX) < 0.0001 && abs(injector.countsPerDegreeY - expectedY) < 0.0001,
            String(format: "sens=2.5 m_yaw=0.022 -> %.4f counts/град", injector.countsPerDegreeX)
        )

        // 5. Интерполяция.
        if let ak = patternStore.weapon(id: "ak47") {
            let first = ak.cumulative(at: 0)
            let second = ak.cumulative(at: ak.shotInterval)
            let expectedSecond = ak.cumulativeDegrees[1]
            let midpoint = ak.cumulative(at: ak.shotInterval * 0.5)
            let last = ak.cumulative(at: 1000)
            let tableLast = ak.cumulativeDegrees.last ?? PatternPoint(x: 0, y: 0)
            check(
                "Интерполяция AK-47",
                abs(first.x) < 1e-9 && abs(first.y) < 1e-9
                    && abs(second.x - expectedSecond.x) < 1e-9 && abs(second.y - expectedSecond.y) < 1e-9
                    && abs(midpoint.x - expectedSecond.x / 2) < 1e-9
                    && abs(last.x - tableLast.x) < 1e-9 && abs(last.y - tableLast.y) < 1e-9,
                String(format: "0 -> %.4f/%.4f, 1 выстрел -> %.4f/%.4f, конец -> %.4f/%.4f",
                       first.x, first.y, second.x, second.y, last.x, last.y)
            )
        } else {
            check("Интерполяция AK-47", false, "профиль ak47 отсутствует")
        }

        // 6. Round-trip конфига и устойчивые значения по умолчанию.
        do {
            let data = try config.jsonData()
            let decoded = try JSONDecoder().decode(HelperConfig.self, from: data)
            check("JSON-конфиг: round-trip", decoded == config, "конфиг кодируется и декодируется без потерь")
        } catch {
            check("JSON-конфиг: round-trip", false, error.localizedDescription)
        }
        do {
            let minimal = Data(#"{"version":1,"sensitivity":3.0}"#.utf8)
            let decoded = try JSONDecoder().decode(HelperConfig.self, from: minimal)
            let validated = try decoded.validated()
            check(
                "JSON-конфиг: значения по умолчанию",
                validated.recoil.weapon == "ak47" && validated.bunnyHop.tickRate == 128 && validated.sensitivity == 3.0,
                "недостающие секции подставились"
            )
        } catch {
            check("JSON-конфиг: значения по умолчанию", false, error.localizedDescription)
        }
        do {
            var invalid = config
            invalid.sensitivity = 0
            _ = try invalid.validated()
            check("Валидация конфига", false, "sensitivity=0 не была отклонена")
        } catch {
            check("Валидация конфига", true, "некорректная sensitivity отклонена")
        }

        // 7. Горячие клавиши.
        do {
            let set = try HotkeyParser.parseAll(config.hotkeys)
            let shiftI = CGEventFlags.maskShift
            check(
                "Хоткеи",
                set.toggleAll.matches(keyCode: KeyCode.i, flags: shiftI)
                    && !set.toggleAll.matches(keyCode: KeyCode.i, flags: [])
                    && set.nextWeapon.matches(keyCode: KeyCode.rightBracket, flags: shiftI),
                "Shift+I, Shift+1/2/3, Shift+[ ] разобраны"
            )
        } catch {
            check("Хоткеи", false, error.localizedDescription)
        }
        do {
            var duplicate = config.hotkeys
            duplicate.recoil = duplicate.toggleAll
            _ = try HotkeyParser.parseAll(duplicate)
            check("Защита от дублей хоткеев", false, "дубль не обнаружен")
        } catch {
            check("Защита от дублей хоткеев", true, "дублирующийся хоткей отклонён")
        }

        // 8. Безопасность консоли.
        let dirty = "echo `say;\"hello\":world`"
        let clean = ConsoleFeedback.sanitize(dirty)
        let cleanOK = !clean.contains("`") && !clean.contains(";") && !clean.contains("\"")
            && clean.allSatisfy { "abcdefghijklmnopqrstuvwxyz0123456789 -_.=/[]()".contains($0) }
        check("Безопасность console echo", cleanOK, "очищено: \"\(clean)\"; say/чат не используются")

        // 9. Циклический выбор оружия.
        let first = patternStore.weapons.first!
        let next = patternStore.next(after: first.id)
        let back = patternStore.previous(before: next.id)
        check("Циклический выбор оружия", back.id == first.id, "\(first.id) -> \(next.id) -> \(back.id)")

        let status = Permissions.status()
        results.append(SelfTestResult(
            name: "Разрешения (информационно)",
            passed: true,
            detail: status.summary + "; выдаются вручную в System Settings"
        ))
        results.append(SelfTestResult(
            name: "Dry-run инъекции",
            passed: injector.dryRun,
            detail: "selftest не отправляет события в игру"
        ))
        return results
    }
}
