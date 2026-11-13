import CoreGraphics
import Foundation

// MARK: - Аппаратные коды клавиш (раскладка US, виртуальные коды Carbon)

public enum KeyCode {
    public static let a: CGKeyCode = 0
    public static let s: CGKeyCode = 1
    public static let d: CGKeyCode = 2
    public static let f: CGKeyCode = 3
    public static let h: CGKeyCode = 4
    public static let g: CGKeyCode = 5
    public static let z: CGKeyCode = 6
    public static let x: CGKeyCode = 7
    public static let c: CGKeyCode = 8
    public static let v: CGKeyCode = 9
    public static let b: CGKeyCode = 11
    public static let q: CGKeyCode = 12
    public static let w: CGKeyCode = 13
    public static let e: CGKeyCode = 14
    public static let r: CGKeyCode = 15
    public static let y: CGKeyCode = 16
    public static let t: CGKeyCode = 17
    public static let one: CGKeyCode = 18
    public static let two: CGKeyCode = 19
    public static let three: CGKeyCode = 20
    public static let four: CGKeyCode = 21
    public static let six: CGKeyCode = 22
    public static let five: CGKeyCode = 23
    public static let equal: CGKeyCode = 24
    public static let nine: CGKeyCode = 25
    public static let seven: CGKeyCode = 26
    public static let minus: CGKeyCode = 27
    public static let eight: CGKeyCode = 28
    public static let zero: CGKeyCode = 29
    public static let rightBracket: CGKeyCode = 30
    public static let o: CGKeyCode = 31
    public static let u: CGKeyCode = 32
    public static let leftBracket: CGKeyCode = 33
    public static let i: CGKeyCode = 34
    public static let p: CGKeyCode = 35
    public static let returnKey: CGKeyCode = 36
    public static let l: CGKeyCode = 37
    public static let j: CGKeyCode = 38
    public static let quote: CGKeyCode = 39
    public static let k: CGKeyCode = 40
    public static let semicolon: CGKeyCode = 41
    public static let backslash: CGKeyCode = 42
    public static let comma: CGKeyCode = 43
    public static let slash: CGKeyCode = 44
    public static let n: CGKeyCode = 45
    public static let m: CGKeyCode = 46
    public static let period: CGKeyCode = 47
    public static let tab: CGKeyCode = 48
    public static let space: CGKeyCode = 49
    public static let grave: CGKeyCode = 50
    public static let delete: CGKeyCode = 51
    public static let escape: CGKeyCode = 53
    public static let command: CGKeyCode = 55
    public static let shift: CGKeyCode = 56
    public static let capsLock: CGKeyCode = 57
    public static let option: CGKeyCode = 58
    public static let control: CGKeyCode = 59
    public static let rightShift: CGKeyCode = 60
    public static let rightOption: CGKeyCode = 61
    public static let rightControl: CGKeyCode = 62
    public static let function: CGKeyCode = 63
    public static let f1: CGKeyCode = 122
    public static let f2: CGKeyCode = 120
    public static let f3: CGKeyCode = 99
    public static let f4: CGKeyCode = 118
    public static let f5: CGKeyCode = 96
    public static let f6: CGKeyCode = 97
    public static let f7: CGKeyCode = 98
    public static let f8: CGKeyCode = 100
    public static let f9: CGKeyCode = 101
    public static let f10: CGKeyCode = 109
    public static let f11: CGKeyCode = 103
    public static let f12: CGKeyCode = 111
    public static let leftArrow: CGKeyCode = 123
    public static let rightArrow: CGKeyCode = 124
    public static let downArrow: CGKeyCode = 125
    public static let upArrow: CGKeyCode = 126
    public static let forwardDelete: CGKeyCode = 117
    public static let home: CGKeyCode = 115
    public static let end: CGKeyCode = 119
    public static let pageUp: CGKeyCode = 116
    public static let pageDown: CGKeyCode = 121
}

public struct KeyStroke: Equatable {
    public let keyCode: CGKeyCode
    public let shift: Bool

    public init(_ keyCode: CGKeyCode, shift: Bool = false) {
        self.keyCode = keyCode
        self.shift = shift
    }
}

