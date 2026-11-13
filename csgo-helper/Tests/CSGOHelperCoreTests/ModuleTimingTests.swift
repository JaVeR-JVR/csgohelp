import CoreGraphics
import XCTest
@testable import CSGOHelperCore

final class SnapTapTests: XCTestCase {
    private var injector = RecordingInjector()

    override func setUp() {
        super.setUp()
        injector = RecordingInjector()
        Logger.shared.configure(level: .off, file: nil, console: false)
    }

    private func makeSnapTap(enabled: Bool = true) -> SnapTap {
        let config = SnapTapConfig(
            enabled: enabled,
            socdEnabled: true,
            brakeTapEnabled: true,
            holdMs: 22,
            cooldownMs: 65,
            leftKeyCode: KeyCode.a,
            rightKeyCode: KeyCode.d
        )
        return SnapTap(config: config, injector: injector)
    }

    func testSOCDLastKeyWinsAndRestoresHeldKey() {
        let snapTap = makeSnapTap()

        snapTap.handleKey(code: KeyCode.a, down: true, at: 1.0, focused: true)
        XCTAssertTrue(injector.keys.isEmpty, "первое нажатие не требует коррекции")

        snapTap.handleKey(code: KeyCode.d, down: true, at: 1.1, focused: true)
        XCTAssertEqual(injector.keys, [.init(code: KeyCode.a, down: false, shift: false)],
                       "A должна быть отпущена в пользу D")

        snapTap.handleKey(code: KeyCode.d, down: false, at: 1.2, focused: true)
        XCTAssertEqual(injector.keys.last, .init(code: KeyCode.a, down: true, shift: false),
                       "после отпускания D всё ещё зажатая A возвращается")

        snapTap.update(now: 5.0)
        XCTAssertEqual(injector.keys.count, 2, "восстановленная клавиша не должна отпускаться по таймеру")

        snapTap.handleKey(code: KeyCode.a, down: false, at: 1.3, focused: true)
        XCTAssertEqual(injector.keys.last, .init(code: KeyCode.d, down: true, shift: false),
                       "отпускание последней клавиши даёт тормозной тап")

        snapTap.update(now: 1.321)
        XCTAssertEqual(injector.keys.count, 3)
        snapTap.update(now: 1.322)
        XCTAssertEqual(injector.keys.last, .init(code: KeyCode.d, down: false, shift: false))
    }

    func testBrakeTapRespectsCooldownAndHoldTime() {
        let snapTap = makeSnapTap()

        snapTap.handleKey(code: KeyCode.a, down: true, at: 10.0, focused: true)
        snapTap.handleKey(code: KeyCode.a, down: false, at: 10.1, focused: true)
        XCTAssertEqual(injector.keys, [.init(code: KeyCode.d, down: true, shift: false)])

        snapTap.update(now: 10.121)
        XCTAssertEqual(injector.keys.count, 1, "тап должен длиться holdMs")

        snapTap.update(now: 10.122)
        XCTAssertEqual(injector.keys.last, .init(code: KeyCode.d, down: false, shift: false))

        // Второй тап в пределах cooldownMs игнорируется.
        snapTap.handleKey(code: KeyCode.a, down: true, at: 10.15, focused: true)
        snapTap.handleKey(code: KeyCode.a, down: false, at: 10.16, focused: true)
        XCTAssertEqual(injector.keys.count, 2)

        // После cooldown тап снова разрешён.
        snapTap.handleKey(code: KeyCode.a, down: true, at: 10.3, focused: true)
        snapTap.handleKey(code: KeyCode.a, down: false, at: 10.31, focused: true)
        XCTAssertEqual(injector.keys.count, 3)
        XCTAssertEqual(injector.keys.last, .init(code: KeyCode.d, down: true, shift: false))
    }

