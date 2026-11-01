import Foundation

public struct Diagnostic: Sendable, Equatable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }
    public var severity: Severity
    public var file: String
    public var line: Int?
    public var message: String

    public init(_ severity: Severity, _ file: String, line: Int? = nil, _ message: String) {
        self.severity = severity
        self.file = file
        self.line = line
        self.message = message
    }

    public var description: String {
        let name = (file as NSString).lastPathComponent
        return "\(name)\(line.map { ":\($0)" } ?? ""): \(severity.rawValue): \(message)"
    }
}

/// Reads typed values from a TOML table, recording type errors and unknown keys.
final class TableReader {
    let table: TOMLTable
    let file: String
    let prefix: String
    private(set) var used: Set<String> = []
    var diagnostics: [Diagnostic] = []

    init(_ table: TOMLTable, file: String, prefix: String = "") {
        self.table = table
        self.file = file
        self.prefix = prefix
    }

    func name(_ key: String) -> String { prefix.isEmpty ? key : "\(prefix).\(key)" }

    func typeError(_ key: String, _ expected: String) {
        let found = table[key]?.typeName ?? "nothing"
        diagnostics.append(Diagnostic(.error, file, line: table.line(of: key), "'\(name(key))' must be \(expected), found \(found)"))
    }

    func error(_ key: String, _ message: String) {
        diagnostics.append(Diagnostic(.error, file, line: table.line(of: key), "'\(name(key))': \(message)"))
    }

    func raw(_ key: String) -> TOMLValue? {
        used.insert(key)
        return table[key]
    }

    func string(_ key: String) -> String? {
        guard let v = raw(key) else { return nil }
        guard let s = v.string else { typeError(key, "a string"); return nil }
        return s
    }

    func bool(_ key: String) -> Bool? {
        guard let v = raw(key) else { return nil }
        guard let b = v.bool else { typeError(key, "true or false"); return nil }
        return b
    }

    func int(_ key: String, in range: ClosedRange<Int>? = nil) -> Int? {
        guard let v = raw(key) else { return nil }
        guard let n = v.int else { typeError(key, "an integer"); return nil }
        if let range, !range.contains(n) { error(key, "must be between \(range.lowerBound) and \(range.upperBound)"); return nil }
        return n
    }

    func double(_ key: String, in range: ClosedRange<Double>? = nil) -> Double? {
        guard let v = raw(key) else { return nil }
        guard let d = v.double else { typeError(key, "a number"); return nil }
        if let range, !range.contains(d) { error(key, "must be between \(range.lowerBound) and \(range.upperBound)"); return nil }
        return d
    }

    /// Accepts a single string or an array of strings.
    func strings(_ key: String) -> [String]? {
        guard let v = raw(key) else { return nil }
        if let s = v.string { return [s] }
        guard let a = v.array, a.allSatisfy({ $0.string != nil }) else { typeError(key, "a string or an array of strings"); return nil }
        return a.map { $0.string! }
    }

    func table(_ key: String) -> TOMLTable? {
        guard let v = raw(key) else { return nil }
        guard let t = v.table else { typeError(key, "a table"); return nil }
        return t
    }

    func tables(_ key: String) -> [TOMLTable]? {
        guard let v = raw(key) else { return nil }
        if let t = v.table { return [t] }
        guard let a = v.array, a.allSatisfy({ $0.table != nil }) else { typeError(key, "an array of tables ([[\(name(key))]])"); return nil }
        return a.map { $0.table! }
    }

    func oneOf(_ key: String, _ options: [String]) -> String? {
        guard let s = string(key) else { return nil }
        guard options.contains(s) else { error(key, "must be one of \(options.map { "\"\($0)\"" }.joined(separator: ", ")), found \"\(s)\""); return nil }
        return s
    }

    /// Warns about keys nobody read: usually typos.
    func finish() -> [Diagnostic] {
        for key in table.keys where !used.contains(key) {
            diagnostics.append(Diagnostic(.warning, file, line: table.line(of: key), "unknown key '\(name(key))'"))
        }
        return diagnostics
    }
}

