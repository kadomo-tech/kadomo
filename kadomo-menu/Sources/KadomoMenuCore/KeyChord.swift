import Foundation

/// A key plus modifiers, written like `cmd+shift+k`, `option+space`, `ctrl+n`.
public struct KeyChord: Hashable, Sendable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let control = Modifiers(rawValue: 4)
        public static let shift = Modifiers(rawValue: 8)
    }

    public var modifiers: Modifiers
    /// Lowercase key name: a single character, or one of `KeyChord.namedKeys`.
    public var key: String

    public init(_ key: String, _ modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let namedKeys: Set<String> = [
        "space", "enter", "tab", "escape", "backspace", "delete", "up", "down", "left", "right",
        "home", "end", "pageup", "pagedown",
        "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
    ]

    static let keyAliases: [String: String] = [
        "return": "enter", "esc": "escape", "bksp": "backspace", "del": "delete", "pgup": "pageup", "pgdn": "pagedown",
        "arrowup": "up", "arrowdown": "down", "arrowleft": "left", "arrowright": "right",
    ]

    public static func parse(_ text: String) -> KeyChord? {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, !last.isEmpty else {
            // "cmd++" means the plus key.
            if text.hasSuffix("++") { return parse(String(text.dropLast(2)) + "+plus").map { KeyChord("+", $0.modifiers) } }
            return nil
        }
        var mods: Modifiers = []
        for p in parts.dropLast() {
            switch p {
            case "cmd", "command", "super", "meta": mods.insert(.command)
            case "opt", "option", "alt": mods.insert(.option)
            case "ctrl", "control": mods.insert(.control)
            case "shift": mods.insert(.shift)
            default: return nil
            }
        }
        let key = keyAliases[last] ?? last
        guard key.count == 1 || namedKeys.contains(key) || key == "plus" else { return nil }
        return KeyChord(key == "plus" ? "+" : key, mods)
    }

    public var description: String {
        var s = ""
        if modifiers.contains(.control) { s += "ctrl+" }
        if modifiers.contains(.option) { s += "option+" }
        if modifiers.contains(.shift) { s += "shift+" }
        if modifiers.contains(.command) { s += "cmd+" }
        return s + key
    }

    /// Compact Mac-style glyphs for hints: ⌃⌥⇧⌘ then the key.
    public var symbol: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        let k: String = switch key {
        case "enter": "↩"
        case "tab": "⇥"
        case "escape": "esc"
        case "backspace": "⌫"
        case "delete": "⌦"
        case "space": "Space"
        case "up": "↑"
        case "down": "↓"
        case "left": "←"
        case "right": "→"
        case "pageup": "⇞"
        case "pagedown": "⇟"
        default: key.uppercased()
        }
        return s + k
    }
}

/// Launcher commands that keys can be bound to.
public enum KeyCommand: String, CaseIterable, Sendable {
    case up, down, first, last, pageUp = "page_up", pageDown = "page_down"
    case enter, alternate, actions, back, forward, close, clear, favorite

    public var summary: String {
        switch self {
        case .up: "Previous result"
        case .down: "Next result"
        case .first: "First result"
        case .last: "Last result"
        case .pageUp: "Page up"
        case .pageDown: "Page down"
        case .enter: "Run, or open category"
        case .alternate: "Alternate action"
        case .actions: "Show actions"
        case .back: "Back to parent category"
        case .forward: "Open category"
        case .close: "Clear, back, or close"
        case .clear: "Clear search"
        case .favorite: "Toggle favorite"
        }
    }

    public static let defaults: [KeyCommand: [String]] = [
        .up: ["up", "ctrl+p"],
        .down: ["down", "ctrl+n"],
        .first: ["cmd+up", "home"],
        .last: ["cmd+down", "end"],
        .pageUp: ["pageup"],
        .pageDown: ["pagedown"],
        .enter: ["enter"],
        .alternate: ["cmd+enter"],
        .actions: ["tab", "shift+tab", "cmd+k"],
        .back: ["left", "cmd+["],
        .forward: ["right", "cmd+]"],
        .close: ["escape"],
        .clear: ["cmd+backspace"],
        .favorite: ["cmd+d"],
    ]
}

/// Resolved chord → command lookup.
public struct KeyMap: Sendable, Equatable {
    public private(set) var bindings: [KeyChord: KeyCommand] = [:]
    public private(set) var chords: [KeyCommand: [KeyChord]] = [:]

    public init(_ config: [KeyCommand: [String]] = KeyCommand.defaults) {
        for command in KeyCommand.allCases {
            let list = (config[command] ?? KeyCommand.defaults[command] ?? []).compactMap(KeyChord.parse)
            chords[command] = list
            for c in list { bindings[c] = command }
        }
    }

    public func command(for chord: KeyChord) -> KeyCommand? { bindings[chord] }
    public func primary(_ command: KeyCommand) -> KeyChord? { chords[command]?.first }
}
