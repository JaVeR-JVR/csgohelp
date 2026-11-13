import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

public struct PermissionStatus: Equatable {
    public let accessibilityTrusted: Bool
    public let canPostEvents: Bool
    public let canListenToEvents: Bool
    public let secureInputEnabled: Bool

    public var allRequired: Bool {
        accessibilityTrusted && canPostEvents && canListenToEvents
    }

    public var summary: String {
        let accessibility = accessibilityTrusted ? "Accessibility: OK" : "Accessibility: НЕТ"
        let post = canPostEvents ? "Post events: OK" : "Post events: НЕТ"
        let listen = canListenToEvents ? "Input Monitoring: OK" : "Input Monitoring: НЕТ"
        let secure = secureInputEnabled ? "Secure Input: ВКЛ" : "Secure Input: выкл"
        return "\(accessibility); \(post); \(listen); \(secure)"
    }
}

public enum Permissions {
    public static func status() -> PermissionStatus {
        PermissionStatus(
            accessibilityTrusted: AXIsProcessTrusted(),
            canPostEvents: CGPreflightPostEventAccess(),
            canListenToEvents: CGPreflightListenEventAccess(),
            secureInputEnabled: isSecureEventInputEnabled()
        )
    }

    /// Показывает системный запрос Accessibility. Input Monitoring и отправка
    /// событий имеют собственные запросы в актуальных версиях macOS.
    @discardableResult
    public static func requestAccessibilityPrompt() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    public static func requestListenAccess() -> Bool {
        CGRequestListenEventAccess()
    }

    @discardableResult
    public static func requestPostAccess() -> Bool {
        CGRequestPostEventAccess()
    }

    public static func requestAllPrompts() {
        _ = requestAccessibilityPrompt()
        _ = requestListenAccess()
        _ = requestPostAccess()
    }

    /// IsSecureEventInputEnabled находится в Carbon и не экспортируется в Swift
    /// без импорта устаревшего umbrella-заголовка. Поэтому ищем символ динамически.
    public static func isSecureEventInputEnabled() -> Bool {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IsSecureEventInputEnabled") else {
            return false
        }
        typealias Function = @convention(c) () -> Bool
        let function = unsafeBitCast(symbol, to: Function.self)
        return function()
    }

    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    public static func openPrivacySettings() {
        open("x-apple.systempreferences:com.apple.preference.security")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspaceLauncher.open(url)
    }
}

private enum NSWorkspaceLauncher {
    static func open(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try? process.run()
    }
}
