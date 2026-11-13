import AppKit
import CSGOHelperCore
import Foundation

final class StatusMenuController: NSObject, NSMenuDelegate {
    private let engine: HelperEngine
    private let config: HelperConfig
    private let patterns: PatternStore
    private let configURL: URL

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let focusItem = NSMenuItem(title: "Запуск…", action: nil, keyEquivalent: "")
    private let tapItem = NSMenuItem(title: "Перехват: —", action: nil, keyEquivalent: "")
    private let masterItem = NSMenuItem(title: "Всё (Shift+I)", action: nil, keyEquivalent: "")
    private let recoilItem = NSMenuItem(title: "Отдача (Shift+1)", action: nil, keyEquivalent: "")
    private let snapItem = NSMenuItem(title: "Snap Tap (Shift+2)", action: nil, keyEquivalent: "")
    private let bhopItem = NSMenuItem(title: "Bunny Hop (Shift+3)", action: nil, keyEquivalent: "")
    private let dryRunItem = NSMenuItem(title: "DRY-RUN: события не отправляются", action: nil, keyEquivalent: "")
    private var weaponItems: [String: NSMenuItem] = [:]
    private var diagnosticsWindow: NSWindow?
    private var status = EngineStatus()

    init(engine: HelperEngine, config: HelperConfig, patterns: PatternStore, configURL: URL, showMenuBarItem: Bool) {
        self.engine = engine
        self.config = config
        self.patterns = patterns
        self.configURL = configURL
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        statusItem.menu = menu
        statusItem.isVisible = showMenuBarItem
        menu.delegate = self
        update(engine.currentStatus())
    }

