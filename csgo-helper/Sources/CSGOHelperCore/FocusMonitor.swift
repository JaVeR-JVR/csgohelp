import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public struct GameMatcher {
    public let bundleIdentifiers: Set<String>
    public let processNames: Set<String>
    public let titleFragments: [String]

    public init(config: FocusConfig) {
        bundleIdentifiers = Set(config.gameBundleIdentifiers.map { $0.lowercased() })
        processNames = Set(config.gameProcessNames.map { $0.lowercased() })
        titleFragments = config.gameWindowTitles.map { $0.lowercased() }
    }

    public func matches(_ application: NSRunningApplication) -> Bool {
        guard application.processIdentifier != getpid() else { return false }
        let bundle = application.bundleIdentifier?.lowercased() ?? ""
        if !bundle.isEmpty, bundleIdentifiers.contains(bundle) { return true }
        let executable = application.executableURL?.lastPathComponent.lowercased() ?? ""
        let localized = application.localizedName?.lowercased() ?? ""
        let names = [executable, localized, bundle]
        for name in names where !name.isEmpty {
            if processNames.contains(name) { return true }
            if processNames.contains(where: { name.hasPrefix($0) }) && name.contains("cs") { return true }
        }
        if titleFragments.contains(where: { !$0.isEmpty && (localized.contains($0) || executable.contains($0)) }) {
            return true
        }
        return false
    }
}

public struct FocusState: Equatable {
    public var gameRunning: Bool = false
    public var isGameFrontmost: Bool = false
    public var shouldInject: Bool = false
    public var frontmostName: String?
    public var frontmostPID: pid_t = 0
    public var gamePID: pid_t = 0
    public var gameName: String?
    public var windowTitle: String?
    public var gameExecutable: String?
    public var matchedBy: String?
    public var timestamp: Date = Date()

    public var signature: String {
        "\(gameRunning)|\(isGameFrontmost)|\(shouldInject)|\(frontmostPID)|\(gamePID)|\(windowTitle ?? "")|\(frontmostName ?? "")"
    }

    public var shortDescription: String {
        if !gameRunning { return "игра не запущена" }
        if shouldInject {
            return "CS:GO в фокусе" + (windowTitle.map { " — \($0)" } ?? "")
        }
        if isGameFrontmost { return "окно игры активно, но инъекция запрещена настройками" }
        return "ожидание фокуса игры (сейчас: \(frontmostName ?? "неизвестно"))"
    }
}

public final class GameFocusMonitor {
    public private(set) var current = FocusState()
    public var onChange: ((FocusState) -> Void)?
    public var onGameExited: (() -> Void)?

    private let config: FocusConfig
    private let matcher: GameMatcher
    private let logger: Logger
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var axObserver: AXObserver?
    private var observedPID: pid_t = 0
    private var lastSignature: String = ""
    private var started = false

    public init(config: FocusConfig, logger: Logger = .shared) {
        self.config = config
        self.matcher = GameMatcher(config: config)
        self.logger = logger
    }

    deinit {
        stop()
    }

    public func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]
        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh(force: true)
            }
            workspaceObservers.append(observer)
        }
        let interval = max(0.1, config.pollIntervalMs / 1000.0)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh(force: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh(force: true)
        logger.info("монитор фокуса запущен (опрос \(Int(interval * 1000)) мс, AXObserver: \(AXIsProcessTrusted() ? "да" : "нет"))", category: "focus")
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        removeAXObserver()
        started = false
    }

    public func refresh(force: Bool) {
        let state = GameFocusMonitor.snapshot(config: config)
        current = state
        installAXObserverIfNeeded(pid: state.frontmostPID)
        let signature = state.signature
        if force || signature != lastSignature {
            lastSignature = signature
            logger.debug("фокус: \(state.shortDescription)", category: "focus")
            onChange?(state)
        }
    }

    public static func snapshot(config: FocusConfig) -> FocusState {
        let matcher = GameMatcher(config: config)
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications
        let gameApplications = running.filter { matcher.matches($0) }
        let frontmost = workspace.frontmostApplication
        var state = FocusState()
        state.timestamp = Date()
        state.frontmostPID = frontmost?.processIdentifier ?? 0
        state.frontmostName = frontmost?.localizedName
        state.gameRunning = !gameApplications.isEmpty
        state.gamePID = gameApplications.first?.processIdentifier ?? 0
        state.gameName = gameApplications.first?.localizedName
        state.gameExecutable = gameApplications.first?.executableURL?.path
        if let frontmost, matcher.matches(frontmost) {
            state.isGameFrontmost = true
            state.gamePID = frontmost.processIdentifier
            state.gameName = frontmost.localizedName
            state.gameExecutable = frontmost.executableURL?.path
            state.matchedBy = frontmost.bundleIdentifier ?? frontmost.executableURL?.lastPathComponent
        } else if gameApplications.contains(where: { $0.processIdentifier == frontmost?.processIdentifier }) {
            state.isGameFrontmost = true
        }

        let window = windowInfo(pid: state.isGameFrontmost ? state.frontmostPID : state.gamePID)
        state.windowTitle = window?.title
        if !state.isGameFrontmost, let title = window?.title,
           config.gameWindowTitles.contains(where: { title.localizedCaseInsensitiveContains($0) }) {
            state.isGameFrontmost = true
        }
        state.shouldInject = state.gameRunning && (state.isGameFrontmost || !config.requireGameFocus)
        return state
    }

    private static func windowInfo(pid: pid_t) -> (title: String?, bounds: CGRect)? {
        guard pid > 0 else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var best: (title: String?, bounds: CGRect)?
        var bestArea: CGFloat = 0
        for entry in raw {
            guard let owner = entry[kCGWindowOwnerPID as String] as? pid_t, owner == pid else { continue }
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            var bounds = CGRect.zero
            if let dictionary = entry[kCGWindowBounds as String] as? [String: Any] {
                bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) ?? .zero
            }
            let area = bounds.width * bounds.height
            guard area >= bestArea else { continue }
            bestArea = area
            let title = entry[kCGWindowName as String] as? String
            best = (title, bounds)
        }
        return best
    }

    private func installAXObserverIfNeeded(pid: pid_t) {
        guard pid > 0, pid != observedPID, AXIsProcessTrusted() else { return }
        removeAXObserver()
        var observer: AXObserver?
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverCreate(pid, axObserverCallback, &observer)
        guard result == .success, let observer else {
            logger.debug("AXObserverCreate завершился ошибкой: \(result.rawValue)", category: "focus")
            return
        }
        let element = AXUIElementCreateApplication(pid)
        let added = AXObserverAddNotification(observer, element, kAXFocusedWindowChangedNotification as CFString, refcon)
        guard added == .success else {
            logger.debug("AXObserverAddNotification завершился ошибкой: \(added.rawValue)", category: "focus")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer
        observedPID = pid
        logger.debug("AXObserver установлен для pid \(pid)", category: "focus")
    }

    private func removeAXObserver() {
        guard let observer = axObserver else { return }
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = nil
        observedPID = 0
    }
}

private func axObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let monitor = Unmanaged<GameFocusMonitor>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async {
        monitor.refresh(force: true)
    }
}
