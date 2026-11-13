import CoreGraphics
import Foundation

/// Компенсация отдачи по заранее рассчитанной кумулятивной таблице.
///
/// Автоматическое оружие: таблица выбирается по времени с момента физического
/// нажатия ЛКМ. Первая точка всегда нулевая (первый выстрел), интерполяция
/// следует за RPM оружия.
///
/// Полуавтоматическое оружие: каждый клик использует следующий прирост за
/// выстрел. Счётчик серии сбрасывается после короткой паузы. Это не даёт
/// делать вид, что болтовка или пистолет стреляют с частотой магазина.
public final class RecoilEngine {
    public private(set) var weapon: WeaponProfile
    public private(set) var enabled: Bool
    public private(set) var isSpraying = false
    public private(set) var lastAppliedCounts: (x: Int, y: Int) = (0, 0)

    private let patterns: PatternStore
    private let injector: InputInjecting
    private let config: RecoilConfig
    private let logger: Logger

    private var buttonDownAt: TimeInterval?
    private var appliedX = 0.0
    private var appliedY = 0.0
    private var lastLogAt: TimeInterval = 0
    private var semiPendingAt: TimeInterval?
    private var semiShotIndex = 0
    private var lastSemiShotAt: TimeInterval = -Double.infinity

    public init(
        patterns: PatternStore,
        weaponID: String,
        injector: InputInjecting,
        config: RecoilConfig,
        logger: Logger = .shared
    ) throws {
        guard let weapon = patterns.weapon(id: weaponID) else {
            throw HelperError.patterns("оружие \"\(weaponID)\" не найдено; список: --list-weapons")
        }
        self.patterns = patterns
        self.weapon = weapon
        self.injector = injector
        self.config = config
        self.enabled = config.enabled
        self.logger = logger
        logger.info("recoil: профиль \(weapon.id) (\(weapon.displayName)), качество \(weapon.quality.rawValue), режим \(weapon.isAutomatic ? "continuous" : "per-shot")", category: "recoil")
    }

    public func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        reset()
        logger.info("recoil: \(value ? "включён" : "выключен")", category: "recoil")
    }

    @discardableResult
    public func selectWeapon(id: String) -> Bool {
        guard let next = patterns.weapon(id: id) else {
            logger.warn("recoil: неизвестное оружие \(id)", category: "recoil")
            return false
        }
        guard next.id != weapon.id else { return true }
        weapon = next
        reset()
        logger.info("recoil: оружие \(next.id) (\(next.displayName)), источник \(next.patternSource)", category: "recoil")
        return true
    }

    public func noteMouseDown(at now: TimeInterval) {
        if buttonDownAt == nil {
            buttonDownAt = now
            appliedX = 0
            appliedY = 0
            lastLogAt = 0
            if !weapon.isAutomatic {
                semiPendingAt = now + config.semiAutoShotDelayMs / 1000.0
            }
        }
    }

    public func noteMouseUp(at now: TimeInterval) {
        if let start = buttonDownAt {
            let duration = (now - start) * 1000.0
            logger.debug(String(format: "recoil: ЛКМ отпущена через %.0f мс", duration), category: "recoil")
        }
        buttonDownAt = nil
        semiPendingAt = nil
        appliedX = 0
        appliedY = 0
        isSpraying = false
    }

    public func reset() {
        buttonDownAt = nil
        semiPendingAt = nil
        appliedX = 0
        appliedY = 0
        semiShotIndex = 0
        lastSemiShotAt = -Double.infinity
        isSpraying = false
        injector.resetFractionalRemainder()
    }

    /// Вызывается циклом движка. `isButtonDown` может приходить из event tap
    /// или, если Input Monitoring недоступен, из опроса CGEventSource.
    public func update(now: TimeInterval, isButtonDown: Bool, allowed: Bool) {
        guard enabled, allowed else {
            if buttonDownAt != nil { reset() }
            return
        }
        guard isButtonDown else {
            if buttonDownAt != nil { noteMouseUp(at: now) }
            return
        }
        if buttonDownAt == nil {
            noteMouseDown(at: now)
        }
        if weapon.isAutomatic {
            updateContinuous(now: now)
        } else {
            updatePerShot(now: now)
        }
    }

    private func updateContinuous(now: TimeInterval) {
        guard let start = buttonDownAt else { return }
        let elapsed = now - start
        guard elapsed * 1000.0 >= config.holdThresholdMs else { return }
        isSpraying = true
        let tableTime = elapsed * config.patternTimeScale
        let target = weapon.cumulative(at: tableTime)
        let targetX = target.x * config.intensity * injector.countsPerDegreeX
        let targetY = target.y * config.intensity * injector.countsPerDegreeY
        apply(targetX: targetX, targetY: targetY, now: now, elapsed: elapsed)
    }

    private func updatePerShot(now: TimeInterval) {
        guard let pending = semiPendingAt, now >= pending else { return }
        semiPendingAt = nil
        let gap = now - lastSemiShotAt
        if gap > config.burstResetMs / 1000.0 {
            semiShotIndex = 0
        } else {
            semiShotIndex = min(semiShotIndex + 1, max(weapon.perShotDegrees.count - 1, 0))
        }
        lastSemiShotAt = now
        let increment = weapon.perShotIncrement(shotIndex: semiShotIndex)
        let targetX = increment.x * config.intensity * injector.countsPerDegreeX
        let targetY = increment.y * config.intensity * injector.countsPerDegreeY
        let deltaX = clampMagnitude(targetX, targetY, maxCounts: Double(config.maxCountsPerTick))
        lastAppliedCounts = injector.moveMouseByCounts(dx: deltaX.x, dy: deltaX.y)
        logger.debug(
            String(format: "recoil: per-shot %@ #%d d=(%.1f, %.1f) counts", weapon.id, semiShotIndex + 1, deltaX.x, deltaX.y),
            category: "recoil"
        )
    }

    private func apply(targetX: Double, targetY: Double, now: TimeInterval, elapsed: TimeInterval) {
        var deltaX = targetX - appliedX
        var deltaY = targetY - appliedY
        let clamped = clampMagnitude(deltaX, deltaY, maxCounts: Double(config.maxCountsPerTick))
        deltaX = clamped.x
        deltaY = clamped.y
        guard abs(deltaX) >= 0.01 || abs(deltaY) >= 0.01 else { return }
        lastAppliedCounts = injector.moveMouseByCounts(dx: deltaX, dy: deltaY)
        appliedX += Double(lastAppliedCounts.x)
        appliedY += Double(lastAppliedCounts.y)
        let shouldLog = injector.dryRun ? (now - lastLogAt >= 0.2) : (now - lastLogAt >= 0.5)
        if shouldLog {
            lastLogAt = now
            logger.log(
                injector.dryRun ? .info : .debug,
                String(
                    format: "recoil %@ t=%.0fms target=(%.1f, %.1f) applied=(%.1f, %.1f) counts",
                    weapon.id, elapsed * 1000, targetX, targetY, appliedX, appliedY
                ),
                category: "recoil"
            )
        }
    }

    private func clampMagnitude(_ x: Double, _ y: Double, maxCounts: Double) -> (x: Double, y: Double) {
        let magnitude = (x * x + y * y).squareRoot()
        guard magnitude > maxCounts, magnitude > 0 else { return (x, y) }
        let scale = maxCounts / magnitude
        return (x * scale, y * scale)
    }
}
