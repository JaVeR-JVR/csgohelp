import Foundation

// MARK: - Перечисления

public enum LogLevel: String, Codable, CaseIterable, Comparable {
    case trace
    case debug
    case info
    case warn
    case error
    case off

    private var rank: Int {
        switch self {
        case .trace: return 0
        case .debug: return 1
        case .info: return 2
        case .warn: return 3
        case .error: return 4
        case .off: return 5
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

public enum ConsoleTextMode: String, Codable, CaseIterable {
    /// Виртуальные коды клавиш US-раскладки. Большинство привязок консоли CS:GO
    /// ожидают именно их.
    case keycode
    /// Инъекция Unicode-строки. Работает с не-US раскладками и IME, но некоторые
    /// сборки консоли Source её игнорируют; используйте только как запасной вариант.
    case unicode
}

public enum BunnyHopMode: String, Codable, CaseIterable {
    /// Повторяющиеся импульсы нажатие/отпускание, пока Space физически зажат.
    case spam
    /// Ожидание типичного окна приземления, затем импульсы с частотой тика.
    /// Обратной связи о состоянии «на земле» нет; окно приблизительное.
    case predictive
}

// MARK: - Секции конфигурации

public struct RecoilConfig: Codable, Equatable {
    public var enabled: Bool
    public var weapon: String
    public var intensity: Double
    /// До удержания ЛКМ в течение этого времени движение мыши не выполняется.
    /// Это защищает прицел от случайного сдвига при одиночных кликах и тапах.
    public var holdThresholdMs: Double
    /// Задержка перед компенсацией неавтоматического выстрела. Полуавтоматы
    /// управляются дискретными кликами, а не непрерывной кривой времени.
    public var semiAutoShotDelayMs: Double
    /// Сброс счётчика серии полуавтомата после такой паузы.
    public var burstResetMs: Double
    /// Предохранительный лимит counts мыши, инжектируемых за тик движка.
    public var maxCountsPerTick: Int
    /// Множитель частоты тиков игры при интерполяции паттерна.
    /// 1.0 соответствует RPM таблицы; меньшие значения смягчают кривую.
    public var patternTimeScale: Double
    public var compensateDuringFeedback: Bool

    public init(
        enabled: Bool = true,
        weapon: String = "ak47",
        intensity: Double = 1.0,
        holdThresholdMs: Double = 120,
        semiAutoShotDelayMs: Double = 18,
        burstResetMs: Double = 420,
        maxCountsPerTick: Int = 260,
        patternTimeScale: Double = 1.0,
        compensateDuringFeedback: Bool = false
    ) {
        self.enabled = enabled
        self.weapon = weapon
        self.intensity = intensity
        self.holdThresholdMs = holdThresholdMs
        self.semiAutoShotDelayMs = semiAutoShotDelayMs
        self.burstResetMs = burstResetMs
        self.maxCountsPerTick = maxCountsPerTick
        self.patternTimeScale = patternTimeScale
        self.compensateDuringFeedback = compensateDuringFeedback
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        weapon = try c.decodeIfPresent(String.self, forKey: .weapon) ?? "ak47"
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 1.0
        holdThresholdMs = try c.decodeIfPresent(Double.self, forKey: .holdThresholdMs) ?? 120
        semiAutoShotDelayMs = try c.decodeIfPresent(Double.self, forKey: .semiAutoShotDelayMs) ?? 18
        burstResetMs = try c.decodeIfPresent(Double.self, forKey: .burstResetMs) ?? 420
        maxCountsPerTick = try c.decodeIfPresent(Int.self, forKey: .maxCountsPerTick) ?? 260
        patternTimeScale = try c.decodeIfPresent(Double.self, forKey: .patternTimeScale) ?? 1.0
        compensateDuringFeedback = try c.decodeIfPresent(Bool.self, forKey: .compensateDuringFeedback) ?? false
    }
}

public struct SnapTapConfig: Codable, Equatable {
    public var enabled: Bool
    /// Очистка SOCD: когда A и D зажаты одновременно, побеждает последняя нажатая.
    public var socdEnabled: Bool
    /// Короткий тап противоположной клавишей после отпускания последней клавиши
    /// движения. Создаёт контр-импульс, укорачивающий скольжение.
    public var brakeTapEnabled: Bool
    public var holdMs: Double
    public var cooldownMs: Double
    /// Физические коды клавиш: A = 0, D = 2 на клавиатурах ANSI/ISO macOS.
    public var leftKeyCode: UInt16
    public var rightKeyCode: UInt16
    /// Игнорировать автоповторы и синтетические события с меткой HelperMeta.
    public var requirePhysicalEvent: Bool

    public init(
        enabled: Bool = true,
        socdEnabled: Bool = true,
        brakeTapEnabled: Bool = true,
        holdMs: Double = 22,
        cooldownMs: Double = 65,
        leftKeyCode: UInt16 = 0,
        rightKeyCode: UInt16 = 2,
        requirePhysicalEvent: Bool = true
    ) {
        self.enabled = enabled
        self.socdEnabled = socdEnabled
        self.brakeTapEnabled = brakeTapEnabled
        self.holdMs = holdMs
        self.cooldownMs = cooldownMs
        self.leftKeyCode = leftKeyCode
        self.rightKeyCode = rightKeyCode
        self.requirePhysicalEvent = requirePhysicalEvent
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        socdEnabled = try c.decodeIfPresent(Bool.self, forKey: .socdEnabled) ?? true
        brakeTapEnabled = try c.decodeIfPresent(Bool.self, forKey: .brakeTapEnabled) ?? true
        holdMs = try c.decodeIfPresent(Double.self, forKey: .holdMs) ?? 22
        cooldownMs = try c.decodeIfPresent(Double.self, forKey: .cooldownMs) ?? 65
        leftKeyCode = try c.decodeIfPresent(UInt16.self, forKey: .leftKeyCode) ?? 0
        rightKeyCode = try c.decodeIfPresent(UInt16.self, forKey: .rightKeyCode) ?? 2
        requirePhysicalEvent = try c.decodeIfPresent(Bool.self, forKey: .requirePhysicalEvent) ?? true
    }
}

public struct BunnyHopConfig: Codable, Equatable {
    public var enabled: Bool
    public var mode: BunnyHopMode
    /// 64 или 128. Частота тиков сервера неизвестна внешнему процессу,
    /// поэтому значение влияет только на интервал импульсов.
    public var tickRate: Int
    public var startDelayMs: Double
    public var pressHoldMs: Double
    public var pulseIntervalTicks: Int
    public var predictiveAirtimeMs: Double
    public var predictiveWindowMs: Double
    public var maxContinuousHoldMs: Double

    public init(
        enabled: Bool = true,
        mode: BunnyHopMode = .spam,
        tickRate: Int = 128,
        startDelayMs: Double = 60,
        pressHoldMs: Double = 8,
        pulseIntervalTicks: Int = 2,
        predictiveAirtimeMs: Double = 760,
        predictiveWindowMs: Double = 180,
        maxContinuousHoldMs: Double = 8000
    ) {
        self.enabled = enabled
        self.mode = mode
        self.tickRate = tickRate
        self.startDelayMs = startDelayMs
        self.pressHoldMs = pressHoldMs
        self.pulseIntervalTicks = pulseIntervalTicks
        self.predictiveAirtimeMs = predictiveAirtimeMs
        self.predictiveWindowMs = predictiveWindowMs
        self.maxContinuousHoldMs = maxContinuousHoldMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        mode = try c.decodeIfPresent(BunnyHopMode.self, forKey: .mode) ?? .spam
        tickRate = try c.decodeIfPresent(Int.self, forKey: .tickRate) ?? 128
        startDelayMs = try c.decodeIfPresent(Double.self, forKey: .startDelayMs) ?? 60
        pressHoldMs = try c.decodeIfPresent(Double.self, forKey: .pressHoldMs) ?? 8
        pulseIntervalTicks = try c.decodeIfPresent(Int.self, forKey: .pulseIntervalTicks) ?? 2
        predictiveAirtimeMs = try c.decodeIfPresent(Double.self, forKey: .predictiveAirtimeMs) ?? 760
        predictiveWindowMs = try c.decodeIfPresent(Double.self, forKey: .predictiveWindowMs) ?? 180
        maxContinuousHoldMs = try c.decodeIfPresent(Double.self, forKey: .maxContinuousHoldMs) ?? 8000
    }
}

public struct HotkeyConfig: Codable, Equatable {
    /// Строковая запись: "shift+i", "shift+1", "shift+]", "ctrl+alt+h".
    public var toggleAll: String
    public var recoil: String
    public var snapTap: String
    public var bunnyHop: String
    public var nextWeapon: String
    public var previousWeapon: String
    public var echoStatus: String

    public init(
        toggleAll: String = "shift+i",
        recoil: String = "shift+1",
        snapTap: String = "shift+2",
        bunnyHop: String = "shift+3",
        nextWeapon: String = "shift+]",
        previousWeapon: String = "shift+[",
        echoStatus: String = "shift+0"
    ) {
        self.toggleAll = toggleAll
        self.recoil = recoil
        self.snapTap = snapTap
        self.bunnyHop = bunnyHop
        self.nextWeapon = nextWeapon
        self.previousWeapon = previousWeapon
        self.echoStatus = echoStatus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        toggleAll = try c.decodeIfPresent(String.self, forKey: .toggleAll) ?? "shift+i"
        recoil = try c.decodeIfPresent(String.self, forKey: .recoil) ?? "shift+1"
        snapTap = try c.decodeIfPresent(String.self, forKey: .snapTap) ?? "shift+2"
        bunnyHop = try c.decodeIfPresent(String.self, forKey: .bunnyHop) ?? "shift+3"
        nextWeapon = try c.decodeIfPresent(String.self, forKey: .nextWeapon) ?? "shift+]"
        previousWeapon = try c.decodeIfPresent(String.self, forKey: .previousWeapon) ?? "shift+["
        echoStatus = try c.decodeIfPresent(String.self, forKey: .echoStatus) ?? "shift+0"
    }
}

public struct FeedbackConfig: Codable, Equatable {
    public var enabled: Bool
    /// Открыть консоль Source клавишей `, напечатать строку `echo`, нажать
    /// Return и снова закрыть. Никогда не использует `say` и не пишет в чат игры.
    public var consoleEcho: Bool
    public var openConsole: Bool
    public var closeConsoleAfterMs: Double
    public var textMode: ConsoleTextMode
    public var typeDelayMs: Double
    public var openDelayMs: Double
    public var consoleKeyCode: UInt16
    public var returnKeyCode: UInt16

    public init(
        enabled: Bool = true,
        consoleEcho: Bool = true,
        openConsole: Bool = true,
        closeConsoleAfterMs: Double = 900,
        textMode: ConsoleTextMode = .keycode,
        typeDelayMs: Double = 9,
        openDelayMs: Double = 120,
        consoleKeyCode: UInt16 = 50,
        returnKeyCode: UInt16 = 36
    ) {
        self.enabled = enabled
        self.consoleEcho = consoleEcho
        self.openConsole = openConsole
        self.closeConsoleAfterMs = closeConsoleAfterMs
        self.textMode = textMode
        self.typeDelayMs = typeDelayMs
        self.openDelayMs = openDelayMs
        self.consoleKeyCode = consoleKeyCode
        self.returnKeyCode = returnKeyCode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        consoleEcho = try c.decodeIfPresent(Bool.self, forKey: .consoleEcho) ?? true
        openConsole = try c.decodeIfPresent(Bool.self, forKey: .openConsole) ?? true
        closeConsoleAfterMs = try c.decodeIfPresent(Double.self, forKey: .closeConsoleAfterMs) ?? 900
        textMode = try c.decodeIfPresent(ConsoleTextMode.self, forKey: .textMode) ?? .keycode
        typeDelayMs = try c.decodeIfPresent(Double.self, forKey: .typeDelayMs) ?? 9
        openDelayMs = try c.decodeIfPresent(Double.self, forKey: .openDelayMs) ?? 120
        consoleKeyCode = try c.decodeIfPresent(UInt16.self, forKey: .consoleKeyCode) ?? 50
        returnKeyCode = try c.decodeIfPresent(UInt16.self, forKey: .returnKeyCode) ?? 36
    }
}

public struct FocusConfig: Codable, Equatable {
    public var requireGameFocus: Bool
    public var gameBundleIdentifiers: [String]
    public var gameProcessNames: [String]
    public var gameWindowTitles: [String]
    public var pollIntervalMs: Double
    /// Отпускать все синтетические клавиши при потере фокуса игрой. Настоятельно рекомендуется.
    public var releaseKeysOnFocusLoss: Bool

    public init(
        requireGameFocus: Bool = true,
        gameBundleIdentifiers: [String] = [
            "com.valvesoftware.csgo"
        ],
        gameProcessNames: [String] = [
            "csgo_osx64",
            "csgo"
        ],
        gameWindowTitles: [String] = [
            "Counter-Strike: Global Offensive",
            "CS:GO"
        ],
        pollIntervalMs: Double = 500,
        releaseKeysOnFocusLoss: Bool = true
    ) {
        self.requireGameFocus = requireGameFocus
        self.gameBundleIdentifiers = gameBundleIdentifiers
        self.gameProcessNames = gameProcessNames
        self.gameWindowTitles = gameWindowTitles
        self.pollIntervalMs = pollIntervalMs
        self.releaseKeysOnFocusLoss = releaseKeysOnFocusLoss
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requireGameFocus = try c.decodeIfPresent(Bool.self, forKey: .requireGameFocus) ?? true
        gameBundleIdentifiers = try c.decodeIfPresent([String].self, forKey: .gameBundleIdentifiers)
            ?? ["com.valvesoftware.csgo"]
        gameProcessNames = try c.decodeIfPresent([String].self, forKey: .gameProcessNames)
            ?? ["csgo_osx64", "csgo"]
        gameWindowTitles = try c.decodeIfPresent([String].self, forKey: .gameWindowTitles)
            ?? ["Counter-Strike: Global Offensive", "CS:GO"]
        pollIntervalMs = try c.decodeIfPresent(Double.self, forKey: .pollIntervalMs) ?? 500
        releaseKeysOnFocusLoss = try c.decodeIfPresent(Bool.self, forKey: .releaseKeysOnFocusLoss) ?? true
    }
}

public struct LoggingConfig: Codable, Equatable {
    public var level: LogLevel
    public var file: String
    public var console: Bool
    public var maxFileBytes: Int
    public var dryRun: Bool

    public init(
        level: LogLevel = .info,
        file: String = HelperPaths.defaultLogURL.path,
        console: Bool = false,
        maxFileBytes: Int = 2_000_000,
        dryRun: Bool = false
    ) {
        self.level = level
        self.file = file
        self.console = console
        self.maxFileBytes = maxFileBytes
        self.dryRun = dryRun
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decodeIfPresent(LogLevel.self, forKey: .level) ?? .info
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? HelperPaths.defaultLogURL.path
        console = try c.decodeIfPresent(Bool.self, forKey: .console) ?? false
        maxFileBytes = try c.decodeIfPresent(Int.self, forKey: .maxFileBytes) ?? 2_000_000
        dryRun = try c.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
    }
}

// MARK: - Корневая секция

public struct HelperConfig: Codable, Equatable {
    public var version: Int
    public var sensitivity: Double
    public var mYaw: Double
    public var mPitch: Double
    /// Запрашивать разрешения TCC при старте GUI. Отключите для полностью ручной настройки.
    public var requestPermissionsOnStart: Bool
    public var showMenuBarItem: Bool
    public var recoil: RecoilConfig
    public var snapTap: SnapTapConfig
    public var bunnyHop: BunnyHopConfig
    public var hotkeys: HotkeyConfig
    public var feedback: FeedbackConfig
    public var focus: FocusConfig
    public var logging: LoggingConfig

    public init(
        version: Int = 1,
        sensitivity: Double = 2.5,
        mYaw: Double = 0.022,
        mPitch: Double = 0.022,
        requestPermissionsOnStart: Bool = true,
        showMenuBarItem: Bool = true,
        recoil: RecoilConfig = RecoilConfig(),
        snapTap: SnapTapConfig = SnapTapConfig(),
        bunnyHop: BunnyHopConfig = BunnyHopConfig(),
        hotkeys: HotkeyConfig = HotkeyConfig(),
        feedback: FeedbackConfig = FeedbackConfig(),
        focus: FocusConfig = FocusConfig(),
        logging: LoggingConfig = LoggingConfig()
    ) {
        self.version = version
        self.sensitivity = sensitivity
        self.mYaw = mYaw
        self.mPitch = mPitch
        self.requestPermissionsOnStart = requestPermissionsOnStart
        self.showMenuBarItem = showMenuBarItem
        self.recoil = recoil
        self.snapTap = snapTap
        self.bunnyHop = bunnyHop
        self.hotkeys = hotkeys
        self.feedback = feedback
        self.focus = focus
        self.logging = logging
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 2.5
        mYaw = try c.decodeIfPresent(Double.self, forKey: .mYaw) ?? 0.022
        mPitch = try c.decodeIfPresent(Double.self, forKey: .mPitch) ?? 0.022
        requestPermissionsOnStart = try c.decodeIfPresent(Bool.self, forKey: .requestPermissionsOnStart) ?? true
        showMenuBarItem = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarItem) ?? true
        recoil = try c.decodeIfPresent(RecoilConfig.self, forKey: .recoil) ?? RecoilConfig()
        snapTap = try c.decodeIfPresent(SnapTapConfig.self, forKey: .snapTap) ?? SnapTapConfig()
        bunnyHop = try c.decodeIfPresent(BunnyHopConfig.self, forKey: .bunnyHop) ?? BunnyHopConfig()
        hotkeys = try c.decodeIfPresent(HotkeyConfig.self, forKey: .hotkeys) ?? HotkeyConfig()
        feedback = try c.decodeIfPresent(FeedbackConfig.self, forKey: .feedback) ?? FeedbackConfig()
        focus = try c.decodeIfPresent(FocusConfig.self, forKey: .focus) ?? FocusConfig()
        logging = try c.decodeIfPresent(LoggingConfig.self, forKey: .logging) ?? LoggingConfig()
    }

    public func validated() throws -> HelperConfig {
        var copy = self
        guard copy.version == 1 else {
            throw HelperError.configuration("поддерживается только version=1, получено \(copy.version)")
        }
        guard copy.sensitivity > 0, copy.sensitivity <= 20 else {
            throw HelperError.configuration("sensitivity должна быть больше 0 и не больше 20")
        }
        guard copy.mYaw > 0, copy.mYaw < 1, copy.mPitch > 0, copy.mPitch < 1 else {
            throw HelperError.configuration("mYaw и mPitch должны быть в диапазоне (0, 1)")
        }
        guard copy.recoil.intensity >= 0, copy.recoil.intensity <= 3 else {
            throw HelperError.configuration("recoil.intensity должна быть от 0 до 3")
        }
        guard copy.recoil.holdThresholdMs >= 0, copy.recoil.holdThresholdMs <= 2000 else {
            throw HelperError.configuration("recoil.holdThresholdMs должна быть от 0 до 2000")
        }
        guard copy.recoil.maxCountsPerTick > 0, copy.recoil.maxCountsPerTick <= 2000 else {
            throw HelperError.configuration("recoil.maxCountsPerTick должен быть от 1 до 2000")
        }
        guard copy.recoil.patternTimeScale > 0.1, copy.recoil.patternTimeScale <= 3 else {
            throw HelperError.configuration("recoil.patternTimeScale должна быть от 0.1 до 3")
        }
        guard copy.snapTap.holdMs >= 5, copy.snapTap.holdMs <= 100 else {
            throw HelperError.configuration("snapTap.holdMs должна быть от 5 до 100 мс")
        }
        guard copy.snapTap.cooldownMs >= 0, copy.snapTap.cooldownMs <= 500 else {
            throw HelperError.configuration("snapTap.cooldownMs должна быть от 0 до 500")
        }
        guard [64, 128].contains(copy.bunnyHop.tickRate) else {
            throw HelperError.configuration("bunnyHop.tickRate должна быть 64 или 128")
        }
        guard copy.bunnyHop.pressHoldMs >= 1, copy.bunnyHop.pressHoldMs <= 60 else {
            throw HelperError.configuration("bunnyHop.pressHoldMs должна быть от 1 до 60")
        }
        guard copy.bunnyHop.startDelayMs >= 0, copy.bunnyHop.startDelayMs <= 500 else {
            throw HelperError.configuration("bunnyHop.startDelayMs должна быть от 0 до 500")
        }
        guard copy.bunnyHop.pulseIntervalTicks >= 1, copy.bunnyHop.pulseIntervalTicks <= 8 else {
            throw HelperError.configuration("bunnyHop.pulseIntervalTicks должен быть от 1 до 8")
        }
        guard copy.feedback.typeDelayMs >= 0, copy.feedback.typeDelayMs <= 100 else {
            throw HelperError.configuration("feedback.typeDelayMs должна быть от 0 до 100")
        }
        guard copy.feedback.closeConsoleAfterMs >= 200, copy.feedback.closeConsoleAfterMs <= 5000 else {
            throw HelperError.configuration("feedback.closeConsoleAfterMs должна быть от 200 до 5000")
        }
        guard copy.focus.pollIntervalMs >= 100, copy.focus.pollIntervalMs <= 5000 else {
            throw HelperError.configuration("focus.pollIntervalMs должна быть от 100 до 5000")
        }
        guard copy.logging.maxFileBytes >= 64_000 else {
            throw HelperError.configuration("logging.maxFileBytes должен быть не меньше 64000")
        }
        _ = try HotkeyParser.parseAll(copy.hotkeys)
        copy.recoil.weapon = copy.recoil.weapon.lowercased()
        return copy
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func jsonString() throws -> String {
        String(decoding: try jsonData(), as: UTF8.self) + "\n"
    }
}

public final class ConfigStore {
    public let url: URL

    public init(url: URL = HelperPaths.defaultConfigURL) {
        self.url = url
    }

    public static func resolveURL(explicit: String?) -> URL {
        if let explicit, !explicit.isEmpty {
            return HelperPaths.url(from: explicit)
        }
        if let environment = ProcessInfo.processInfo.environment["CSGO_HELPER_CONFIG"], !environment.isEmpty {
            return HelperPaths.url(from: environment)
        }
        return HelperPaths.defaultConfigURL
    }

    /// Загрузить конфигурацию, создав файл по умолчанию, если его нет.
    /// Возвращает признак создания файла, чтобы CLI мог сообщить об этом.
    public func loadOrCreate() throws -> (config: HelperConfig, created: Bool) {
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            do {
                let decoded = try JSONDecoder().decode(HelperConfig.self, from: data)
                return (try decoded.validated(), false)
            } catch let error as HelperError {
                throw error
            } catch {
                throw HelperError.configuration("не удалось прочитать \(url.path): \(error.localizedDescription)")
            }
        }
        let config = try HelperConfig().validated()
        try save(config)
        return (config, true)
    }

    public func save(_ config: HelperConfig) throws {
        let validated = try config.validated()
        try AtomicFile.write(try validated.jsonData(), to: url)
    }
}
