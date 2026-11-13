import Foundation

/// Небольшие общие помощники, не зависящие от AppKit.
public enum HelperPaths {
    public static let appSupportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("CSGOHelper", isDirectory: true)
    }()

    public static let logDirectory: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return base.appendingPathComponent("Logs/CSGOHelper", isDirectory: true)
    }()

    public static let defaultConfigURL = appSupportDirectory.appendingPathComponent("config.json")
    public static let defaultPatternsURL = appSupportDirectory.appendingPathComponent("patterns.json")
    public static let defaultLogURL = logDirectory.appendingPathComponent("helper.log")
    public static let lockURL = appSupportDirectory.appendingPathComponent("helper.lock")

    public static func expand(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    public static func url(from path: String) -> URL {
        URL(fileURLWithPath: expand(path))
    }

    public static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

/// Монотонный источник времени для дедлайнов. Метки CGEvent хорошо подходят
/// для упорядочивания ввода, но планирование ведётся по процессным часам:
/// локально созданные синтетические события имеют нулевую метку времени.
public enum MonotonicClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public static func now() -> TimeInterval {
        let ticks = mach_continuous_time()
        return seconds(ticks: ticks)
    }

    public static func seconds(ticks: UInt64) -> TimeInterval {
        let nanos = Double(ticks) * Double(timebase.numer) / Double(timebase.denom)
        return nanos / 1_000_000_000.0
    }

    public static func ticks(for seconds: TimeInterval) -> UInt64 {
        let nanos = seconds * 1_000_000_000.0
        return UInt64(max(0, nanos) * Double(timebase.denom) / Double(timebase.numer))
    }
}

public enum HelperMeta {
    public static let version = "1.0.0"
    public static let bundleIdentifier = "local.csgo.helper"
    public static let displayName = "CSGO Helper"
    public static let syntheticEventMarker: Int64 = 0x4353_474F_4845_4C50 // ASCII "CSGOHELP"
}

public enum AtomicFile {
    public static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try HelperPaths.ensureDirectory(directory)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).tmp-\(getpid())")
        try data.write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }

    public static func writeString(_ string: String, to url: URL) throws {
        guard let data = string.data(using: .utf8) else {
            throw HelperError.encoding("Не удалось закодировать текст в UTF-8")
        }
        try write(data, to: url)
    }
}

public enum HelperError: LocalizedError, Equatable {
    case configuration(String)
    case patterns(String)
    case permissions(String)
    case injection(String)
    case inputTap(String)
    case instanceAlreadyRunning(String)
    case encoding(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .configuration(let message): return "Конфигурация: \(message)"
        case .patterns(let message): return "Паттерны: \(message)"
        case .permissions(let message): return "Разрешения: \(message)"
        case .injection(let message): return "Ввод: \(message)"
        case .inputTap(let message): return "Перехват ввода: \(message)"
        case .instanceAlreadyRunning(let message): return "Экземпляр: \(message)"
        case .encoding(let message): return "Кодирование: \(message)"
        case .unsupported(let message): return "Не поддерживается: \(message)"
        }
    }
}

public func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}
