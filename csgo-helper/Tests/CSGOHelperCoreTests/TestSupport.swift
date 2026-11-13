import CoreGraphics
import Foundation
@testable import CSGOHelperCore

enum TestPaths {
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // каталог CSGOHelperCoreTests
            .deletingLastPathComponent() // каталог Tests
            .deletingLastPathComponent() // корень пакета csgo-helper
    }

    static var patterns: URL {
        repositoryRoot.appendingPathComponent("Resources/patterns.json")
    }

    static var configExample: URL {
        repositoryRoot.appendingPathComponent("Config/config.example.json")
    }
}

final class RecordingInjector: InputInjecting {
    struct Key: Equatable {
        let code: CGKeyCode
        let down: Bool
        let shift: Bool
    }

    let dryRun = true
    var countsPerDegreeX = 20.0
    var countsPerDegreeY = 20.0
    private(set) var keys: [Key] = []
    private(set) var moves: [(x: Double, y: Double)] = []
    private(set) var typed: [String] = []
    private(set) var unicode: [String] = []
    private(set) var resets = 0

    func resetFractionalRemainder() {
        resets += 1
    }

    func moveMouseByCounts(dx: Double, dy: Double) -> (x: Int, y: Int) {
        moves.append((dx, dy))
        return (Int(dx.rounded()), Int(dy.rounded()))
    }

    func postKey(code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        keys.append(Key(code: code, down: down, shift: flags.contains(.maskShift)))
    }

    func typeText(_ text: String, mode: ConsoleTextMode) {
        typed.append(text)
    }

    func postUnicode(_ text: String) {
        unicode.append(text)
    }

    func reset() {
        keys.removeAll()
        moves.removeAll()
        typed.removeAll()
        unicode.removeAll()
        resets = 0
    }
}

func makePatternStore() throws -> PatternStore {
    try PatternStore(url: TestPaths.patterns)
}
