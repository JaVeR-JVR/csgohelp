import Foundation

public struct PatternPoint: Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

extension PatternPoint: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard container.count == nil || container.count == 2 else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "точка должна быть [x, y]")
        }
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}

public enum PatternQuality: String, Codable {
    case measured
    case heuristic
}

public struct WeaponProfile: Codable, Equatable {
    public let id: String
    public let displayName: String
    public let aliases: [String]
    public let itemDef: Int?
    public let weaponClass: String
    public let fireMode: String
    public let rpm: Int
    public let magazine: Int
    public let reloadMs: Double
    public let pellets: Int
    public let scoped: Bool
    public let recommendedHoldMs: Double
    public let sourcePattern: String?
    public let patternSource: String
    public let quality: PatternQuality
    public let cumulativeDegrees: [PatternPoint]
    public let perShotDegrees: [PatternPoint]

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case aliases
        case itemDef
        case weaponClass = "class"
        case fireMode
        case rpm
        case magazine
        case reloadMs
        case pellets
        case scoped
        case recommendedHoldMs
        case sourcePattern
        case patternSource
        case quality
        case cumulativeDegrees
        case perShotDegrees
    }

    public var isAutomatic: Bool {
        fireMode == "automatic"
    }

    public var shotInterval: Double {
        60.0 / Double(max(rpm, 1))
    }

    public var patternDuration: Double {
        shotInterval * Double(max(cumulativeDegrees.count - 1, 0))
    }

    /// Кумулятивная цель компенсации отдачи на момент времени от первого
    /// выстрела. Первая точка — первый выстрел, всегда ноль. После последней
    /// точки таблицы значение остаётся на конце магазина.
    public func cumulative(at elapsed: Double) -> PatternPoint {
        guard cumulativeDegrees.count > 1 else { return PatternPoint(x: 0, y: 0) }
        let clamped = max(0, elapsed)
        let position = clamped / shotInterval
        let lowerIndex = min(Int(floor(position)), cumulativeDegrees.count - 1)
        let upperIndex = min(lowerIndex + 1, cumulativeDegrees.count - 1)
        guard upperIndex != lowerIndex else { return cumulativeDegrees[lowerIndex] }
        let fraction = position - Double(lowerIndex)
        let lower = cumulativeDegrees[lowerIndex]
        let upper = cumulativeDegrees[upperIndex]
        return PatternPoint(
            x: lower.x + (upper.x - lower.x) * fraction,
            y: lower.y + (upper.y - lower.y) * fraction
        )
    }

    public func perShotIncrement(shotIndex: Int) -> PatternPoint {
        guard !perShotDegrees.isEmpty else { return PatternPoint(x: 0, y: 0) }
        let index = min(max(shotIndex, 0), perShotDegrees.count - 1)
        return perShotDegrees[index]
    }

    public var isMeasured: Bool { quality == .measured }
}

public struct PatternDocument: Codable {
    public let schemaVersion: Int
    public let units: String
    public let degreesPerSourceUnit: Double?
    public let notes: String?
    public let sources: PatternSources?
    public let counts: PatternCounts?
    public let weapons: [WeaponProfile]

    public struct PatternSources: Codable {
        public let measured: SourceInfo?
        public let guide: SourceInfo?
        public let fallback: SourceInfo?
    }

    public struct SourceInfo: Codable {
        public let name: String
        public let url: String?
        public let license: String?
        public let copyright: String?
        public let use: String?
        public let method: String?
    }

    public struct PatternCounts: Codable {
        public let total: Int
        public let measured: Int
        public let heuristic: Int
    }
}

public final class PatternStore {
    public let sourceURL: URL
    public let document: PatternDocument
    public let weapons: [WeaponProfile]
    private let byID: [String: WeaponProfile]
    private let byAlias: [String: WeaponProfile]

