import CoreGraphics
import Foundation

/// Snap Tap / очистка SOCD.
///
/// Event tap работает в режиме listen-only, поэтому физические события всегда
/// сначала доходят до игры. Мы добавляем корректирующие нажатия *после* них:
///  * A + D зажаты: отпускаем в игре более старую клавишу, оставляя последнюю.
///  * Отпускание последней клавиши движения: короткий тап противоположной
///    клавишей (торможение).
///  * Отпускание клавиши, подавившей другую: повторно нажимаем всё ещё
///    физически зажатую клавишу.
public final class SnapTap {
    private let config: SnapTapConfig
    private let injector: InputInjecting
    private let logger: Logger

    private var leftPhysicalDown = false
    private var rightPhysicalDown = false
    private var suppressedPhysicalKey: CGKeyCode?
    private var syntheticKeyDown: CGKeyCode?
    private var syntheticKeyDeadline: TimeInterval = 0
    private var lastTapAt: TimeInterval = -Double.infinity
    private var enabled = true

    public init(config: SnapTapConfig, injector: InputInjecting, logger: Logger = .shared) {
        self.config = config
        self.injector = injector
        self.logger = logger
        self.enabled = config.enabled
    }

    public func setEnabled(_ value: Bool, focused: Bool) {
        guard enabled != value else { return }
        enabled = value
        if !value {
            releaseSynthetic(focused: focused)
            suppressedPhysicalKey = nil
        }
        logger.info("snap tap: \(value ? "включён" : "выключен")", category: "snaptap")
    }

    public var isEnabled: Bool { enabled }

    public func handleKey(code: CGKeyCode, down: Bool, at now: TimeInterval, focused: Bool) {
        guard code == config.leftKeyCode || code == config.rightKeyCode else { return }
        let isLeft = code == config.leftKeyCode
        if down {
            if isLeft {
                if leftPhysicalDown { return }
                leftPhysicalDown = true
            } else {
                if rightPhysicalDown { return }
                rightPhysicalDown = true
            }
            guard enabled, focused else { return }
            // Новое физическое нажатие отменяет ожидающий тормозной тап этой клавишей.
            if syntheticKeyDown == code {
                syntheticKeyDown = nil
                syntheticKeyDeadline = 0
            }
            if config.socdEnabled {
                suppressOppositeIfNeeded(pressed: code)
            }
        } else {
            if isLeft {
                if !leftPhysicalDown { return }
                leftPhysicalDown = false
            } else {
                if !rightPhysicalDown { return }
                rightPhysicalDown = false
            }
            guard enabled else { return }
            // Игра всё равно получит это физическое отпускание. Если клавиша
            // была лишь синтетически восстановлена (зеркало физического
            // удержания), забываем это состояние, чтобы оно не блокировало
            // будущий тормозной тап.
            if syntheticKeyDown == code && syntheticKeyDeadline == 0 {
                syntheticKeyDown = nil
            }
            if suppressedPhysicalKey == code {
                // Клавиша была отпущена в игре более новым нажатием
                // противоположной, но всё ещё физически зажата? Это её реальное
                // отпускание, восстанавливать нечего.
                suppressedPhysicalKey = nil
            }
            guard focused else { return }
            let otherIsHeld = isLeft ? rightPhysicalDown : leftPhysicalDown
            if config.socdEnabled, otherIsHeld, let suppressed = suppressedPhysicalKey {
                // Клавиша, подавившая другую, отпущена: возвращаем в игру
                // всё ещё зажатую клавишу.
                injector.postKey(code: suppressed, down: true)
                syntheticKeyDown = suppressed
                syntheticKeyDeadline = 0
                suppressedPhysicalKey = nil
                logger.debug("SOCD: восстановлена клавиша \(suppressed)", category: "snaptap")
                return
            }
            if !otherIsHeld, config.brakeTapEnabled {
                brakeTap(oppositeOf: code, at: now)
            }
        }
    }

    public func update(now: TimeInterval) {
        guard let key = syntheticKeyDown, syntheticKeyDeadline > 0, now >= syntheticKeyDeadline else { return }
        injector.postKey(code: key, down: false)
        logger.debug("snap tap: отпущена \(key)", category: "snaptap")
        syntheticKeyDown = nil
        syntheticKeyDeadline = 0
    }

    public func releaseAll(focused: Bool) {
        if syntheticKeyDown != nil {
            injector.postKey(code: syntheticKeyDown!, down: false)
            syntheticKeyDown = nil
        }
        syntheticKeyDeadline = 0
        suppressedPhysicalKey = nil
        leftPhysicalDown = false
        rightPhysicalDown = false
    }

    private func suppressOppositeIfNeeded(pressed: CGKeyCode) {
        let opposite: CGKeyCode
        let oppositeIsPhysicalDown: Bool
        if pressed == config.leftKeyCode {
            opposite = config.rightKeyCode
            oppositeIsPhysicalDown = rightPhysicalDown
        } else {
            opposite = config.leftKeyCode
            oppositeIsPhysicalDown = leftPhysicalDown
        }
        guard oppositeIsPhysicalDown, suppressedPhysicalKey != opposite else { return }
        injector.postKey(code: opposite, down: false)
        suppressedPhysicalKey = opposite
        logger.debug("SOCD: подавлена клавиша \(opposite) в пользу \(pressed)", category: "snaptap")
    }

    private func brakeTap(oppositeOf released: CGKeyCode, at now: TimeInterval) {
        guard now - lastTapAt >= config.cooldownMs / 1000.0 else { return }
        guard syntheticKeyDown == nil else { return }
        let key = released == config.leftKeyCode ? config.rightKeyCode : config.leftKeyCode
        injector.postKey(code: key, down: true)
        syntheticKeyDown = key
        let hold = config.holdMs / 1000.0
        syntheticKeyDeadline = now + hold
        lastTapAt = now
        logger.debug("snap tap: тормозной тап \(key) на \(Int(config.holdMs)) мс", category: "snaptap")
    }

    private func releaseSynthetic(focused: Bool) {
        if let key = syntheticKeyDown {
            injector.postKey(code: key, down: false)
            syntheticKeyDown = nil
        }
        syntheticKeyDeadline = 0
    }
}