public enum DisplayTarget: String, Sendable, CaseIterable {
    /// The screen holding the frontmost app's focused window.
    case active
    /// The screen under the mouse pointer.
    case mouse
    /// The screen with the menu bar.
    case primary
}

public struct AppConfig: Sendable, Equatable {
    public var theme = "kadomo-dark"
    public var hotkey = "option+space"
    public var launchAtLogin = true
    public var display = DisplayTarget.active
    public var closeOnBlur = true
    public var escapeNavigatesBack = true
    public var backspaceNavigatesBack = true
    public var hoverSelects = false
    public var showFavoritesOnHome = true
    public var recentOnHome = 0
    public var maxResults = 40
    public var searchSubtitles = true
    public var debugLog = false
    /// Query prefix → category id. `@fire` searches Apps only.
    public var prefixes: [String: String] = ["@": Categories.apps, "!": Categories.system]
    public var keys: [KeyCommand: [String]] = KeyCommand.defaults
    /// Extra search term → item id.
    public var aliases: [String: String] = [:]
    public var favorites: [String] = []
    public var hidden: [String] = []
    public var appDirectories: [String] = AppConfig.defaultAppDirectories
    public var appExclude: [String] = []
    public var commandDirectories: [String] = []
    public var commands: [TOMLTable] = []
    public var categories: [TOMLTable] = []
    public var kadomo = KadomoIntegration()
    /// The optional Omarchy theme integration (`[omarchy] enabled`). Off removes
    /// its menu, discovery, and installs; Kadomo's own themes never depend on it.
    public var omarchyEnabled = true
    /// An Omarchy theme also styles every app and the wallpaper through the
    /// Kadomo theme manager, when it is installed (`[omarchy] desktop`).
    public var omarchyDesktop = true
    public var windowManager = "auto"

    public init() {}

    public static let defaultAppDirectories = [
        "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
        "~/Applications", "/System/Library/CoreServices/Applications",
    ]
}

/// Optional hooks into the wider Kadomo desktop. Every path may be absent.
public struct KadomoIntegration: Sendable, Equatable {
    /// "auto" uses Kadomo files when they exist, "off" ignores them.
    public var mode = "auto"
    /// Kadomo's per-app theme file for the current desktop theme. Used when `theme = "kadomo"`.
    public var themeFile = "~/.config/kadomo/current/theme/kadomo-menu.toml"
    /// Commands and categories Kadomo registers.
    public var commandsDirectory = "~/.config/kadomo/menu/commands"
    public init() {}
}

