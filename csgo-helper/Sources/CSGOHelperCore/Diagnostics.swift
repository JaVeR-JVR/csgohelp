import Foundation

public enum Diagnostics {
    public static func report(
        configURL: URL,
        config: HelperConfig?,
        configError: String?,
        patternsURL: URL?,
        patterns: PatternStore?,
        patternsError: String?
    ) -> String {
        var lines: [String] = []
        func section(_ title: String) {
            lines.append("")
            lines.append("== \(title) ==")
        }

        let version = ProcessInfo.processInfo.operatingSystemVersionString
        let arch: String
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64 (возможно, Rosetta)"
        #else
        arch = "unknown"
        #endif

        section("Система")
        lines.append("CSGO Helper \(HelperMeta.version), macOS \(version), \(arch)")
        lines.append("Executable: \(Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? "?")")
        lines.append("Bundle: \(Bundle.main.bundleURL.path)")

        section("Разрешения")
        let permissions = Permissions.status()
        lines.append(permissions.accessibilityTrusted ? "Accessibility: OK" : "Accessibility: НЕТ — включите в System Settings → Privacy & Security → Accessibility")
        lines.append(permissions.canPostEvents ? "Post events: OK" : "Post events: НЕТ — нужно Accessibility")
        lines.append(permissions.canListenToEvents ? "Input Monitoring: OK" : "Input Monitoring: НЕТ — включите в Privacy & Security → Input Monitoring")
        lines.append(permissions.secureInputEnabled ? "Secure Input: ВКЛ — клавиатурный перехват может не работать, пока активно поле пароля/терминал" : "Secure Input: выкл")
        if !permissions.allRequired {
            lines.append("Запрос разрешений: csgo-helper --request-permissions (или кнопка в меню)")
            lines.append("После выдачи разрешений перезапустите helper — TCC привязывает их к пути .app.")
        }

        section("Конфигурация")
        lines.append("Путь: \(configURL.path)")
        lines.append(FileManager.default.fileExists(atPath: configURL.path) ? "Файл существует" : "Файл отсутствует — будет создан при запуске")
        if let config {
            lines.append("sensitivity=\(config.sensitivity), m_yaw=\(config.mYaw), m_pitch=\(config.mPitch)")
            lines.append("оружие=\(config.recoil.weapon), dry-run=\(config.logging.dryRun)")
            lines.append("хоткеи: all=\(config.hotkeys.toggleAll), recoil=\(config.hotkeys.recoil), snap=\(config.hotkeys.snapTap), bhop=\(config.hotkeys.bunnyHop)")
        } else if let configError {
            lines.append("ОШИБКА: \(configError)")
        }

        section("Паттерны")
        if let patterns, let patternsURL {
            lines.append("Путь: \(patternsURL.path)")
            lines.append("Профилей: \(patterns.weapons.count), измерено: \(patterns.measuredCount), эвристика: \(patterns.heuristicCount)")
            let heuristic = patterns.weapons.filter { !$0.isMeasured }.map(\.id)
            lines.append("Эвристические профили: \(heuristic.joined(separator: ", "))")
            lines.append("Источник измеренных: spray.training (MIT), Steam guide 2830373896 — валидация")
        } else {
            lines.append("Паттерны не загружены: \(patternsError ?? "причина неизвестна")")
            lines.append("Укажите --patterns PATH или выполните python3 Tools/build_patterns.py")
        }

        section("Игра и фокус")
        let focusConfig = config?.focus ?? FocusConfig()
        let focus = GameFocusMonitor.snapshot(config: focusConfig)
        lines.append("Игра запущена: \(focus.gameRunning ? "да" : "нет")")
        lines.append("Игра в фокусе: \(focus.isGameFrontmost ? "да" : "нет")")
        lines.append("Инъекция разрешена: \(focus.shouldInject ? "да" : "нет")")
        lines.append("Frontmost: \(focus.frontmostName ?? "—") (pid \(focus.frontmostPID))")
        lines.append("Игровой процесс: \(focus.gameName ?? "—") (pid \(focus.gamePID)), \(focus.gameExecutable ?? "путь неизвестен")")
        lines.append("Окно: \(focus.windowTitle ?? "заголовок недоступен без Screen Recording")")
        let installs = SteamLocator.installations()
        if installs.isEmpty {
            lines.append("Установки Steam не найдены по стандартным путям")
        } else {
            for install in installs {
                lines.append((install.isLegacy ? "[legacy] " : "[CS2] ") + install.summary)
            }
        }
        lines.append("CS:GO legacy (Steam app 4465480) — целевая игра; CS2 может не поддерживаться этим профилем.")
        lines.append("Сканирование VPK: python3 Tools/extract_game_data.py --game \"<путь>\" --list")

        section("Автозапуск и обёртка")
        let launchAgent = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents/local.csgo.helper.plist")
        lines.append("LaunchAgent: \(launchAgent.path) — \(FileManager.default.fileExists(atPath: launchAgent.path) ? "установлен" : "не установлен")")
        let installedApp = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Applications/CSGOHelper.app")
        lines.append("Установленное приложение: \(installedApp.path) — \(FileManager.default.fileExists(atPath: installedApp.path) ? "есть" : "нет")")
        lines.append("Steam-обёртка: scripts/steam-launch-wrapper.sh (или ~/Applications/csgo-helper-steam.sh после make install)")

        section("Логи")
        lines.append("Файл: \(HelperPaths.defaultLogURL.path)")
        if let attributes = try? FileManager.default.attributesOfItem(atPath: HelperPaths.defaultLogURL.path),
           let size = attributes[.size] as? NSNumber {
            lines.append("Размер: \(size.intValue) байт")
        } else {
            lines.append("Файл ещё не создан")
        }

        section("Рекомендации")
        if permissions.secureInputEnabled {
            lines.append("- Закройте приложения с Secure Input (терминал с вводом пароля, менеджеры паролей) и перезапустите helper.")
        }
        if !permissions.canListenToEvents || !permissions.canPostEvents {
            lines.append("- Выдайте Accessibility и Input Monitoring, затем перезапустите .app (путь TCC должен быть стабильным).")
        }
        if let patterns, patterns.heuristicCount > 0 {
            lines.append("- \(patterns.heuristicCount) профилей используют эвристику; проверяйте их на закрытом сервере и настраивайте intensity.")
        }
        lines.append("- Включите raw input/окно игры в фокусе; Secure Input и удалённый рабочий стол блокируют синтетический ввод.")
        lines.append("- Не используйте на публичных серверах: макросы могут нарушать Steam Subscriber Agreement.")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