    public init(url: URL) throws {
        self.sourceURL = url
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw HelperError.patterns("не удалось прочитать \(url.path): \(error.localizedDescription)")
        }
        let document: PatternDocument
        do {
            document = try JSONDecoder().decode(PatternDocument.self, from: data)
        } catch {
            throw HelperError.patterns("некорректный JSON \(url.path): \(error.localizedDescription)")
        }
        guard document.schemaVersion == 1 else {
            throw HelperError.patterns("поддерживается schemaVersion=1, получено \(document.schemaVersion)")
        }
        guard !document.weapons.isEmpty else {
            throw HelperError.patterns("в файле нет ни одного оружия")
        }
        var ids: [String: WeaponProfile] = [:]
        var aliases: [String: WeaponProfile] = [:]
        for weapon in document.weapons {
            if ids[weapon.id] != nil {
                throw HelperError.patterns("дублирующийся id оружия: \(weapon.id)")
            }
            guard weapon.rpm > 0 else {
                throw HelperError.patterns("\(weapon.id): rpm должен быть больше 0")
            }
            guard weapon.magazine > 0 else {
                throw HelperError.patterns("\(weapon.id): magazine должен быть больше 0")
            }
            guard weapon.cumulativeDegrees.count >= 2 else {
                throw HelperError.patterns("\(weapon.id): нужно минимум две точки паттерна")
            }
            guard let first = weapon.cumulativeDegrees.first, first.x == 0, first.y == 0 else {
                throw HelperError.patterns("\(weapon.id): первая точка должна быть [0, 0]")
            }
            guard weapon.perShotDegrees.count == weapon.cumulativeDegrees.count - 1 else {
                throw HelperError.patterns("\(weapon.id): perShotDegrees должен содержать на одну точку меньше")
            }
            guard weapon.cumulativeDegrees.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                throw HelperError.patterns("\(weapon.id): NaN/Infinity в паттерне")
            }
            ids[weapon.id] = weapon
            for alias in weapon.aliases {
                aliases[alias.lowercased()] = weapon
            }
        }
        self.document = document
        self.weapons = document.weapons
        self.byID = ids
        self.byAlias = aliases
    }

    public func weapon(id: String) -> WeaponProfile? {
        let normalized = id.lowercased()
        return byID[normalized] ?? byAlias[normalized] ?? byAlias["weapon_" + normalized]
    }

    public func next(after id: String) -> WeaponProfile {
        guard let index = weapons.firstIndex(where: { $0.id == id }) else { return weapons[0] }
        return weapons[(index + 1) % weapons.count]
    }

    public func previous(before id: String) -> WeaponProfile {
        guard let index = weapons.firstIndex(where: { $0.id == id }) else { return weapons[0] }
        return weapons[(index - 1 + weapons.count) % weapons.count]
    }

    public var measuredCount: Int { weapons.filter(\.isMeasured).count }
    public var heuristicCount: Int { weapons.count - measuredCount }

    public static func defaultSearchPaths(explicit: String?) -> [URL] {
        if let explicit, !explicit.isEmpty {
            return [HelperPaths.url(from: explicit)]
        }
        if let environment = ProcessInfo.processInfo.environment["CSGO_HELPER_PATTERNS"], !environment.isEmpty {
            return [HelperPaths.url(from: environment)]
        }
        var candidates: [URL] = []
        if let resource = Bundle.main.resourceURL {
            candidates.append(resource.appendingPathComponent("patterns.json"))
        }
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/patterns.json"))
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("patterns.json"))
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("Resources/patterns.json"))
        candidates.append(cwd.appendingPathComponent("csgo-helper/Resources/patterns.json"))
        // Запасной путь для отладки/тестов: исходник лежит рядом с каталогом
        // Resources пакета. В собранном приложении этот путь безвреден.
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        candidates.append(sourceRoot.appendingPathComponent("Resources/patterns.json"))
        return candidates
    }

    public static func locate(explicit: String?) -> URL? {
        let candidates = defaultSearchPaths(explicit: explicit)
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func load(explicit: String?) throws -> PatternStore {
        let candidates = defaultSearchPaths(explicit: explicit)
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw HelperError.patterns(
                "patterns.json не найден. Искали: " + candidates.map(\.path).joined(separator: ", ")
            )
        }
        return try PatternStore(url: url)
    }

    public func tableSummary() -> String {
        let measured = weapons.filter(\.isMeasured)
            .map { "\($0.id) (\($0.cumulativeDegrees.count) выстр.)" }
            .joined(separator: ", ")
        return "измерено: \(measuredCount) [\(measured)], эвристика: \(heuristicCount)"
    }
}