public enum ConfigLoader {
    public static func parse(_ text: String, file: String) -> (AppConfig, [Diagnostic]) {
        var config = AppConfig()
        let table: TOMLTable
        do {
            table = try TOML.parse(text)
        } catch {
            return (config, [Diagnostic(.error, file, line: error.line, error.message)])
        }
        let r = TableReader(table, file: file)
        var extra: [Diagnostic] = []

        if let v = r.string("theme") { config.theme = v }
        if let v = r.string("hotkey") {
            if KeyChord.parse(v) == nil { r.error("hotkey", "not a key chord like \"option+space\"") } else { config.hotkey = v }
        }
        if let v = r.bool("launch_at_login") { config.launchAtLogin = v }
        if let v = r.oneOf("display", DisplayTarget.allCases.map(\.rawValue)) { config.display = DisplayTarget(rawValue: v)! }
        if let v = r.bool("close_on_blur") { config.closeOnBlur = v }
        if let v = r.bool("escape_navigates_back") { config.escapeNavigatesBack = v }
        if let v = r.bool("backspace_navigates_back") { config.backspaceNavigatesBack = v }
        if let v = r.bool("hover_selects") { config.hoverSelects = v }
        if let v = r.bool("show_favorites") { config.showFavoritesOnHome = v }
        if let v = r.int("show_recent", in: 0...5) { config.recentOnHome = v }
        if let v = r.bool("debug_log") { config.debugLog = v }
        if let v = r.strings("favorites") { config.favorites = v }
        if let v = r.strings("hidden") { config.hidden = v }
        if let v = r.oneOf("window_manager", ["auto", "yabai", "off"]) { config.windowManager = v }

        if let t = r.table("search") {
            let s = TableReader(t, file: file, prefix: "search")
            if let v = s.int("max_results", in: 5...500) { config.maxResults = v }
            if let v = s.bool("subtitles") { config.searchSubtitles = v }
            if let p = s.table("prefixes") {
                var map: [String: String] = [:]
                for key in p.keys {
                    if let id = p[key]?.string { map[key] = id } else {
                        extra.append(Diagnostic(.error, file, line: p.line(of: key), "'search.prefixes.\(key)' must be a category id string"))
                    }
                }
                config.prefixes = map
            }
            extra += s.finish()
        }

        if let t = r.table("keys") {
            let k = TableReader(t, file: file, prefix: "keys")
            for command in KeyCommand.allCases {
                guard let list = k.strings(command.rawValue) else { continue }
                let bad = list.filter { KeyChord.parse($0) == nil }
                if bad.isEmpty { config.keys[command] = list } else { k.error(command.rawValue, "invalid key chord \(bad.map { "\"\($0)\"" }.joined(separator: ", "))") }
            }
            extra += k.finish()
        }

        if let t = r.table("aliases") {
            for key in t.keys {
                if let id = t[key]?.string { config.aliases[key] = id } else {
                    extra.append(Diagnostic(.error, file, line: t.line(of: key), "'aliases.\(key)' must be an item id string"))
                }
            }
        }

        if let t = r.table("apps") {
            let a = TableReader(t, file: file, prefix: "apps")
            if let v = a.strings("directories") { config.appDirectories = v }
            if let v = a.strings("extra_directories") { config.appDirectories += v }
            if let v = a.strings("exclude") { config.appExclude = v }
            extra += a.finish()
        }

        if let t = r.table("kadomo") {
            let k = TableReader(t, file: file, prefix: "kadomo")
            if let v = k.oneOf("mode", ["auto", "off"]) { config.kadomo.mode = v }
            if let v = k.string("theme_file") { config.kadomo.themeFile = v }
            if let v = k.string("commands_directory") { config.kadomo.commandsDirectory = v }
            extra += k.finish()
        }

        if let t = r.table("omarchy") {
            let o = TableReader(t, file: file, prefix: "omarchy")
            if let v = o.bool("enabled") { config.omarchyEnabled = v }
            if let v = o.bool("desktop") { config.omarchyDesktop = v }
            extra += o.finish()
        }

        if let v = r.strings("command_directories") { config.commandDirectories = v }
        if let v = r.tables("command") { config.commands = v }
        if let v = r.tables("category") { config.categories = v }

        return (config, r.finish() + extra)
    }
}

public enum Paths {
    /// `~/.config/kadomo-menu`, or `$KADOMO_MENU_CONFIG_DIR`, or `$XDG_CONFIG_HOME/kadomo-menu`.
    public static var configDirectory: String {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["KADOMO_MENU_CONFIG_DIR"], !dir.isEmpty { return expand(dir) }
        if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty { return expand(xdg) + "/kadomo-menu" }
        return NSHomeDirectory() + "/.config/kadomo-menu"
    }

    public static var configFile: String { configDirectory + "/config.toml" }
    public static var themesDirectory: String { configDirectory + "/themes" }
    public static var commandsDirectory: String { configDirectory + "/commands" }

    /// Usage history, the socket, and logs. `$KADOMO_MENU_STATE_DIR` overrides.
    public static var stateDirectory: String {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["KADOMO_MENU_STATE_DIR"], !dir.isEmpty { return expand(dir) }
        return NSHomeDirectory() + "/Library/Application Support/kadomo-menu"
    }

    public static var socket: String {
        if let s = ProcessInfo.processInfo.environment["KADOMO_MENU_SOCKET"], !s.isEmpty { return expand(s) }
        return stateDirectory + "/menu.sock"
    }

    public static var usageFile: String { stateDirectory + "/usage.json" }

    /// Expands a leading `~` or `~/`. Nothing else: no variables, no globbing.
    public static func expand(_ path: String) -> String {
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") { return NSHomeDirectory() + path.dropFirst() }
        return path
    }
}