    private func buildMenu() {
        menu.autoenablesItems = false
        focusItem.isEnabled = false
        tapItem.isEnabled = false
        dryRunItem.isEnabled = false
        dryRunItem.isHidden = true
        menu.addItem(focusItem)
        menu.addItem(tapItem)
        menu.addItem(dryRunItem)
        menu.addItem(.separator())

        for (item, action) in [
            (masterItem, #selector(toggleMaster)),
            (recoilItem, #selector(toggleRecoil)),
            (snapItem, #selector(toggleSnapTap)),
            (bhopItem, #selector(toggleBunnyHop))
        ] {
            item.target = self
            item.action = action
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let weaponRoot = NSMenuItem(title: "Оружие", action: nil, keyEquivalent: "")
        let weaponMenu = NSMenu()
        weaponMenu.autoenablesItems = false
        let legend = NSMenuItem(title: "● измерено   ~ эвристика", action: nil, keyEquivalent: "")
        legend.isEnabled = false
        weaponMenu.addItem(legend)
        weaponMenu.addItem(.separator())
        var previousClass: String?
        for weapon in patterns.weapons {
            if let previousClass, previousClass != weapon.weaponClass {
                weaponMenu.addItem(.separator())
            }
            previousClass = weapon.weaponClass
            let marker = weapon.isMeasured ? "●" : "~"
            let item = NSMenuItem(title: "\(marker) \(weapon.displayName)", action: #selector(selectWeapon(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = weapon.id
            item.toolTip = "\(weapon.id), \(weapon.rpm) rpm, \(weapon.magazine) патронов, \(weapon.patternSource)"
            weaponMenu.addItem(item)
            weaponItems[weapon.id] = item
        }
        weaponRoot.submenu = weaponMenu
        menu.addItem(weaponRoot)

        menu.addItem(.separator())
        addItem("Статус в консоль игры (Shift+0)", #selector(echoStatus))
        addItem("Перезапустить перехват ввода", #selector(restartTap))
        addItem("Проверить разрешения…", #selector(showPermissions))
        addItem("Диагностика…", #selector(showDiagnostics))
        addItem("Открыть конфиг", #selector(openConfig))
        addItem("Открыть журнал", #selector(openLog))
        menu.addItem(.separator())
        addItem("О программе", #selector(showAbout))
        addItem("Выход", #selector(quit))
    }

    private func addItem(_ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    func menuWillOpen(_ menu: NSMenu) {
        update(engine.currentStatus())
    }

    func update(_ status: EngineStatus) {
        self.status = status
        if status.focus.shouldInject {
            focusItem.title = "В игре · \(status.weaponName)"
        } else if status.focus.gameRunning {
            focusItem.title = "Ожидание фокуса игры · \(status.weaponName)"
        } else {
            focusItem.title = "Игра не запущена · \(status.weaponName)"
        }
        if !status.permissions.allRequired {
            focusItem.title = "⚠︎ Нет разрешений · \(status.weaponName)"
        }
        if status.injectionAvailable {
            tapItem.title = status.tapRunning ? "Перехват: OK · отправка: OK" : "Перехват: нет · отправка: OK"
        } else {
            tapItem.title = "Перехват: \(status.tapRunning ? "OK" : "нет") · отправка: НЕТ"
        }
        dryRunItem.isHidden = !status.dryRun
        setToggle(masterItem, status.masterEnabled)
        setToggle(recoilItem, status.recoilEnabled)
        setToggle(snapItem, status.snapTapEnabled)
        setToggle(bhopItem, status.bunnyHopEnabled)
        for (id, item) in weaponItems {
            item.state = id == status.weaponID ? .on : .off
        }
        updateIcon(status)
        statusItem.button?.toolTip = "CSGO Helper \(HelperMeta.version)\n\(status.focus.shortDescription)\n"
            + "\(status.weaponName) [\(status.weaponQuality.rawValue)]\n"
            + status.permissions.summary
    }

    private func setToggle(_ item: NSMenuItem, _ enabled: Bool) {
        item.state = enabled ? .on : .off
    }

    private func updateIcon(_ status: EngineStatus) {
        let symbol: String
        if !status.running {
            symbol = "pause.circle"
        } else if !status.permissions.allRequired || !status.injectionAvailable {
            symbol = "exclamationmark.triangle"
        } else if status.focus.shouldInject {
            symbol = "scope"
        } else if status.focus.gameRunning {
            symbol = "hourglass"
        } else {
            symbol = "gamecontroller"
        }
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "CSGO Helper") {
            image.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.title = ""
        } else {
            statusItem.button?.title = "CS"
        }
    }

    // MARK: - Действия меню

    @objc private func toggleMaster() {
        engine.setMasterEnabled(!status.masterEnabled, announce: false)
    }

    @objc private func toggleRecoil() {
        engine.setRecoilEnabled(!status.recoilEnabled, announce: false)
    }

    @objc private func toggleSnapTap() {
        engine.setSnapTapEnabled(!status.snapTapEnabled, announce: false)
    }

    @objc private func toggleBunnyHop() {
        engine.setBunnyHopEnabled(!status.bunnyHopEnabled, announce: false)
    }

    @objc private func selectWeapon(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        engine.selectWeapon(id: id, announce: false)
    }

    @objc private func echoStatus() {
        engine.echoStatus()
    }

    @objc private func restartTap() {
        engine.restartInputTap()
    }

    @objc private func showPermissions() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Разрешения CSGO Helper"
        alert.informativeText = Permissions.status().summary
            + "\n\nAccessibility — отправка событий. Input Monitoring — перехват Shift+I, A/D и Space. "
            + "После выдачи разрешений перезапустите helper."
        alert.alertStyle = Permissions.status().allRequired ? .informational : .warning
        alert.addButton(withTitle: "Открыть Accessibility")
        alert.addButton(withTitle: "Открыть Input Monitoring")
        alert.addButton(withTitle: "Закрыть")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Permissions.openAccessibilitySettings()
        } else if response == .alertSecondButtonReturn {
            Permissions.openInputMonitoringSettings()
        }
    }

    @objc private func showDiagnostics() {
        let report = Diagnostics.report(
            configURL: configURL,
            config: config,
            configError: nil,
            patternsURL: patterns.sourceURL,
            patterns: patterns,
            patternsError: nil
        )
        if let window = diagnosticsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CSGO Helper — диагностика"
        window.center()
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        textView.string = report
        scroll.documentView = textView
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        diagnosticsWindow = window
    }

    @objc private func openConfig() {
        if !FileManager.default.fileExists(atPath: configURL.path) {
            do {
                try ConfigStore(url: configURL).save(config)
            } catch {
                showSimpleAlert("Не удалось создать конфиг", error.localizedDescription)
                return
            }
        }
        NSWorkspace.shared.open(configURL)
    }

    @objc private func openLog() {
        let url = HelperPaths.url(from: config.logging.file)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([HelperPaths.logDirectory])
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "CSGO Helper \(HelperMeta.version)"
        alert.informativeText = """
        Компенсация отдачи, Snap Tap и авто-банихоп для CS:GO legacy на macOS.

        Работает только через синтез событий ввода: без чтения памяти игры, без инъекций dylib, без аимбота/триггербота и без обхода VAC.

        Паттерны: spray.training (MIT), Steam guide 2830373896 и детерминированная эвристика. Оружие выбирается вручную: внешний процесс не может определить его без чтения памяти или GSI.

        Использование макросов может нарушать Steam Subscriber Agreement. Не используйте на публичных серверах.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showSimpleAlert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
