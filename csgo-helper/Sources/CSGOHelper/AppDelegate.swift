import AppKit
import CSGOHelperCore
import Darwin
import Foundation

final class CSGOAppDelegate: NSObject, NSApplicationDelegate {
    private let engine: HelperEngine
    private let config: HelperConfig
    private let patterns: PatternStore
    private let configURL: URL
    private let options: CLIOptions
    private let lock: InstanceLock
    private var statusMenu: StatusMenuController?
    private let permissionGuide = PermissionGuidePanel()
    private var signalSources: [DispatchSourceSignal] = []
    private var seenGame = false
    private var exitWorkItem: DispatchWorkItem?
    private var permissionGuideShown = false

    init(
        engine: HelperEngine,
        config: HelperConfig,
        patterns: PatternStore,
        configURL: URL,
        options: CLIOptions,
        lock: InstanceLock
    ) {
        self.engine = engine
        self.config = config
        self.patterns = patterns
        self.configURL = configURL
        self.options = options
        self.lock = lock
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusMenu = StatusMenuController(
            engine: engine,
            config: config,
            patterns: patterns,
            configURL: configURL,
            showMenuBarItem: config.showMenuBarItem
        )
        self.statusMenu = statusMenu
        engine.onStatusChange = { [weak self] status in
            self?.statusMenu?.update(status)
            self?.handleExitPolicy(status)
        }
        engine.start()
        installSignalHandlers()
        Logger.shared.info("GUI запущен; bundle \(Bundle.main.bundleURL.path)", category: "app")

        let status = Permissions.status()
        Logger.shared.info("разрешения: \(status.summary)", category: "app")
        if config.requestPermissionsOnStart && !status.allRequired {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.showPermissionGuide(requestPrompts: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("завершение приложения", category: "app")
        exitWorkItem?.cancel()
        engine.stop()
        lock.release()
        Logger.shared.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func installSignalHandlers() {
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func showPermissionGuide(requestPrompts: Bool) {
        guard !permissionGuideShown else { return }
        permissionGuideShown = true
        if requestPrompts {
            Permissions.requestAllPrompts()
        }
        let status = Permissions.status()
        guard !status.allRequired else {
            Logger.shared.info("разрешения выданы: \(status.summary)", category: "app")
            return
        }
        Logger.shared.warn("не хватает разрешений: \(status.summary)", category: "app")
        // Окно намеренно немадальное: экземпляр из LaunchAgent должен
        // продолжать обрабатывать SIGTERM и события workspace, пока панель открыта.
        permissionGuide.show(status: status)
    }

    private func handleExitPolicy(_ status: EngineStatus) {
        guard options.exitOnGameExit else { return }
        if status.focus.gameRunning {
            seenGame = true
            exitWorkItem?.cancel()
            exitWorkItem = nil
        } else if seenGame, exitWorkItem == nil {
            let item = DispatchWorkItem { [weak self] in
                Logger.shared.info("игра завершена, helper выходит по --exit-on-game-exit", category: "run")
                self?.engine.stop()
                NSApp.terminate(nil)
            }
            exitWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
        }
    }
}