public enum KeyMap {
    private static let letters: [Character: CGKeyCode] = [
        "a": KeyCode.a, "s": KeyCode.s, "d": KeyCode.d, "f": KeyCode.f,
        "h": KeyCode.h, "g": KeyCode.g, "z": KeyCode.z, "x": KeyCode.x,
        "c": KeyCode.c, "v": KeyCode.v, "b": KeyCode.b, "q": KeyCode.q,
        "w": KeyCode.w, "e": KeyCode.e, "r": KeyCode.r, "y": KeyCode.y,
        "t": KeyCode.t, "o": KeyCode.o, "u": KeyCode.u, "i": KeyCode.i,
        "p": KeyCode.p, "l": KeyCode.l, "j": KeyCode.j, "k": KeyCode.k,
        "n": KeyCode.n, "m": KeyCode.m
    ]

    private static let digits: [Character: CGKeyCode] = [
        "0": KeyCode.zero, "1": KeyCode.one, "2": KeyCode.two,
        "3": KeyCode.three, "4": KeyCode.four, "5": KeyCode.five,
        "6": KeyCode.six, "7": KeyCode.seven, "8": KeyCode.eight,
        "9": KeyCode.nine
    ]

    private static let plainPunctuation: [Character: CGKeyCode] = [
        " ": KeyCode.space, "-": KeyCode.minus, "=": KeyCode.equal,
        "[": KeyCode.leftBracket, "]": KeyCode.rightBracket,
        ";": KeyCode.semicolon, "'": KeyCode.quote, ",": KeyCode.comma,
        ".": KeyCode.period, "/": KeyCode.slash, "\\": KeyCode.backslash,
        "`": KeyCode.grave, "\n": KeyCode.returnKey, "\t": KeyCode.tab
    ]

    private static let shiftedPunctuation: [Character: (CGKeyCode, CGKeyCode)] = [
        "!": (KeyCode.one, KeyCode.shift), "@": (KeyCode.two, KeyCode.shift),
        "#": (KeyCode.three, KeyCode.shift), "$": (KeyCode.four, KeyCode.shift),
        "%": (KeyCode.five, KeyCode.shift), "^": (KeyCode.six, KeyCode.shift),
        "&": (KeyCode.seven, KeyCode.shift), "*": (KeyCode.eight, KeyCode.shift),
        "(": (KeyCode.nine, KeyCode.shift), ")": (KeyCode.zero, KeyCode.shift),
        "_": (KeyCode.minus, KeyCode.shift), "+": (KeyCode.equal, KeyCode.shift),
        "{": (KeyCode.leftBracket, KeyCode.shift), "}": (KeyCode.rightBracket, KeyCode.shift),
        ":": (KeyCode.semicolon, KeyCode.shift), "\"": (KeyCode.quote, KeyCode.shift),
        "<": (KeyCode.comma, KeyCode.shift), ">": (KeyCode.period, KeyCode.shift),
        "?": (KeyCode.slash, KeyCode.shift), "|": (KeyCode.backslash, KeyCode.shift),
        "~": (KeyCode.grave, KeyCode.shift)
    ]

    public static func stroke(for character: Character) -> KeyStroke? {
        if let code = letters[character] {
            return KeyStroke(code)
        }
        if let code = digits[character] {
            return KeyStroke(code)
        }
        if let code = plainPunctuation[character] {
            return KeyStroke(code)
        }
        let upper = Character(String(character).lowercased())
        if let code = letters[upper] {
            return KeyStroke(code, shift: true)
        }
        if let (code, _) = shiftedPunctuation[character] {
            return KeyStroke(code, shift: true)
        }
        return nil
    }

    public static func keyCode(for name: String) -> CGKeyCode? {
        let lower = name.lowercased()
        if lower.count == 1, let character = lower.first, let stroke = stroke(for: character) {
            // Именованные хоткеи используют физическую клавишу без Shift;
            // явный токен "shift+" добавляет модификатор отдельно.
            return stroke.keyCode
        }
        switch lower {
        case "space", "spacebar": return KeyCode.space
        case "return", "enter": return KeyCode.returnKey
        case "escape", "esc": return KeyCode.escape
        case "tab": return KeyCode.tab
        case "delete", "backspace": return KeyCode.delete
        case "forwarddelete": return KeyCode.forwardDelete
        case "left", "leftarrow": return KeyCode.leftArrow
        case "right", "rightarrow": return KeyCode.rightArrow
        case "up", "uparrow": return KeyCode.upArrow
        case "down", "downarrow": return KeyCode.downArrow
        case "home": return KeyCode.home
        case "end": return KeyCode.end
        case "pageup": return KeyCode.pageUp
        case "pagedown": return KeyCode.pageDown
        case "backtick", "grave": return KeyCode.grave
        case "f1": return KeyCode.f1
        case "f2": return KeyCode.f2
        case "f3": return KeyCode.f3
        case "f4": return KeyCode.f4
        case "f5": return KeyCode.f5
        case "f6": return KeyCode.f6
        case "f7": return KeyCode.f7
        case "f8": return KeyCode.f8
        case "f9": return KeyCode.f9
        case "f10": return KeyCode.f10
        case "f11": return KeyCode.f11
        case "f12": return KeyCode.f12
        case "[": return KeyCode.leftBracket
        case "]": return KeyCode.rightBracket
        case "1": return KeyCode.one
        case "2": return KeyCode.two
        case "3": return KeyCode.three
        case "0": return KeyCode.zero
        default: return nil
        }
    }
}

