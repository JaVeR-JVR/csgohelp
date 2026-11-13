import CoreGraphics
import Foundation

/// Абстракция для сигнальных модулей, чтобы их тайминги можно было тестировать
/// записывающим инжектором. Реальная реализация — EventInjector.
public protocol InputInjecting: AnyObject {
    var dryRun: Bool { get }
    var countsPerDegreeX: Double { get }
    var countsPerDegreeY: Double { get }
    func resetFractionalRemainder()
    @discardableResult func moveMouseByCounts(dx: Double, dy: Double) -> (x: Int, y: Int)
    func postKey(code: CGKeyCode, down: Bool, flags: CGEventFlags)
    func typeText(_ text: String, mode: ConsoleTextMode)
    func postUnicode(_ text: String)
}

public extension InputInjecting {
    func postKey(code: CGKeyCode, down: Bool) {
        postKey(code: code, down: down, flags: [])
    }
}

/// Весь синтетический ввод идёт через этот класс. Каждое событие несёт метку,
/// чтобы event tap игнорировал собственный вывод и не заводил его обратно в
/// логику хоткеев и snap tap.
public final class EventInjector: InputInjecting {
    public let sensitivity: Double
    public let mYaw: Double
    public let mPitch: Double
    public let dryRun: Bool

    private let source: CGEventSource?
    private let marker = HelperMeta.syntheticEventMarker
    private var remainderX = 0.0
    private var remainderY = 0.0
    private let logger: Logger

    public init(sensitivity: Double, mYaw: Double, mPitch: Double, dryRun: Bool, logger: Logger = .shared) {
        self.sensitivity = sensitivity
        self.mYaw = mYaw
        self.mPitch = mPitch
        self.dryRun = dryRun
        self.source = CGEventSource(stateID: .hidSystemState)
        self.logger = logger
    }

    public var countsPerDegreeX: Double {
        1.0 / (sensitivity * mYaw)
    }

    public var countsPerDegreeY: Double {
        1.0 / (sensitivity * mPitch)
    }

    public func counts(forDegreesX degrees: Double, y: Double) -> (x: Double, y: Double) {
        (degrees * countsPerDegreeX, y * countsPerDegreeY)
    }

    public func resetFractionalRemainder() {
        remainderX = 0
        remainderY = 0
    }

    /// Инжектировать относительное движение мыши. Дробная часть переносится
    /// между тиками, чтобы медленные коррекции не терялись при округлении.
    @discardableResult
    public func moveMouseByCounts(dx: Double, dy: Double) -> (x: Int, y: Int) {
        remainderX += dx
        remainderY += dy
        let integerX = Int(remainderX.rounded(.toNearestOrAwayFromZero))
        let integerY = Int(remainderY.rounded(.toNearestOrAwayFromZero))
        remainderX -= Double(integerX)
        remainderY -= Double(integerY)
        guard integerX != 0 || integerY != 0 else { return (0, 0) }

        if dryRun {
            logger.trace("dry-run mouse delta x=\(integerX) y=\(integerY)", category: "inject")
            return (integerX, integerY)
        }

        let location = CGEvent(source: nil)?.location ?? CGPoint.zero
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else {
            logger.error("не удалось создать CGEvent мыши", category: "inject")
            return (0, 0)
        }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(integerX))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(integerY))
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
        return (integerX, integerY)
    }

    public func postKey(code: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else {
            logger.error("не удалось создать CGEvent клавиши \(code)", category: "inject")
            return
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        if dryRun {
            logger.debug("dry-run key \(down ? "down" : "up") code=\(code) flags=\(flags.rawValue)", category: "inject")
            return
        }
        event.post(tap: .cghidEventTap)
    }

    public func typeText(_ text: String, mode: ConsoleTextMode) {
        switch mode {
        case .unicode:
            postUnicode(text)
        case .keycode:
            for character in text {
                guard let stroke = KeyMap.stroke(for: character) else {
                    logger.warn("символ \(String(reflecting: character)) не поддерживается US-раскладкой", category: "console")
                    continue
                }
                let flags: CGEventFlags = stroke.shift ? .maskShift : []
                postKey(code: stroke.keyCode, down: true, flags: flags)
                postKey(code: stroke.keyCode, down: false, flags: flags)
            }
        }
    }

    public func postUnicode(_ text: String) {
        guard !text.isEmpty else { return }
        for character in text {
            let utf16 = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { continue }
            utf16.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            down.setIntegerValueField(.eventSourceUserData, value: marker)
            guard let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            up.setIntegerValueField(.eventSourceUserData, value: marker)
            if dryRun {
                logger.debug("dry-run unicode \(String(reflecting: character))", category: "inject")
            } else {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }
}
