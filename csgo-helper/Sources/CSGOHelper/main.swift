import AppKit
import CSGOHelperCore
import Darwin
import Foundation

private enum CLIContext {
    static var options = CLIOptions()
}

// Точка входа CSGO Helper. В режиме UI это лёгкое приложение в меню-баре;
// тот же бинарник поддерживает headless и диагностические режимы без NSApplication.

private func writeStandardError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

private func fail(_ error: Error) -> Never {
    writeStandardError("ошибка: \(error.localizedDescription)")
    exit(2)
}

private func pad(_ text: String, _ width: Int) -> String {
    if text.count >= width { return text }
    return text + String(repeating: " ", count: width - text.count)
}

private func resolveConfigAndPatterns() throws -> (configURL: URL, config: HelperConfig, patternsURL: URL, patterns: PatternStore) {
    let configURL = ConfigStore.resolveURL(explicit: CLIContext.options.configPath)
    var (config, _) = try ConfigStore(url: configURL).loadOrCreate()
    let patterns = try PatternStore.load(explicit: CLIContext.options.patternsPath)
    if let weapon = CLIContext.options.weapon {
        guard patterns.weapon(id: weapon) != nil else {
            throw HelperError.patterns("оружие \"\(weapon)\" не найдено; см. --list-weapons")
        }
        config.recoil.weapon = weapon
    }
    if CLIContext.options.dryRun { config.logging.dryRun = true }
    if let level = CLIContext.options.logLevel { config.logging.level = level }
    if let logPath = CLIContext.options.logPath { config.logging.file = logPath }
    config = try config.validated()
    return (configURL, config, patterns.sourceURL, patterns)
}

private func configureLogger(_ config: HelperConfig, headless: Bool) {
    let console = !CLIContext.options.quiet && (headless || config.logging.console)
    let file: URL? = CLIContext.options.noLog ? nil : HelperPaths.url(from: config.logging.file)
    Logger.shared.configure(
        level: config.logging.level,
        file: file,
        console: console,
        maxFileBytes: config.logging.maxFileBytes
    )
}

private func printWeaponTable(_ patterns: PatternStore) {
    print(pad("id", 13) + "name                          rpm   mag  mode           quality    source")
    print(String(repeating: "-", count: 103))
    for weapon in patterns.weapons {
        let source = weapon.isMeasured ? "spray.training" : "fallback"
        print(
            pad(weapon.id, 13)
                + pad(weapon.displayName, 30)
                + pad(String(weapon.rpm), 6)
                + pad(String(weapon.magazine), 5)
                + pad(weapon.fireMode, 15)
                + pad(weapon.quality.rawValue, 11)
                + source
        )
    }
    print("")
    print("Всего: \(patterns.weapons.count), измерено: \(patterns.measuredCount), эвристика: \(patterns.heuristicCount)")
    print("Источник: \(patterns.sourceURL.path)")
    print("Паттерны заданы в градусах компенсации; +x вправо, +y вниз. Первый выстрел не компенсируется.")
}

private func runSelfTest() -> Never {
    let configURL = ConfigStore.resolveURL(explicit: CLIContext.options.configPath)
    var config = HelperConfig()
    do {
        config = try ConfigStore(url: configURL).loadOrCreate().config
    } catch {
        writeStandardError("предупреждение: конфиг не загружен (\(error.localizedDescription)); selftest использует значения по умолчанию")
    }
    let patterns: PatternStore
    do {
        patterns = try PatternStore.load(explicit: CLIContext.options.patternsPath)
    } catch {
        writeStandardError("ошибка: \(error.localizedDescription)")
        exit(2)
    }
    let results = SelfTest.run(patternStore: patterns, config: config)
    var failures = 0
    for result in results {
        if !result.passed { failures += 1 }
        print("[\(result.passed ? "PASS" : "FAIL")] \(result.name): \(result.detail)")
    }
    print("")
    print("Итог: \(results.count - failures)/\(results.count) проверок пройдено")
    exit(failures == 0 ? 0 : 1)
}

private func runDiagnostics() -> Never {
    let configURL = ConfigStore.resolveURL(explicit: CLIContext.options.configPath)
    var config: HelperConfig?
    var configError: String?
    do {
        config = try ConfigStore(url: configURL).loadOrCreate().config
    } catch {
        configError = error.localizedDescription
    }
    var patterns: PatternStore?
    var patternsError: String?
    var patternsURL: URL?
    do {
        let store = try PatternStore.load(explicit: CLIContext.options.patternsPath)
        patterns = store
        patternsURL = store.sourceURL
    } catch {
        patternsError = error.localizedDescription
    }
    print(Diagnostics.report(
        configURL: configURL,
        config: config,
        configError: configError,
        patternsURL: patternsURL,
        patterns: patterns,
        patternsError: patternsError
    ))
    exit(0)
}

private func printPermissions() -> Never {
    let status = Permissions.status()
    print("Проверка разрешений (\(HelperMeta.version)):")
    print("  Accessibility (отправка событий): \(status.accessibilityTrusted ? "OK" : "НЕТ")")
    print("  CGEvent post:                    \(status.canPostEvents ? "OK" : "НЕТ")")
    print("  Input Monitoring (перехват):     \(status.canListenToEvents ? "OK" : "НЕТ")")
    print("  Secure Input:                    \(status.secureInputEnabled ? "ВКЛ" : "выкл")")
    print("")
    print("Выдать: Системные настройки → Конфиденциальность и безопасность →")
    print("  Accessibility и Input Monitoring → добавить CSGOHelper.app.")
    print("После изменения разрешений перезапустите helper.")
    exit(0)
}