// MARK: - Горячие клавиши

public struct Hotkey: Equatable {
    public let keyCode: CGKeyCode
    public let shift: Bool
    public let control: Bool
    public let option: Bool
    public let command: Bool
    public let source: String

    public init(keyCode: CGKeyCode, shift: Bool = false, control: Bool = false,
                option: Bool = false, command: Bool = false, source: String = "") {
        self.keyCode = keyCode
        self.shift = shift
        self.control = control
        self.option = option
        self.command = command
        self.source = source
    }

    public static func == (lhs: Hotkey, rhs: Hotkey) -> Bool {
        lhs.keyCode == rhs.keyCode
            && lhs.shift == rhs.shift
            && lhs.control == rhs.control
            && lhs.option == rhs.option
            && lhs.command == rhs.command
    }

    public static func parse(_ string: String) throws -> Hotkey {
        let raw = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw HelperError.configuration("пустой хоткей") }
        let tokens = raw.lowercased().split(separator: "+", omittingEmptySubsequences: true).map(String.init)
        guard let keyName = tokens.last, !keyName.isEmpty else {
            throw HelperError.configuration("хоткей \"\(string)\" не содержит клавишу")
        }
        var shift = false
        var control = false
        var option = false
        var command = false
        for modifier in tokens.dropLast() {
            switch modifier {
            case "shift": shift = true
            case "ctrl", "control": control = true
            case "alt", "option", "opt": option = true
            case "cmd", "command", "meta": command = true
            default:
                throw HelperError.configuration("неизвестный модификатор \"\(modifier)\" в хоткее \"\(string)\"")
            }
        }
        guard let keyCode = KeyMap.keyCode(for: keyName) else {
            throw HelperError.configuration("неизвестная клавиша \"\(keyName)\" в хоткее \"\(string)\"")
        }
        guard shift || control || option || command else {
            throw HelperError.configuration("хоткей \"\(string)\" должен содержать хотя бы один модификатор")
        }
        return Hotkey(keyCode: keyCode, shift: shift, control: control, option: option,
                      command: command, source: raw)
    }

    public func matches(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard keyCode == self.keyCode else { return false }
        let shiftDown = flags.contains(.maskShift)
        let controlDown = flags.contains(.maskControl)
        let optionDown = flags.contains(.maskAlternate)
        let commandDown = flags.contains(.maskCommand)
        return shiftDown == shift && controlDown == control && optionDown == option && commandDown == command
    }
}

public enum HotkeyParser {
    public struct Set: Equatable {
        public let toggleAll: Hotkey
        public let recoil: Hotkey
        public let snapTap: Hotkey
        public let bunnyHop: Hotkey
        public let nextWeapon: Hotkey
        public let previousWeapon: Hotkey
        public let echoStatus: Hotkey
    }

    public static func parseAll(_ config: HotkeyConfig) throws -> Set {
        let all = [
            ("toggleAll", config.toggleAll),
            ("recoil", config.recoil),
            ("snapTap", config.snapTap),
            ("bunnyHop", config.bunnyHop),
            ("nextWeapon", config.nextWeapon),
            ("previousWeapon", config.previousWeapon),
            ("echoStatus", config.echoStatus)
        ]
        var parsed: [String: Hotkey] = [:]
        for (name, value) in all {
            let hotkey = try Hotkey.parse(value)
            if let duplicate = parsed.first(where: { $0.value == hotkey }) {
                throw HelperError.configuration("хоткей \(name) совпадает с \(duplicate.key)")
            }
            parsed[name] = hotkey
        }
        return Set(
            toggleAll: parsed["toggleAll"]!,
            recoil: parsed["recoil"]!,
            snapTap: parsed["snapTap"]!,
            bunnyHop: parsed["bunnyHop"]!,
            nextWeapon: parsed["nextWeapon"]!,
            previousWeapon: parsed["previousWeapon"]!,
            echoStatus: parsed["echoStatus"]!
        )
    }
}
