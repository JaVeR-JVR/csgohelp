import CoreGraphics
import Foundation

public enum PhysicalEventKind: Equatable {
    case keyDown
    case keyUp
    case flagsChanged
    case leftMouseDown
    case leftMouseUp
    case tapDisabled
    case tapNotice(String)
}

public struct PhysicalInputEvent: Equatable {
    public let kind: PhysicalEventKind
    public let keyCode: CGKeyCode?
    public let flags: CGEventFlags
    public let isRepeat: Bool
    public let timestamp: CGEventTimestamp
    public let receivedAt: TimeInterval
}

public final class InputTap {
    public var onEvent: ((PhysicalInputEvent) -> Void)?
    public var onFailure: ((String) -> Void)?
    public private(set) var isRunning = false
    public private(set) var receivedEventCount = 0

    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private let logger: Logger

    public init(logger: Logger = .shared) {
        self.logger = logger
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard !isRunning else { return }
        guard Permissions.status().canListenToEvents else {
            throw HelperError.inputTap(
                "нет разрешения Input Monitoring. Откройте Системные настройки → Конфиденциальность и безопасность → Мониторинг ввода."
            )
        }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: inputTapCallback,
            userInfo: refcon
        ) else {
            throw HelperError.inputTap(
                "CGEvent.tapCreate вернул nil. Проверьте Input Monitoring и Accessibility, затем перезапустите helper."
            )
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            self.logger.debug("event tap запущен", category: "tap")
            CFRunLoopRun()
            self.logger.debug("event tap остановлен", category: "tap")
        }
        thread.name = "csgo-helper.eventtap"
        thread.qualityOfService = .userInteractive
        thread.stackSize = 512 * 1024
        self.thread = thread
        thread.start()
        logger.info("перехват клавиатуры и ЛКМ активен", category: "tap")
    }

    public func stop() {
        guard isRunning || tap != nil else { return }
        isRunning = false
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        tap = nil
        runLoop = nil
        thread = nil
        logger.info("перехват ввода остановлен", category: "tap")
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        receivedEventCount += 1
        switch type {
        case .tapDisabledByTimeout:
            logger.warn("event tap отключён системой по таймауту; включаю снова", category: "tap")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            onEvent?(PhysicalInputEvent(kind: .tapDisabled, keyCode: nil, flags: [], isRepeat: false,
                                        timestamp: event.timestamp, receivedAt: MonotonicClock.now()))
            return
        case .tapDisabledByUserInput:
            logger.warn("event tap отключён пользователем/системой (Input Monitoring?)", category: "tap")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            onEvent?(PhysicalInputEvent(kind: .tapDisabled, keyCode: nil, flags: [], isRepeat: false,
                                        timestamp: event.timestamp, receivedAt: MonotonicClock.now()))
            return
        default:
            break
        }

        let marker = event.getIntegerValueField(.eventSourceUserData)
        guard marker != HelperMeta.syntheticEventMarker else { return }

        let kind: PhysicalEventKind
        var keyCode: CGKeyCode?
        var isRepeat = false
        switch type {
        case .keyDown:
            kind = .keyDown
            keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        case .keyUp:
            kind = .keyUp
            keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        case .flagsChanged:
            kind = .flagsChanged
            keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        case .leftMouseDown:
            kind = .leftMouseDown
        case .leftMouseUp:
            kind = .leftMouseUp
        default:
            return
        }
        onEvent?(PhysicalInputEvent(
            kind: kind,
            keyCode: keyCode,
            flags: event.flags,
            isRepeat: isRepeat,
            timestamp: event.timestamp,
            receivedAt: MonotonicClock.now()
        ))
    }
}

private func inputTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let tap = Unmanaged<InputTap>.fromOpaque(refcon).takeUnretainedValue()
        tap.handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
