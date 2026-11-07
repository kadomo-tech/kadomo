import Foundation
import KadomoMenuCore

/// Loads config.toml, themes, and command files, and keeps the last valid
/// version of each when a newer edit is broken.
final class ConfigStore {
    private(set) var config = AppConfig()
    private(set) var themeSources = BuiltinThemes.sources
    private(set) var userItems: [Item] = []
    private(set) var diagnostics: [Diagnostic] = []
    private var hasValidConfig = false
    private static let maxThemeFileBytes = 256 * 1024

    var errors: [Diagnostic] { diagnostics.filter { $0.severity == .error } }
    var warnings: [Diagnostic] { diagnostics.filter { $0.severity == .warning } }

    /// Creates the config folder with commented defaults the first time.
    func ensureDefaults() {
        let fm = FileManager.default
        for dir in [Paths.configDirectory, Paths.themesDirectory, Paths.commandsDirectory, Paths.stateDirectory] {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        writeIfMissing(Paths.configFile, DefaultFiles.config)
        writeIfMissing(Paths.commandsDirectory + "/README.md", DefaultFiles.commandsReadme)
        writeIfMissing(Paths.themesDirectory + "/README.md", DefaultFiles.themesReadme)
    }

    private func writeIfMissing(_ path: String, _ text: String) {
        guard !FileManager.default.fileExists(atPath: path) else { return }
        try? text.write(toFile: path, atomically: false, encoding: .utf8)
    }

    /// Directories whose changes should trigger a reload.
    var watchPaths: [String] {
        var paths = [Paths.configDirectory]
        if config.kadomo.mode != "off" {
            paths.append((Paths.expand(config.kadomo.themeFile) as NSString).deletingLastPathComponent)
            paths.append(Paths.expand(config.kadomo.commandsDirectory))
        }
        paths += config.commandDirectories.map(Paths.expand)
        return paths
    }

    func load() {
        var diags: [Diagnostic] = []
        let file = Paths.configFile
        let text = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        let (parsed, configDiags) = ConfigLoader.parse(text, file: file)
        let syntaxBroken = (try? TOML.parse(text)) == nil
        if syntaxBroken && hasValidConfig {
            diags += configDiags.map { var d = $0; d.message += " (keeping the previous configuration)"; return d }
        } else {
            config = parsed
            hasValidConfig = hasValidConfig || !syntaxBroken
            diags += configDiags
        }
        Log.debugEnabled = config.debugLog || ProcessInfo.processInfo.environment["KADOMO_MENU_DEBUG"] == "1"

        // Themes: built-ins, then user files (a user file may replace a built-in), then Kadomo's.
        var themes = BuiltinThemes.sources
        for (path, id) in tomlFiles(in: Paths.themesDirectory) {
            if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                themes[id] = ThemeSource(id: id, text: text, file: path, builtin: false)
            }
        }
        if config.kadomo.mode != "off" {
            let path = Paths.expand(config.kadomo.themeFile)
            // This file can come from a theme someone else wrote.
            var info = stat()
            if stat(path, &info) == 0, info.st_size > Self.maxThemeFileBytes {
                diags.append(Diagnostic(.warning, path, "larger than \(Self.maxThemeFileBytes / 1024) KB; ignored"))
            } else if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                // Kadomo's file inherits from Kadomo Dark unless it says otherwise.
                let body = text.contains("extends") ? text : "extends = \"kadomo-dark\"\n" + text
                themes["kadomo"] = ThemeSource(id: "kadomo", text: body, file: path, builtin: false)
            }
        }
        themeSources = themes