    func testDisabledAndUnfocusedNeverInject() {
        let disabled = makeSnapTap(enabled: false)
        disabled.handleKey(code: KeyCode.a, down: true, at: 0, focused: true)
        disabled.handleKey(code: KeyCode.d, down: true, at: 0.1, focused: true)
        disabled.handleKey(code: KeyCode.a, down: false, at: 0.2, focused: true)
        XCTAssertTrue(injector.keys.isEmpty)

        let unfocused = makeSnapTap()
        unfocused.handleKey(code: KeyCode.a, down: true, at: 1, focused: false)
        unfocused.handleKey(code: KeyCode.d, down: true, at: 1.1, focused: false)
        unfocused.handleKey(code: KeyCode.d, down: false, at: 1.2, focused: false)
        XCTAssertTrue(injector.keys.isEmpty)

        // Сброс при потере фокуса не должен добавлять события, если не было
        // синтетически зажатых клавиш.
        unfocused.releaseAll(focused: true)
        XCTAssertTrue(injector.keys.isEmpty)
    }

    func testReleaseAllClearsSyntheticMirror() {
        let snapTap = makeSnapTap()
        snapTap.handleKey(code: KeyCode.a, down: true, at: 0, focused: true)
        snapTap.handleKey(code: KeyCode.d, down: true, at: 0.1, focused: true)
        snapTap.handleKey(code: KeyCode.d, down: false, at: 0.2, focused: true)
        XCTAssertEqual(injector.keys.last?.down, true)

        snapTap.releaseAll(focused: true)
        XCTAssertEqual(injector.keys.last, .init(code: KeyCode.a, down: false, shift: false))

        // Повторное нажатие после сброса снова работает.
        snapTap.handleKey(code: KeyCode.d, down: true, at: 1, focused: true)
        snapTap.handleKey(code: KeyCode.d, down: false, at: 1.1, focused: true)
        XCTAssertEqual(injector.keys.last, .init(code: KeyCode.a, down: true, shift: false))
    }

    func testKeyOutsideMovementIsIgnored() {
        let snapTap = makeSnapTap()
        snapTap.handleKey(code: KeyCode.w, down: true, at: 0, focused: true)
        snapTap.handleKey(code: KeyCode.w, down: false, at: 0.1, focused: true)
        XCTAssertTrue(injector.keys.isEmpty)
    }
}

final class BunnyHopTests: XCTestCase {
    private var injector = RecordingInjector()

    override func setUp() {
        super.setUp()
        injector = RecordingInjector()
        Logger.shared.configure(level: .off, file: nil, console: false)
    }

    private func makeBunnyHop(mode: BunnyHopMode = .spam, maxHoldMs: Double = 8000) -> BunnyHop {
        let config = BunnyHopConfig(
            enabled: true,
            mode: mode,
            tickRate: 128,
            startDelayMs: 60,
            pressHoldMs: 8,
            pulseIntervalTicks: 2,
            predictiveAirtimeMs: 760,
            predictiveWindowMs: 180,
            maxContinuousHoldMs: maxHoldMs
        )
        return BunnyHop(config: config, injector: injector)
    }

    func testSpamPulseTiming() {
        let bhop = makeBunnyHop()
        bhop.handleKey(code: KeyCode.space, down: true, at: 0, focused: true)
        XCTAssertTrue(bhop.isActive)
        XCTAssertTrue(injector.keys.isEmpty, "физическое нажатие уже ушло в игру")

        bhop.update(now: 0.059, allowed: true)
        XCTAssertTrue(injector.keys.isEmpty)
        bhop.update(now: 0.060, allowed: true)
        XCTAssertEqual(injector.keys, [.init(code: KeyCode.space, down: false, shift: false)])

        bhop.update(now: 0.067, allowed: true)
        XCTAssertEqual(injector.keys.count, 1)
        bhop.update(now: 0.068, allowed: true)
        XCTAssertEqual(injector.keys.last, .init(code: KeyCode.space, down: true, shift: false))

        // Интервал 2 тика при 128 tick = 15.625 мс от начала предыдущего импульса.
        bhop.update(now: 0.0756, allowed: true)
        XCTAssertEqual(injector.keys.count, 2)
        bhop.update(now: 0.075625, allowed: true)
        XCTAssertEqual(injector.keys.count, 3)
        bhop.update(now: 0.083625, allowed: true)
        XCTAssertEqual(injector.keys.count, 4)
        XCTAssertEqual(injector.keys.map(\.down), [false, true, false, true])
    }

