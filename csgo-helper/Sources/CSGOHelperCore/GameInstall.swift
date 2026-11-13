import Foundation

public struct GameInstall {
    public let name: String
    public let directory: URL
    public let vpk: URL?
    public let vpkVersion: Int?
    public let vpkTreeSize: Int?
    public let vpkSize: Int?
    public let isLegacy: Bool

    public var summary: String {
        var parts = [name, directory.path]
        if let vpk {
            parts.append("VPK: \(vpk.path)")
            parts.append("версия \(vpkVersion.map(String.init) ?? "?")")
            parts.append("tree \(vpkTreeSize ?? 0), файл \(vpkSize ?? 0) байт")
        } else {
            parts.append("pak01_dir.vpk не найден")
        }
        return parts.joined(separator: " | ")
    }
}

public enum SteamLocator {
    public static var steamRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Steam", isDirectory: true)
    }

    /// Библиотеки Steam из libraryfolders.vdf плюс библиотека по умолчанию.
    /// Парсер намеренно минимальный и извлекает только значения `"path"`.
    public static func libraryRoots() -> [URL] {
        var roots: [URL] = [steamRoot]
        let vdf = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let text = try? String(contentsOf: vdf, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let parts = line.components(separatedBy: "\"")
                guard parts.count >= 4, parts[1].lowercased() == "path" else { continue }
                let path = parts[3].replacingOccurrences(of: "\\\\", with: "/")
                guard !path.isEmpty else { continue }
                let url = URL(fileURLWithPath: path)
                if !roots.contains(url) { roots.append(url) }
            }
        }
        return roots
    }

    public static func installations() -> [GameInstall] {
        var installs: [GameInstall] = []
        var seen = Set<String>()
        for root in libraryRoots() {
            let common = root.appendingPathComponent("steamapps/common", isDirectory: true)
            let candidates: [(String, String, Bool)] = [
                ("CS:GO legacy", "csgo legacy", true),
                ("Counter-Strike Global Offensive (CS2)", "Counter-Strike Global Offensive", false)
            ]
            for (display, folder, legacy) in candidates {
                let directory = common.appendingPathComponent(folder, isDirectory: true)
                guard FileManager.default.fileExists(atPath: directory.path), !seen.contains(directory.path) else {
                    continue
                }
                seen.insert(directory.path)
                let vpkCandidates = [
                    directory.appendingPathComponent("csgo/pak01_dir.vpk"),
                    directory.appendingPathComponent("game/csgo/pak01_dir.vpk")
                ]
                let vpk = vpkCandidates.first { FileManager.default.fileExists(atPath: $0.path) }
                var version: Int?
                var treeSize: Int?
                var size: Int?
                if let vpk {
                    size = ((try? FileManager.default.attributesOfItem(atPath: vpk.path))?[.size] as? NSNumber)?.intValue
                    if let handle = try? FileHandle(forReadingFrom: vpk) {
                        defer { try? handle.close() }
                        if let data = try? handle.read(upToCount: 12), data.count >= 12 {
                            let signature = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
                            if signature == 0x55AA1234 {
                                version = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) })
                                treeSize = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self) })
                            }
                        }
                    }
                }
                installs.append(GameInstall(
                    name: display, directory: directory, vpk: vpk,
                    vpkVersion: version, vpkTreeSize: treeSize, vpkSize: size, isLegacy: legacy
                ))
            }
        }
        return installs
    }
}
