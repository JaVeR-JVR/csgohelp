import CoreGraphics
import Foundation

/// Импульсы для авто-банихопа.
///
/// Внешний процесс не может прочитать состояние «на земле» локального игрока
/// (для этого нужна память игры, которую проект намеренно не трогает).
/// Поэтому модуль выдаёт короткие пары отпускание/нажатие Space, пока Space
/// физически зажат. `spam` начинает почти сразу; `predictive` ждёт типичное
/// окно приземления. Оба режима — вспомогательная подгонка таймингов,
/// а не гарантированный авто-прыжок.
public final class BunnyHop {
    private enum Phase {
        case idle
        case releaseWait
        case pressWait
    }

    private let config: BunnyHopConfig
    private let injector: InputInjecting
    private let logger: Logger

    private var enabled: Bool
    private var spacePhysicalDown = false
    private var gameSpaceDown = false
    private var active = false
    private var activeSince: TimeInterval = 0
    private var phase: Phase = .idle
    private var nextPulseAt: TimeInterval = 0
    private var pressAt: TimeInterval = 0
    private var pulseCount = 0
    private var lastPulseStart: TimeInterval = 0

    public init(config: BunnyHopConfig, injector: InputInjecting, logger: Logger = .shared) {
        self.config = config
        self.injector = injector
        self.logger = logger
        self.enabled = config.enabled
    }

    public var isEnabled: Bool { enabled }
    public var isActive: Bool { active }

    private var pulseInterval: TimeInterval {
        (1.0 / Double(max(config.tickRate, 1))) * Double(max(config.pulseIntervalTicks, 1))
    }

    public func setEnabled(_ value: Bool, focused: Bool) {
        guard enabled != value else { return }
        enabled = value
        if !value { stop(focused: focused) }
        logger.info("bunny hop: \(value ? "включён" : "выключен")", category: "bhop")
    }

    public func handleKey(code: CGKeyCode, down: Bool, at now: TimeInterval, focused: Bool) {
        guard code == KeyCode.space else { return }
        if down {
            if spacePhysicalDown { return }
            spacePhysicalDown = true
            // Физическое нажатие уже доходит до игры и запускает прыжок.
            gameSpaceDown = true
            guard enabled, focused else { return }
            start(at: now)
        } else {
            spacePhysicalDown = false
            // Физическое отпускание доходит до игры; не отправляем ещё одно
            // следом. Сбрасываем все ожидающие фазы.
            gameSpaceDown = false
            active = false
            phase = .idle
            pulseCount = 0
        }
    }

    public func update(now: TimeInterval, allowed: Bool) {
        guard enabled, allowed else {
            if active { stop(focused: allowed) }
            return
        }
        guard spacePhysicalDown else { return }
        guard active else { return }
        if now - activeSince > config.maxContinuousHoldMs / 1000.0 {
            logger.debug("bhop: достигнут лимит непрерывного удержания Space", category: "bhop")
            stop(focused: allowed)
            return
        }
        switch phase {
        case .idle:
            guard now >= nextPulseAt else { return }
            // Отпускаем клавишу, чтобы движок увидел новый переход 0 -> 1 при
            // повторном нажатии. Физически клавиша остаётся зажатой на уровне HID.
            injector.postKey(code: KeyCode.space, down: false)
            gameSpaceDown = false
            lastPulseStart = now
            pressAt = now + config.pressHoldMs / 1000.0
            phase = .releaseWait
        case .releaseWait:
            guard now >= pressAt else { return }
            injector.postKey(code: KeyCode.space, down: true)
            gameSpaceDown = true
            pulseCount += 1
            nextPulseAt = lastPulseStart + pulseInterval
            phase = .idle
            if pulseCount == 1 {
                logger.debug("bhop: импульсы начались (режим \(config.mode.rawValue), \(config.tickRate) tick)",
                             category: "bhop")
            }
        case .pressWait:
            phase = .idle
        }
    }

    /// Отпустить синтетическое нажатие Space при завершении/потере фокуса.
    /// Безопасно отправить key-up, даже если игра уже получила его.
    public func releaseAll(focused: Bool) {
        if active || gameSpaceDown {
            injector.postKey(code: KeyCode.space, down: false)
        }
        gameSpaceDown = false
        active = false
        spacePhysicalDown = false
        phase = .idle
        pulseCount = 0
    }

    private func start(at now: TimeInterval) {
        active = true
        activeSince = now
        phase = .idle
        pulseCount = 0
        let initialDelay: TimeInterval
        switch config.mode {
        case .spam:
            initialDelay = config.startDelayMs / 1000.0
        case .predictive:
            let delay = config.predictiveAirtimeMs - config.predictiveWindowMs / 2.0
            initialDelay = max(config.startDelayMs, delay) / 1000.0
        }
        nextPulseAt = now + initialDelay
        logger.debug("bhop: Space зажат, первый импульс через \(Int(initialDelay * 1000)) мс", category: "bhop")
    }

    private func stop(focused: Bool) {
        guard active || gameSpaceDown else {
            phase = .idle
            return
        }
        if gameSpaceDown {
            injector.postKey(code: KeyCode.space, down: false)
        }
        gameSpaceDown = false
        active = false
        spacePhysicalDown = false
        phase = .idle
        pulseCount = 0
    }
}