    func testPredictiveStartWaitsForLandingWindow() {
        let bhop = makeBunnyHop(mode: .predictive)
        bhop.handleKey(code: KeyCode.space, down: true, at: 100, focused: true)

        bhop.update(now: 100.669, allowed: true)
        XCTAssertTrue(injector.keys.isEmpty)
        bhop.update(now: 100.670, allowed: true)
        XCTAssertEqual(injector.keys.first, .init(code: KeyCode.space, down: false, shift: false))
    }

    func testPhysicalReleaseResetsWithoutSyntheticKeyUp() {
        let bhop = makeBunnyHop()
        bhop.handleKey(code: KeyCode.space, down: true, at: 0, focused: true)
        bhop.update(now: 0.060, allowed: true)
        bhop.update(now: 0.068, allowed: true)
        XCTAssertEqual(injector.keys.last?.down, true)

        bhop.handleKey(code: KeyCode.space, down: false, at: 0.1, focused: true)
        let count = injector.keys.count
        bhop.update(now: 10, allowed: true)
        XCTAssertEqual(injector.keys.count, count, "после физического key-up импульсы прекращаются")
        XCTAssertFalse(bhop.isActive)
    }

    func testFocusLossReleasesSpace() {
        let bhop = makeBunnyHop()
        bhop.handleKey(code: KeyCode.space, down: true, at: 0, focused: true)
        bhop.update(now: 0.060, allowed: true)
        bhop.update(now: 0.068, allowed: true)
        bhop.update(now: 0.1, allowed: false)
        XCTAssertEqual(injector.keys.last, .init(code: KeyCode.space, down: false, shift: false))
        XCTAssertFalse(bhop.isActive)
    }

    func testMaximumHoldLimit() {
        let bhop = makeBunnyHop(maxHoldMs: 100)
        bhop.handleKey(code: KeyCode.space, down: true, at: 0, focused: true)
        bhop.update(now: 0.060, allowed: true)
        bhop.update(now: 0.068, allowed: true)
        bhop.update(now: 0.101, allowed: true)
        XCTAssertEqual(injector.keys.last, .init(code: KeyCode.space, down: false, shift: false))
        XCTAssertFalse(bhop.isActive)
    }

    func testDisabledBunnyHopDoesNothing() {
        let config = BunnyHopConfig(enabled: false)
        let bhop = BunnyHop(config: config, injector: injector)
        bhop.handleKey(code: KeyCode.space, down: true, at: 0, focused: true)
        bhop.update(now: 1, allowed: true)
        XCTAssertTrue(injector.keys.isEmpty)
    }
}

final class RecoilEngineTests: XCTestCase {
    private var injector = RecordingInjector()
    private var store: PatternStore?

    override func setUpWithError() throws {
        try super.setUpWithError()
        injector = RecordingInjector()
        store = try makePatternStore()
        Logger.shared.configure(level: .off, file: nil, console: false)
    }

    private func makeEngine(
        weapon: String = "ak47",
        enabled: Bool = true,
        intensity: Double = 1.0,
        holdThresholdMs: Double = 120,
        maxCountsPerTick: Int = 2000,
        semiAutoShotDelayMs: Double = 18,
        burstResetMs: Double = 420
    ) throws -> RecoilEngine {
        let config = RecoilConfig(
            enabled: enabled,
            weapon: weapon,
            intensity: intensity,
            holdThresholdMs: holdThresholdMs,
            semiAutoShotDelayMs: semiAutoShotDelayMs,
            burstResetMs: burstResetMs,
            maxCountsPerTick: maxCountsPerTick,
            patternTimeScale: 1.0,
            compensateDuringFeedback: false
        )
        return try RecoilEngine(patterns: store!, weaponID: weapon, injector: injector, config: config)
    }