        // Commands: config.toml, the commands folder, extra folders, then Kadomo's.
        var items: [Item] = []
        let (inline, inlineDiags) = UserCommands.parse(commands: config.commands, categories: config.categories, file: file, source: "user")
        items += inline
        diags += inlineDiags
        var dirs: [(String, String)] = [(Paths.commandsDirectory, "user")]
        dirs += config.commandDirectories.map { (Paths.expand($0), "user") }
        if config.kadomo.mode != "off" { dirs.append((Paths.expand(config.kadomo.commandsDirectory), "kadomo")) }
        for (dir, source) in dirs {
            for (path, _) in tomlFiles(in: dir) {
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                let (fileItems, fileDiags) = UserCommands.parseFile(text, file: path, source: source)
                items += fileItems
                diags += fileDiags
            }
        }
        userItems = items
        diagnostics = diags
    }

    func tomlFiles(in dir: String) -> [(String, String)] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".toml") && !$0.hasPrefix(".") }.sorted()
        return names.map { ("\(dir)/\($0)", String($0.dropLast(5))) }
    }

    /// Resolves the configured theme. When it is broken, returns nil and the
    /// errors so the caller keeps showing the last good theme.
    func resolveTheme(_ id: String? = nil) -> (Theme?, [Diagnostic]) {
        let wanted = id ?? config.theme
        if wanted == "kadomo", themeSources["kadomo"] == nil {
            return (ThemeLoader.resolve(BuiltinThemes.defaultID, sources: themeSources).0,
                    [Diagnostic(.warning, Paths.configFile, "theme \"kadomo\" needs \(config.kadomo.themeFile); using kadomo-dark")])
        }
        if themeSources[wanted] == nil, id == nil {
            let fallback = ThemeLoader.resolve(BuiltinThemes.defaultID, sources: themeSources).0
            let known = themeSources.keys.sorted().joined(separator: ", ")
            return (fallback, [Diagnostic(.error, Paths.configFile, "unknown theme '\(config.theme)'. Available: \(known)")])
        }
        return ThemeLoader.resolve(wanted, sources: themeSources)
    }

    /// Persists the theme choice by editing only the `theme =` line of config.toml.
    func setTheme(_ id: String) throws {
        let file = Paths.configFile
        var text = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        let line = "theme = \"\(id)\""
        var lines = text.components(separatedBy: "\n")
        var replaced = false
        // Only top-level keys: stop at the first table header.
        for (i, l) in lines.enumerated() {
            let trimmed = l.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            if trimmed.hasPrefix("theme") && trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces).hasPrefix("=") {
                lines[i] = line
                replaced = true
                break
            }
        }
        if !replaced { lines.insert(line, at: 0) }
        text = lines.joined(separator: "\n")
        // Atomic, so the file watcher never reloads a half-written file. Write
        // through a symlink (a dotfiles checkout, say) instead of replacing it.
        let target = URL(fileURLWithPath: file).resolvingSymlinksInPath()
        try text.write(to: target, atomically: true, encoding: .utf8)
    }

    /// Writes an editable theme that inherits from `id`, and returns its path.
    func customizeTheme(_ id: String, theme: Theme) throws -> (String, String) {
        let newID = id.hasSuffix("-custom") ? id : "\(id)-custom"
        let path = Paths.themesDirectory + "/\(newID).toml"
        if !FileManager.default.fileExists(atPath: path) {
            let text = """
            # A copy of \(theme.name). Uncomment and change any token; saving applies it.
            name = "\(theme.name) Custom"
            extends = "\(id)"

            [colors]
            # accent = "#62c1ff"
            # background = "#000000"
            # selection_background = "#29292c"
            # border = ["#b26cf3", "#5ea8f5"]

            [font]
            # family = "\(theme.font.family)"
            # size = \(theme.font.size)

            [geometry]
            # width = \(Int(theme.geometry.width))
            # row_height = \(Int(theme.geometry.rowHeight))
            # corner_radius = \(Int(theme.geometry.cornerRadius))

            [effects]
            # material = "\(theme.effects.material)"
            # selection_style = "\(theme.effects.selectionStyle)"

            """
            try text.write(toFile: path, atomically: false, encoding: .utf8)
        }
        return (newID, path)
    }
}
