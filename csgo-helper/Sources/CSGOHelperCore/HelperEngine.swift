import CoreGraphics
import Foundation

public struct EngineStatus: Equatable {
    public var running: Bool = false
    public var masterEnabled: Bool = true
    public var recoilEnabled: Bool = true
    public var snapTapEnabled: Bool = true
    public var bunnyHopEnabled: Bool = true
    public var weaponID: String = ""
    public var weaponName: String = ""
    public var weaponQuality: PatternQuality = .heuristic
    public var focus: FocusState = FocusState()
    public var tapRunning: Bool = false
    public var injectionAvailable: Bool = false
    public var permissions: PermissionStatus = PermissionStatus(
        accessibilityTrusted: false, canPostEvents: false, canListenToEvents: false, secureInputEnabled: false
    )
    public var dryRun: Bool = false
    public var feedbackActive: Bool = false
    public var message: String = ""

    public init() {}

    public init(
        running: Bool,
        masterEnabled: Bool,
        recoilEnabled: Bool,
        snapTapEnabled: Bool,
        bunnyHopEnabled: Bool,
        weaponID: String,
        weaponName: String,
        weaponQuality: PatternQuality,
        focus: FocusState,
        tapRunning: Bool,
        injectionAvailable: Bool,
        permissions: PermissionStatus,
        dryRun: Bool,
        feedbackActive: Bool,
        message: String
    ) {
        self.running = running
        self.masterEnabled = masterEnabled
        self.recoilEnabled = recoilEnabled
        self.snapTapEnabled = snapTapEnabled
        self.bunnyHopEnabled = bunnyHopEnabled
        self.weaponID = weaponID
        self.weaponName = weaponName
        self.weaponQuality = weaponQuality
        self.focus = focus
        self.tapRunning = tapRunning
        self.injectionAvailable = injectionAvailable
        self.permissions = permissions
        self.dryRun = dryRun
        self.feedbackActive = feedbackActive
        self.message = message
    }

    public var focusShort: String {
        if focus.shouldInject { return "в игре" }
        if focus.gameRunning { return "ожидание фокуса" }
        return "игра не запущена"
    }
}

public final class HelperEngine {
    public var onStatusChange: ((EngineStatus) -> Void)?

    private let config: HelperConfig
    private let patterns: PatternStore
    private let injector: EventInjector
    private let logger: Logger
    private let hotkeys: HotkeyParser.Set
    private let inputTap: InputTap
    private let focusMonitor: GameFocusMonitor
    private let recoil: RecoilEngine
    private let snapTap: SnapTap
    private let bunnyHop: BunnyHop
    private let feedback: ConsoleFeedback

    private let engineQueue = DispatchQueue(label: "csgo-helper.engine", qos: .userInteractive)
    private let queueKey = DispatchSpecificKey<String>()
    private var timer: DispatchSourceTimer?
    private var running = false
    private var masterEnabled = true
    private var focusState = FocusState()
    private var lmbDown = false
    private var permissions: PermissionStatus
    private var injectionAvailable: Bool
    private var tapRunning = false
    private var lastPermissionCheck: TimeInterval = 0
    private var lastStatusEmit: TimeInterval = 0
    private var statusDirty = true
    private var lastFeedbackActive = false
    private var message = ""

    public init(config: HelperConfig, patterns: PatternStore, logger: Logger = .shared) throws {
        self.config = config
        self.patterns = patterns
        self.logger = logger
        self.hotkeys = try HotkeyParser.parseAll(config.hotkeys)
        self.injector = EventInjector(
            sensitivity: config.sensitivity,
            mYaw: config.mYaw,
            mPitch: config.mPitch,
            dryRun: config.logging.dryRun,
            logger: logger
        )
        self.recoil = try RecoilEngine(
            patterns: patterns,
            weaponID: config.recoil.weapon,
            injector: injector,
            config: config.recoil,
            logger: logger
        )
        self.snapTap = SnapTap(config: config.snapTap, injector: injector, logger: logger)
        self.bunnyHop = BunnyHop(config: config.bunnyHop, injector: injector, logger: logger)
        self.feedback = ConsoleFeedback(config: config.feedback, injector: injector, logger: logger)
        self.inputTap = InputTap(logger: logger)
        self.focusMonitor = GameFocusMonitor(config: config.focus, logger: logger)
        let status = Permissions.status()
        self.permissions = status
        self.injectionAvailable = status.canPostEvents
        self.masterEnabled = true
        engineQueue.setSpecific(key: queueKey, value: "engine")
    }

