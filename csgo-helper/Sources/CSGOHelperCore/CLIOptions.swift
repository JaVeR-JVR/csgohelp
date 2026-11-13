import Foundation

public enum CLICommand: Equatable {
    case run
    case selfTest
    case listWeapons
    case diagnose
    case printConfig
    case permissionStatus
    case requestPermissions
    case help
    case version
}

public struct CLIOptions: Equatable {
    public var command: CLICommand = .run
    public var configPath: String?
    public var patternsPath: String?
    public var weapon: String?
    public var dryRun = false
    public var headless = false
    public var waitForGame = false
    public var exitOnGameExit = false
    public var quiet = false
    public var noLog = false
    public var logPath: String?
    public var logLevel: LogLevel?
    public var requestPermissionsAtLaunch = false

    public init() {}

    public static func parse(_ arguments: [String]) throws -> CLIOptions {
        var options = CLIOptions()
        var index = 0
        func requireValue(_ flag: String) throws -> String {
            index += 1
            guard index < arguments.count, !arguments[index].hasPrefix("-") else {
                throw HelperError.configuration("для \(flag) требуется значение")
            }
            return arguments[index]
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--config":
                options.configPath = try requireValue(argument)
            case "--patterns":
                options.patternsPath = try requireValue(argument)
            case "--weapon":
                options.weapon = try requireValue(argument)
            case "--log", "--log-file":
                if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("-") {
                    index += 1
                    options.logPath = arguments[index]
                } else {
                    options.logPath = HelperPaths.defaultLogURL.path
                }
            case "--log-level":
                let value = try requireValue(argument)
                guard let level = LogLevel(rawValue: value.lowercased()) else {
                    throw HelperError.configuration("неизвестный уровень лога \"\(value)\"")
                }
                options.logLevel = level
            case "--dry-run":
                options.dryRun = true
            case "--headless", "--no-gui", "--no-menu":
                options.headless = true
            case "--wait-for-game":
                options.waitForGame = true
            case "--exit-on-game-exit":
                options.exitOnGameExit = true
            case "--quiet":
                options.quiet = true
            case "--no-log":
                options.noLog = true
            case "--request-permissions":
                options.requestPermissionsAtLaunch = true
            case "--selftest", "--self-test":
                options.command = .selfTest
            case "--list-weapons":
                options.command = .listWeapons
            case "--diagnose":
                options.command = .diagnose
            case "--print-config":
                options.command = .printConfig
            case "--permissions":
                options.command = .permissionStatus
            case "--help", "-h":
                options.command = .help
            case "--version", "-v":
                options.command = .version
            case "--run":
                options.command = .run
            default:
                throw HelperError.configuration("неизвестный аргумент \"\(argument)\" (см. --help)")
            }
            index += 1
        }
        return options
    }

    public static let helpText = """
    CSGO Helper \(HelperMeta.version) — компенсация отдачи и макросы движения для CS:GO legacy на macOS.

    Использование:
      csgo-helper [команда] [опции]

    Команды:
      (без команды)          запустить helper (меню-бар или --headless)
      --selftest             проверить паттерны, математику, конфиг и хоткеи
      --list-weapons         показать все профили оружия и источники паттернов
      --diagnose             диагностика: разрешения, фокус, игра, паттерны, LaunchAgent
      --print-config         создать/показать конфиг и путь к нему
      --permissions          показать состояние разрешений
      --request-permissions  запросить Accessibility/Input Monitoring и выйти
      --help                 эта справка
      --version              версия

    Опции запуска:
      --config PATH          конфиг JSON (по умолчанию ~/Library/Application Support/CSGOHelper/config.json)
      --patterns PATH        таблица паттернов (по умолчанию Resources/patterns.json)
      --weapon ID            стартовое оружие (ak47, m4a4, ...)
      --dry-run              не отправлять события, только логировать
      --log [PATH]           писать лог в файл (по умолчанию ~/Library/Logs/CSGOHelper/helper.log)
      --log-level LEVEL      trace|debug|info|warn|error|off
      --headless             без меню-бара и NSApplication; статус в stdout
      --wait-for-game        ждать окно игры (для LaunchAgent)
      --exit-on-game-exit    выйти после завершения игры (для Steam-обёртки)
      --quiet                не дублировать лог в stderr
      --no-log               не писать файл лога

    Горячие клавиши (работают только когда CS:GO — активное окно):
      Shift+I  включить/выключить всё
      Shift+1  отдача
      Shift+2  snap tap
      Shift+3  bunny hop
      Shift+]  следующее оружие
      Shift+[  предыдущее оружие
      Shift+0  echo текущего статуса в консоль игры

    Примеры:
      make
      ./build/CSGOHelper.app/Contents/MacOS/csgo-helper --diagnose
      ./build/CSGOHelper.app/Contents/MacOS/csgo-helper --dry-run --headless --weapon ak47
      ./build/CSGOHelper.app/Contents/MacOS/csgo-helper --config ./Config/config.example.json
    """
}