private func requestPermissions() -> Never {
    Permissions.requestAllPrompts()
    print("Запрошены разрешения Accessibility и Input Monitoring.")
    print("Если диалоги не появились, добавьте .app вручную:")
    print("  Системные настройки → Конфиденциальность и безопасность → Accessibility")
    print("  Системные настройки → Конфиденциальность и безопасность → Мониторинг ввода")
    print("Текущее состояние: \(Permissions.status().summary)")
    exit(0)
}

private func printConfig() -> Never {
    let url = ConfigStore.resolveURL(explicit: CLIContext.options.configPath)
    do {
        let store = ConfigStore(url: url)
        let (config, created) = try store.loadOrCreate()
        print("Конфиг: \(url.path)\(created ? " (создан)" : "")")
        print(try config.jsonString(), terminator: "")
        exit(0)
    } catch {
        fail(error)
    }
}

private func headlessRun() -> Never {
    let configURL = ConfigStore.resolveURL(explicit: CLIContext.options.configPath)
    let config: HelperConfig
    let patterns: PatternStore
    do {
        let loaded = try resolveConfigAndPatterns()
        config = loaded.config
        patterns = loaded.patterns
    } catch {
        fail(error)
    }
    configureLogger(config, headless: true)
    let lock = InstanceLock()
    do {
        try lock.acquire()
    } catch {
        fail(error)
    }
    if CLIContext.options.requestPermissionsAtLaunch {
        Permissions.requestAllPrompts()
    }
    if CLIContext.options.waitForGame {
        Logger.shared.info("ожидание окна CS:GO; хоткеи активируются только при фокусе игры", category: "run")
    }
    if Bundle.main.bundleURL.pathExtension != "app" {
        Logger.shared.warn("запуск не из .app: TCC может привязать разрешения к терминалу/бинарнику; для игры используйте build/CSGOHelper.app", category: "run")
    }
    let engine: HelperEngine
    do {
        engine = try HelperEngine(config: config, patterns: patterns)
    } catch {
        fail(error)
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    var lastLine = ""
    var seenGame = false
    var exitWorkItem: DispatchWorkItem?
    engine.onStatusChange = { status in
        let toggles = "all=\(status.masterEnabled ? "on" : "off") recoil=\(status.recoilEnabled ? "on" : "off") "
            + "snap=\(status.snapTapEnabled ? "on" : "off") bhop=\(status.bunnyHopEnabled ? "on" : "off")"
        let permission = status.permissions.allRequired ? "perms=ok" : "perms=missing"
        let tap = status.tapRunning ? "tap=on" : "tap=off"
        let dry = status.dryRun ? " dry-run" : ""
        let line = "[\(formatter.string(from: Date()))] \(status.focus.shortDescription) | \(status.weaponID) "
            + "[\(status.weaponQuality.rawValue)] | \(toggles) | \(tap) | \(permission)\(dry)"
        if line != lastLine {
            print(line)
            fflush(stdout)
            lastLine = line
        }
        if status.focus.gameRunning {
            seenGame = true
            exitWorkItem?.cancel()
            exitWorkItem = nil
        } else if seenGame, CLIContext.options.exitOnGameExit {
            guard exitWorkItem == nil else { return }
            let item = DispatchWorkItem {
                Logger.shared.info("игра завершена, helper выходит по --exit-on-game-exit", category: "run")
                engine.stop()
                exit(0)
            }
            exitWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
        }
    }
    engine.start()
    Logger.shared.info("helper запущен в headless-режиме; конфиг \(configURL.path)", category: "run")
    print("CSGO Helper \(HelperMeta.version) запущен. Ctrl+C для выхода.")
    fflush(stdout)

    var signalSources: [DispatchSourceSignal] = []
    for number in [SIGINT, SIGTERM] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler {
            Logger.shared.info("получен сигнал \(number), завершение", category: "run")
            engine.stop()
            lock.release()
            Logger.shared.close()
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }
    withExtendedLifetime(signalSources) {
        RunLoop.main.run()
    }
    exit(0)
}

private func guiRun() -> Never {
    let configURL = ConfigStore.resolveURL(explicit: CLIContext.options.configPath)
    let config: HelperConfig
    let patterns: PatternStore
    do {
        let loaded = try resolveConfigAndPatterns()
        config = loaded.config
        patterns = loaded.patterns
    } catch {
        fail(error)
    }
    configureLogger(config, headless: false)
    let lock = InstanceLock()
    do {
        try lock.acquire()
    } catch {
        fail(error)
    }
    let engine: HelperEngine
    do {
        engine = try HelperEngine(config: config, patterns: patterns)
    } catch {
        fail(error)
    }

    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let delegate = CSGOAppDelegate(
        engine: engine,
        config: config,
        patterns: patterns,
        configURL: configURL,
        options: CLIContext.options,
        lock: lock
    )
    application.delegate = delegate
    withExtendedLifetime(delegate) {
        application.run()
    }
    exit(0)
}

// MARK: - Entry

let parsedOptions: CLIOptions
do {
    parsedOptions = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail(error)
}
CLIContext.options = parsedOptions

switch parsedOptions.command {
case .help:
    print(CLIOptions.helpText)
    exit(0)
case .version:
    print("csgo-helper \(HelperMeta.version)")
    exit(0)
case .listWeapons:
    do {
        let patterns = try PatternStore.load(explicit: parsedOptions.patternsPath)
        printWeaponTable(patterns)
        exit(0)
    } catch {
        fail(error)
    }
case .selfTest:
    runSelfTest()
case .diagnose:
    runDiagnostics()
case .permissionStatus:
    printPermissions()
case .requestPermissions:
    requestPermissions()
case .printConfig:
    printConfig()
case .run:
    if parsedOptions.headless {
        headlessRun()
    } else {
        guiRun()
    }
}