    public func start() {
        engineQueue.async { [weak self] in
            guard let self, !self.running else { return }
            self.running = true
            self.logger.info(
                "движок запущен: оружие \(self.recoil.weapon.id), dry-run=\(self.config.logging.dryRun), фокус=\(self.focusState.shortDescription)",
                category: "engine"
            )
            self.startInputTap()
            self.focusMonitor.onChange = { [weak self] state in
                self?.engineQueue.async {
                    self?.applyFocus(state)
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.focusMonitor.start()
            }
            self.startTimer()
            self.emitStatus(force: true)
        }
    }

    public func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopOnQueue()
            return
        }
        engineQueue.sync {
            self.stopOnQueue()
        }
    }

    private func stopOnQueue() {
        guard running else { return }
        running = false
        timer?.cancel()
        timer = nil
        inputTap.stop()
        tapRunning = false
        DispatchQueue.main.async { [weak self] in
            self?.focusMonitor.stop()
        }
        recoil.reset()
        snapTap.releaseAll(focused: false)
        bunnyHop.releaseAll(focused: false)
        feedback.cancel()
        logger.info("движок остановлен, синтетические клавиши отпущены", category: "engine")
        emitStatus(force: true)
    }

    // MARK: - Публичное управление (безопасно вызывать из главного потока)

    public func setMasterEnabled(_ value: Bool, announce: Bool) {
        engineQueue.async { [weak self] in
            self?.applyMasterEnabled(value, announce: announce)
        }
    }

    public func setRecoilEnabled(_ value: Bool, announce: Bool) {
        engineQueue.async { [weak self] in
            self?.applyRecoilEnabled(value, announce: announce)
        }
    }

    public func setSnapTapEnabled(_ value: Bool, announce: Bool) {
        engineQueue.async { [weak self] in
            self?.applySnapTapEnabled(value, announce: announce)
        }
    }

    public func setBunnyHopEnabled(_ value: Bool, announce: Bool) {
        engineQueue.async { [weak self] in
            self?.applyBunnyHopEnabled(value, announce: announce)
        }
    }

    public func selectWeapon(id: String, announce: Bool) {
        engineQueue.async { [weak self] in
            self?.applyWeapon(id: id, announce: announce)
        }
    }

    public func cycleWeapon(forward: Bool, announce: Bool) {
        engineQueue.async { [weak self] in
            self?.applyCycleWeapon(forward: forward, announce: announce)
        }
    }

    public func echoStatus() {
        engineQueue.async { [weak self] in
            self?.applyEchoStatus()
        }
    }

    private func applyMasterEnabled(_ value: Bool, announce: Bool) {
        guard masterEnabled != value else { return }
        masterEnabled = value
        if !value {
            recoil.reset()
            snapTap.releaseAll(focused: focusState.shouldInject)
            bunnyHop.releaseAll(focused: focusState.shouldInject)
        }
        logger.info("master: \(value ? "включён" : "выключен")", category: "engine")
        if announce { self.announce("all=\(value ? "on" : "off")") }
        emitStatus(force: true)
    }

    private func applyRecoilEnabled(_ value: Bool, announce: Bool) {
        recoil.setEnabled(value)
        if announce { self.announce("recoil=\(value ? "on" : "off")") }
        emitStatus(force: true)
    }

    private func applySnapTapEnabled(_ value: Bool, announce: Bool) {
        snapTap.setEnabled(value, focused: focusState.shouldInject)
        if announce { self.announce("snaptap=\(value ? "on" : "off")") }
        emitStatus(force: true)
    }

    private func applyBunnyHopEnabled(_ value: Bool, announce: Bool) {
        bunnyHop.setEnabled(value, focused: focusState.shouldInject)
        if announce { self.announce("bhop=\(value ? "on" : "off")") }
        emitStatus(force: true)
    }

    private func applyWeapon(id: String, announce: Bool) {
        let previous = recoil.weapon.id
        guard recoil.selectWeapon(id: id) else { return }
        if announce, previous != recoil.weapon.id {
            self.announce("weapon=\(recoil.weapon.id)")
        }
        emitStatus(force: true)
    }

    private func applyCycleWeapon(forward: Bool, announce: Bool) {
        let current = recoil.weapon.id
        let next = forward ? patterns.next(after: current) : patterns.previous(before: current)
        recoil.selectWeapon(id: next.id)
        if announce { self.announce("weapon=\(next.id)") }
        emitStatus(force: true)
    }

    private func applyEchoStatus() {
        announce(statusCommand())
    }

    public func currentStatus() -> EngineStatus {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return makeStatus()
        }
        return engineQueue.sync { makeStatus() }
    }

    public func restartInputTap() {
        engineQueue.async { [weak self] in
            guard let self else { return }
            self.inputTap.stop()
            self.tapRunning = false
            self.startInputTap()
            self.emitStatus(force: true)
        }
    }

    // MARK: - Жизненный цикл

    private func startInputTap() {
        inputTap.onEvent = { [weak self] event in
            self?.engineQueue.async {
                self?.handle(event)
            }
        }
        inputTap.onFailure = { [weak self] text in
            self?.engineQueue.async {
                self?.logger.warn("event tap: \(text)", category: "tap")
            }
        }
        do {
            try inputTap.start()
            tapRunning = true
            if !injectionAvailable {
                logger.warn("Input Monitoring выдан, но отправка событий (Accessibility) недоступна", category: "tap")
            }
        } catch {
            tapRunning = false
            logger.error(error.localizedDescription, category: "tap")
            logger.warn("хоткеи, snap tap и bhop недоступны без перехвата ввода; отдача может работать по опросу ЛКМ", category: "tap")
        }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: engineQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .microseconds(150))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        guard running else { return }
        let now = MonotonicClock.now()
        if now - lastPermissionCheck >= 2.0 {
            lastPermissionCheck = now
            let current = Permissions.status()
            if current != permissions {
                permissions = current
                injectionAvailable = current.canPostEvents
                if !current.canPostEvents {
                    recoil.reset()
                    snapTap.releaseAll(focused: false)
                    bunnyHop.releaseAll(focused: false)
                    feedback.cancel()
                }
                // Пользователь может выдать Input Monitoring, когда helper уже
                // работает. Сразу повторяем запуск listen-only event tap,
                // не требуя ручного перезапуска.
                if current.canListenToEvents && !tapRunning {
                    logger.info("Input Monitoring доступен: повторный запуск event tap", category: "tap")
                    startInputTap()
                }
                logger.warn("разрешения изменились: \(current.summary)", category: "permissions")
                statusDirty = true
            }
        }

        if !tapRunning {
            let polled = CGEventSource.buttonState(.combinedSessionState, button: .left)
            if polled != lmbDown {
                lmbDown = polled
                if polled {
                    if canInject { recoil.noteMouseDown(at: now) }
                } else {
                    recoil.noteMouseUp(at: now)
                }
            }
        }

        let gameActive = focusState.shouldInject
        let gameplayAllowed = masterEnabled && gameActive && injectionAvailable
        let feedbackBlocking = feedback.blocksGameplay
        let recoilAllowed = gameplayAllowed && (!feedbackBlocking || config.recoil.compensateDuringFeedback)
        recoil.update(now: now, isButtonDown: lmbDown, allowed: recoilAllowed)
        let hopAllowed = gameplayAllowed && !feedbackBlocking
        bunnyHop.update(now: now, allowed: hopAllowed)
        snapTap.update(now: now)
        feedback.update(now: now)
        if feedback.isActive != lastFeedbackActive {
            lastFeedbackActive = feedback.isActive
            statusDirty = true
        }
        if statusDirty || now - lastStatusEmit >= 0.25 {
            emitStatus(force: false)
        }
    }

    // MARK: - Обработка ввода

    /// Физическое состояние клавиш отслеживается всегда, но модули движения
    /// могут инжектировать ввод только при включённом master-выключателе
    /// и активном фокусе игры.
    private var modulesFocused: Bool {
        masterEnabled && focusState.shouldInject
    }

    private func handle(_ event: PhysicalInputEvent) {
        guard running else { return }
        if handleHotkey(event) { return }

        switch event.kind {
        case .leftMouseDown:
            lmbDown = true
            if focusState.shouldInject, injectionAvailable {
                recoil.noteMouseDown(at: event.receivedAt)
            }
        case .leftMouseUp:
            lmbDown = false
            recoil.noteMouseUp(at: event.receivedAt)
        case .keyDown:
            if let code = event.keyCode {
                if !event.isRepeat, code == config.snapTap.leftKeyCode || code == config.snapTap.rightKeyCode {
                    snapTap.handleKey(code: code, down: true, at: event.receivedAt, focused: modulesFocused)
                }
                if !event.isRepeat, code == KeyCode.space {
                    bunnyHop.handleKey(code: code, down: true, at: event.receivedAt, focused: modulesFocused)
                }
            }
        case .keyUp:
            if let code = event.keyCode {
                if code == config.snapTap.leftKeyCode || code == config.snapTap.rightKeyCode {
                    snapTap.handleKey(code: code, down: false, at: event.receivedAt, focused: modulesFocused)
                }
                if code == KeyCode.space {
                    bunnyHop.handleKey(code: code, down: false, at: event.receivedAt, focused: modulesFocused)
                }
            }
        case .flagsChanged, .tapDisabled, .tapNotice:
            break
        }
    }

    private func handleHotkey(_ event: PhysicalInputEvent) -> Bool {
        guard event.kind == .keyDown, !event.isRepeat, let code = event.keyCode else { return false }
        // Переключатели намеренно неактивны, когда игра не является активным
        // окном. Это предотвращает случайные переключения при наборе текста.
        guard focusState.isGameFrontmost else { return false }
        if hotkeys.toggleAll.matches(keyCode: code, flags: event.flags) {
            applyMasterEnabled(!masterEnabled, announce: true)
            return true
        }
        if hotkeys.recoil.matches(keyCode: code, flags: event.flags) {
            applyRecoilEnabled(!recoil.enabled, announce: true)
            return true
        }
        if hotkeys.snapTap.matches(keyCode: code, flags: event.flags) {
            applySnapTapEnabled(!snapTap.isEnabled, announce: true)
            return true
        }
        if hotkeys.bunnyHop.matches(keyCode: code, flags: event.flags) {
            applyBunnyHopEnabled(!bunnyHop.isEnabled, announce: true)
            return true
        }
        if hotkeys.nextWeapon.matches(keyCode: code, flags: event.flags) {
            applyCycleWeapon(forward: true, announce: true)
            return true
        }
        if hotkeys.previousWeapon.matches(keyCode: code, flags: event.flags) {
            applyCycleWeapon(forward: false, announce: true)
            return true
        }
        if hotkeys.echoStatus.matches(keyCode: code, flags: event.flags) {
            applyEchoStatus()
            return true
        }
        return false
    }

    private func applyFocus(_ state: FocusState) {
        let wasActive = focusState.shouldInject
        let previousSignature = focusState.signature
        focusState = state
        if previousSignature != state.signature {
            logger.debug("фокус изменён: \(state.shortDescription)", category: "engine")
            statusDirty = true
        }
        if wasActive && !state.shouldInject {
            recoil.reset()
            snapTap.releaseAll(focused: false)
            bunnyHop.releaseAll(focused: false)
            feedback.cancel()
            lmbDown = false
            logger.info("фокус потерян: модули остановлены, клавиши отпущены", category: "engine")
        }
        if !wasActive && state.shouldInject {
            logger.info("игра в фокусе: модули готовы", category: "engine")
        }
        emitStatus(force: true)
    }

    private func announce(_ message: String) {
        guard focusState.isGameFrontmost else {
            logger.debug("console echo пропущен: игра не в фокусе (\(message))", category: "console")
            return
        }
        guard injectionAvailable else {
            logger.warn("console echo невозможен: нет Accessibility (\(message))", category: "console")
            return
        }
        if !feedback.isActive {
            // Не печатать в игре, пока активен макрос движения.
            snapTap.releaseAll(focused: true)
            bunnyHop.releaseAll(focused: true)
            recoil.reset()
        }
        let now = MonotonicClock.now()
        if !feedback.start(message: message, now: now) {
            logger.info("статус: \(message)", category: "engine")
        }
        self.message = message
        statusDirty = true
        emitStatus(force: true)
    }

    // MARK: - Статус

    private var canInject: Bool { injectionAvailable }

    private func statusCommand() -> String {
        "all=\(masterEnabled ? "on" : "off") recoil=\(recoil.enabled ? "on" : "off") snaptap=\(snapTap.isEnabled ? "on" : "off") bhop=\(bunnyHop.isEnabled ? "on" : "off") weapon=\(recoil.weapon.id)"
    }

    private func makeStatus() -> EngineStatus {
        EngineStatus(
            running: running,
            masterEnabled: masterEnabled,
            recoilEnabled: recoil.enabled,
            snapTapEnabled: snapTap.isEnabled,
            bunnyHopEnabled: bunnyHop.isEnabled,
            weaponID: recoil.weapon.id,
            weaponName: recoil.weapon.displayName,
            weaponQuality: recoil.weapon.quality,
            focus: focusState,
            tapRunning: inputTap.isRunning,
            injectionAvailable: injectionAvailable,
            permissions: permissions,
            dryRun: config.logging.dryRun,
            feedbackActive: feedback.isActive,
            message: message
        )
    }

    private func emitStatus(force: Bool) {
        let now = MonotonicClock.now()
        if !force {
            guard statusDirty, now - lastStatusEmit >= 0.25 else { return }
        }
        lastStatusEmit = now
        statusDirty = false
        let status = makeStatus()
        if let callback = onStatusChange {
            DispatchQueue.main.async {
                callback(status)
            }
        }
    }
}
