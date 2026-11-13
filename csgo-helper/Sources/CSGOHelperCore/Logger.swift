import Foundation

public final class Logger {
    public static let shared = Logger()

    private let lock = NSLock()
    private var level: LogLevel = .info
    private var consoleEnabled = true
    private var fileURL: URL?
    private var fileHandle: FileHandle?
    private var maxFileBytes = 2_000_000
    private var closed = false
    private let formatter: ISO8601DateFormatter

    private init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
    }

    public func configure(level: LogLevel, file: URL?, console: Bool, maxFileBytes: Int = 2_000_000) {
        lock.lock()
        defer { lock.unlock() }
        self.level = level
        self.consoleEnabled = console
        self.maxFileBytes = max(64_000, maxFileBytes)
        closeFileLocked()
        self.fileURL = file
        guard level != .off, let file else { return }
        do {
            try HelperPaths.ensureDirectory(file.deletingLastPathComponent())
            rotateIfNeededLocked(file)
            if !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            self.fileHandle = handle
        } catch {
            self.fileHandle = nil
            if consoleEnabled {
                FileHandle.standardError.write(Data("logger: не удалось открыть \(file.path): \(error)\n".utf8))
            }
        }
    }

    public var currentLevel: LogLevel {
        lock.lock()
        defer { lock.unlock() }
        return level
    }

    public func log(_ messageLevel: LogLevel, _ message: @autoclosure () -> String, category: String = "app") {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, messageLevel >= level, level != .off else { return }
        let timestamp = formatter.string(from: Date())
        let shortLevel: String
        switch messageLevel {
        case .trace: shortLevel = "TRACE"
        case .debug: shortLevel = "DEBUG"
        case .info: shortLevel = "INFO"
        case .warn: shortLevel = "WARN"
        case .error: shortLevel = "ERROR"
        case .off: return
        }
        let line = "\(timestamp) \(shortLevel) [\(category)] \(message())\n"
        if consoleEnabled {
            FileHandle.standardError.write(Data(line.utf8))
        }
        if let handle = fileHandle, let data = line.data(using: .utf8) {
            do {
                try handle.write(contentsOf: data)
            } catch {
                // Логирование ни при каких условиях не должно ронять helper.
            }
        }
    }

    public func trace(_ message: @autoclosure () -> String, category: String = "app") {
        log(.trace, message(), category: category)
    }

    public func debug(_ message: @autoclosure () -> String, category: String = "app") {
        log(.debug, message(), category: category)
    }

    public func info(_ message: @autoclosure () -> String, category: String = "app") {
        log(.info, message(), category: category)
    }

    public func warn(_ message: @autoclosure () -> String, category: String = "app") {
        log(.warn, message(), category: category)
    }

    public func error(_ message: @autoclosure () -> String, category: String = "app") {
        log(.error, message(), category: category)
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        closeFileLocked()
        closed = true
    }

    private func closeFileLocked() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    private func rotateIfNeededLocked(_ file: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue >= maxFileBytes else { return }
        let backup = file.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: file, to: backup)
    }
}