    func testContinuousSprayRespectsHoldThreshold() throws {
        let engine = try makeEngine()
        engine.noteMouseDown(at: 0)

        engine.update(now: 0.06, isButtonDown: true, allowed: true)
        XCTAssertTrue(injector.moves.isEmpty)
        XCTAssertFalse(engine.isSpraying)

        engine.update(now: 0.12, isButtonDown: true, allowed: true)
        XCTAssertTrue(engine.isSpraying)
        XCTAssertEqual(injector.moves.count, 1)
        XCTAssertEqual(engine.lastAppliedCounts.x, -3)
        XCTAssertEqual(engine.lastAppliedCounts.y, 12)
        XCTAssertGreaterThan(injector.moves[0].y, 0, "отдача уводит прицел вверх, компенсация — вниз по экрану")

        // Повторный вызов в тот же момент не должен выдавать ненулевые counts:
        // дробный остаток остаётся на следующий тик.
        engine.update(now: 0.12, isButtonDown: true, allowed: true)
        XCTAssertEqual(engine.lastAppliedCounts.x, 0)
        XCTAssertEqual(engine.lastAppliedCounts.y, 0)

        engine.update(now: 0.20, isButtonDown: true, allowed: true)
        XCTAssertEqual(engine.lastAppliedCounts.y, 18)
        XCTAssertGreaterThan(engine.lastAppliedCounts.y, 0)
    }

    func testReleaseStopsCompensation() throws {
        let engine = try makeEngine()
        engine.noteMouseDown(at: 0)
        engine.update(now: 0.2, isButtonDown: true, allowed: true)
        XCTAssertFalse(injector.moves.isEmpty)

        engine.noteMouseUp(at: 0.3)
        XCTAssertFalse(engine.isSpraying)
        let count = injector.moves.count
        engine.update(now: 0.4, isButtonDown: false, allowed: true)
        XCTAssertEqual(injector.moves.count, count)
    }

    func testDisabledAndUnfocusedDoNotMove() throws {
        let disabled = try makeEngine(enabled: false)
        disabled.noteMouseDown(at: 0)
        disabled.update(now: 0.5, isButtonDown: true, allowed: true)
        XCTAssertTrue(injector.moves.isEmpty)

        let allowedEngine = try makeEngine()
        allowedEngine.noteMouseDown(at: 0)
        allowedEngine.update(now: 0.5, isButtonDown: true, allowed: false)
        XCTAssertTrue(injector.moves.isEmpty)
    }

    func testZeroIntensityProducesNoMovement() throws {
        let engine = try makeEngine(intensity: 0)
        engine.noteMouseDown(at: 0)
        engine.update(now: 0.5, isButtonDown: true, allowed: true)
        XCTAssertTrue(injector.moves.isEmpty)
    }

    func testPerTickClamp() throws {
        let engine = try makeEngine(maxCountsPerTick: 10)
        engine.noteMouseDown(at: 0)
        engine.update(now: 0.2, isButtonDown: true, allowed: true)
        XCTAssertEqual(injector.moves.count, 1)
        let move = injector.moves[0]
        let magnitude = (move.x * move.x + move.y * move.y).squareRoot()
        XCTAssertLessThanOrEqual(magnitude, 10.0001)
    }

    func testSemiAutomaticUsesOneIncrementPerClickAndResetsBurst() throws {
        let engine = try makeEngine(weapon: "glock18")

        engine.noteMouseDown(at: 0)
        engine.update(now: 0.010, isButtonDown: true, allowed: true)
        XCTAssertTrue(injector.moves.isEmpty, "выстрел ещё не должен быть компенсирован")
        engine.update(now: 0.018, isButtonDown: true, allowed: true)
        XCTAssertEqual(injector.moves.count, 1)
        let firstShotY = injector.moves[0].y
        XCTAssertGreaterThan(firstShotY, 10)

        engine.noteMouseUp(at: 0.05)
        engine.noteMouseDown(at: 0.1)
        // 0.1 + 0.018 в Double чуть больше 0.118, поэтому даём допуск.
        engine.update(now: 0.119, isButtonDown: true, allowed: true)
        XCTAssertEqual(injector.moves.count, 2)
        XCTAssertLessThan(injector.moves[1].y, firstShotY, "второй выстрел имеет меньший инкремент")

        // Пауза длиннее burstResetMs сбрасывает серию.
        engine.noteMouseUp(at: 0.2)
        engine.noteMouseDown(at: 0.6)
        engine.update(now: 0.619, isButtonDown: true, allowed: true)
        XCTAssertEqual(injector.moves.count, 3)
        XCTAssertEqual(injector.moves[2].y, firstShotY, accuracy: 1e-9)
    }

