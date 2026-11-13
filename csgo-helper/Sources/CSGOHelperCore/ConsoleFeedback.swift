import CoreGraphics
import Foundation

/// Обратная связь через консоль.
///
/// Helper открывает консоль Source настроенной клавишей, вводит команду
/// `echo`, отправляет её и снова закрывает консоль. Он никогда не использует
/// `say`, не открывает чат и не отправляет команды на сервер. `echo`
/// выполняется локально клиентской консолью.
public final class ConsoleFeedback {
    private enum Phase: Equatable {
        case idle
        case consoleDown
        case opening
        case typing
        case submitting
        case consoleUp
        case closing
    }

    private let config: FeedbackConfig
    private let injector: InputInjecting
    private let logger: Logger

    private var phase: Phase = .idle
    private var deadline: TimeInterval = 0
    private var characters: [Character] = []
    private var index = 0
    private var openedByUs = false
    private var lastMessage = ""

    public init(config: FeedbackConfig, injector: InputInjecting, logger: Logger = .shared) {
        self.config = config
        self.injector = injector
        self.logger = logger
    }

    public var isActive: Bool { phase != .idle }
    public var blocksGameplay: Bool { phase != .idle }

    /// Возвращает false, если обратная связь выключена, уже занята или
    /// сообщение не удалось очистить. Вызывающий код всё равно обновляет
    /// состояние в приложении.
    @discardableResult
    public func start(message: String, now: TimeInterval) -> Bool {
        guard config.enabled, config.consoleEcho else { return false }
        guard config.openConsole else {
            logger.warn("consoleEcho включён, но openConsole выключен: echo не отправлен", category: "console")
            return false
        }
        guard !isActive else {
            logger.debug("console feedback занят, новое сообщение пропущено", category: "console")
            return false
        }
        let safe = ConsoleFeedback.sanitize(message)
        guard !safe.isEmpty else { return false }
        let command = "echo csgo-helper " + safe
        lastMessage = command
        characters = Array(command)
        index = 0
        openedByUs = true
        injector.postKey(code: config.consoleKeyCode, down: true)
        phase = .consoleDown
        deadline = now + 0.015
        logger.debug("console: \(command)", category: "console")
        return true
    }

    public func update(now: TimeInterval) {
        guard isActive, now >= deadline else { return }
        switch phase {
        case .idle:
            return
        case .consoleDown:
            injector.postKey(code: config.consoleKeyCode, down: false)
            phase = .opening
            deadline = now + config.openDelayMs / 1000.0
        case .opening:
            phase = .typing
            deadline = now
        case .typing:
            if index < characters.count {
                let character = characters[index]
                index += 1
                injector.typeText(String(character), mode: config.textMode)
                deadline = now + config.typeDelayMs / 1000.0
            } else {
                injector.postKey(code: config.returnKeyCode, down: true)
                injector.postKey(code: config.returnKeyCode, down: false)
                phase = .submitting
                deadline = now + 0.12
            }
        case .submitting:
            injector.postKey(code: config.consoleKeyCode, down: true)
            phase = .consoleUp
            deadline = now + 0.015
        case .consoleUp:
            injector.postKey(code: config.consoleKeyCode, down: false)
            openedByUs = false
            phase = .closing
            deadline = now + config.closeConsoleAfterMs / 1000.0
        case .closing:
            phase = .idle
        }
    }

    public func cancel() {
        if openedByUs {
            logger.warn("console feedback прерван; консоль не закрывалась принудительно", category: "console")
        }
        phase = .idle
        characters = []
        index = 0
        openedByUs = false
    }

    /// Разрешены только строчные ASCII, цифры и символы, которые не могут
    /// завершить команду или открыть чат. В частности, кавычки, точки с запятой
    /// и обратные кавычки удаляются.
    public static func sanitize(_ message: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789 -_.=/[]()")
        var output = ""
        for character in message.lowercased() {
            if allowed.contains(character) {
                output.append(character)
            } else if character == ":" {
                output.append("=")
            } else {
                output.append("-")
            }
        }
        return output
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