    func testWeaponSelectionAndReset() throws {
        let engine = try makeEngine()
        let resetsBefore = injector.resets
        XCTAssertTrue(engine.selectWeapon(id: "awp"))
        XCTAssertEqual(engine.weapon.id, "awp")
        XCTAssertGreaterThan(injector.resets, resetsBefore)
        XCTAssertFalse(engine.selectWeapon(id: "not-a-weapon"))
        XCTAssertEqual(engine.weapon.id, "awp")
    }
}

final class ConsoleFeedbackTests: XCTestCase {
    private var injector = RecordingInjector()

    override func setUp() {
        super.setUp()
        injector = RecordingInjector()
        Logger.shared.configure(level: .off, file: nil, console: false)
    }

    private func makeFeedback(
        enabled: Bool = true,
        consoleEcho: Bool = true,
        openConsole: Bool = true
    ) -> ConsoleFeedback {
        let config = FeedbackConfig(
            enabled: enabled,
            consoleEcho: consoleEcho,
            openConsole: openConsole,
            closeConsoleAfterMs: 300,
            textMode: .unicode,
            typeDelayMs: 0,
            openDelayMs: 100,
            consoleKeyCode: KeyCode.grave,
            returnKeyCode: KeyCode.returnKey
        )
        return ConsoleFeedback(config: config, injector: injector)
    }

    func testSanitizeRemovesCommandSeparators() {
        let safe = ConsoleFeedback.sanitize("Status: OK; quit\n`say` \"hi\"")
        XCTAssertFalse(safe.contains(";"))
        XCTAssertFalse(safe.contains("\""))
        XCTAssertFalse(safe.contains("`"))
        XCTAssertFalse(safe.contains("\n"))
        XCTAssertTrue(safe.hasPrefix("status= ok- quit"))
        XCTAssertEqual(ConsoleFeedback.sanitize("ПАТТЕРН"), "-------")
    }

    func testDisabledOrOpenConsoleOffDoesNothing() {
        XCTAssertFalse(makeFeedback(enabled: false).start(message: "test", now: 0))
        XCTAssertFalse(makeFeedback(consoleEcho: false).start(message: "test", now: 0))
        XCTAssertFalse(makeFeedback(openConsole: false).start(message: "test", now: 0))
        XCTAssertTrue(injector.keys.isEmpty)
        XCTAssertTrue(injector.typed.isEmpty)
    }

    func testFullEchoSequence() {
        let feedback = makeFeedback()
        XCTAssertTrue(feedback.start(message: "Test", now: 0))
        XCTAssertTrue(feedback.isActive)
        XCTAssertTrue(feedback.blocksGameplay)
        XCTAssertEqual(injector.keys, [.init(code: KeyCode.grave, down: true, shift: false)])
        XCTAssertFalse(feedback.start(message: "busy", now: 0), "второе сообщение не должно перебивать текущее")

        var now = 0.015
        feedback.update(now: now)
        XCTAssertEqual(injector.keys.last, .init(code: KeyCode.grave, down: false, shift: false))

        now += 0.100
        feedback.update(now: now)
        let expected = Array("echo csgo-helper test")
        for _ in 0..<200 where injector.typed.count < expected.count {
            now += 0.001
            feedback.update(now: now)
        }
        XCTAssertEqual(injector.typed.joined(), String(expected))

        now += 0.001
        feedback.update(now: now)
        XCTAssertEqual(Array(injector.keys.suffix(2)), [
            .init(code: KeyCode.returnKey, down: true, shift: false),
            .init(code: KeyCode.returnKey, down: false, shift: false)
        ])

        now += 0.120
        feedback.update(now: now)
        XCTAssertEqual(injector.keys.last, .init(code: KeyCode.grave, down: true, shift: false))

        now += 0.015
        feedback.update(now: now)
        XCTAssertEqual(injector.keys.last, .init(code: KeyCode.grave, down: false, shift: false))

        now += 0.300
        feedback.update(now: now)
        XCTAssertFalse(feedback.isActive)
        XCTAssertFalse(feedback.blocksGameplay)
    }

    func testCancelAllowsNextMessage() {
        let feedback = makeFeedback()
        XCTAssertTrue(feedback.start(message: "first", now: 0))
        feedback.cancel()
        XCTAssertFalse(feedback.isActive)
        XCTAssertTrue(feedback.start(message: "second", now: 1))
    }
}
