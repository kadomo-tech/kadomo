import Foundation
import KadomoMenuCore

// Reading Omarchy's own files. Everything Omarchy-specific about the source
// format lives in this module; Kadomo's native themes never load it.

public struct OmarchyFormatError: Error, Sendable, Equatable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Omarchy color values: `#rgb`, `#rrggbb`, `#rrggbbaa`, Hyprland's
/// `rgb(rrggbb)` and `rgba(rrggbbaa)`, and CSS-style `rgba(r, g, b, a)`.
public enum OmarchyColor {
    public static func parse(_ raw: String) -> RGBA? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") { return RGBA(hex: s) }
        for prefix in ["rgba(", "rgb("] where s.hasPrefix(prefix) && s.hasSuffix(")") {
            let body = String(s.dropFirst(prefix.count).dropLast())
            if body.contains(",") {
                let parts = body.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 3 || parts.count == 4 else { return nil }
                let rgb = parts.prefix(3).compactMap { Double($0) }
                guard rgb.count == 3, rgb.allSatisfy({ (0...255).contains($0) }) else { return nil }
                var alpha = 1.0
                if parts.count == 4 {
                    guard let a = Double(parts[3]), (0...1).contains(a) else { return nil }
                    alpha = a
                }
                return RGBA(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, alpha)
            }
            guard body.count == 6 || body.count == 8, body.allSatisfy(\.isHexDigit) else { return nil }
            return RGBA(hex: "#" + body)
        }
        return nil
    }

    /// One color, or Hyprland's gradient form `rgba(..) rgba(..) 45deg`.
    public static func parseList(_ raw: String) -> [RGBA]? {
        if let one = parse(raw) { return [one] }
        var colors: [RGBA] = []
        for token in raw.split(whereSeparator: \.isWhitespace) {
            if token.hasSuffix("deg"), Double(token.dropLast(3)) != nil { continue }
            guard let c = parse(String(token)) else { return nil }
            colors.append(c)
        }
        return colors.isEmpty ? nil : colors
    }
}

/// A theme's `colors.toml`, with legacy names resolved.
public struct OmarchyPalette: Sendable, Equatable {
    /// "dark" or "light" when the file says so.
    public var mode: String?
    public var colors: [String: RGBA] = [:]
    /// Keys holding more than one color (`hyprland_active_border`).
    public var gradients: [String: [RGBA]] = [:]
    public var warnings: [String] = []

    public init(mode: String? = nil, colors: [String: RGBA] = [:]) {
        self.mode = mode
        self.colors = colors
    }

    public subscript(_ key: String) -> RGBA? { colors[key] }

    /// The documented legacy short names. The canonical name wins when both are set.
    public static let legacyAliases: [String: String] = [
        "bg": "background", "dark_bg": "dark_background", "darker_bg": "darker_background",
        "lighter_bg": "lighter_background", "fg": "foreground", "dark_fg": "dark_foreground",
        "light_fg": "light_foreground", "bright_fg": "bright_foreground",
    ]

    public static let maxBytes = 64 * 1024

    public static func parse(_ text: String) throws(OmarchyFormatError) -> OmarchyPalette {
        guard text.utf8.count <= maxBytes else { throw OmarchyFormatError("colors.toml is larger than 64 KB") }
        let table: TOMLTable
        do { table = try TOML.parse(text) } catch {
            throw OmarchyFormatError("colors.toml is not valid TOML (line \(error.line): \(error.message))")
        }
        var palette = OmarchyPalette()
        var legacy: [String: RGBA] = [:]
        for key in table.keys {
            guard let value = table[key] else { continue }
            if key == "mode" {
                if let m = value.string?.lowercased(), m == "dark" || m == "light" { palette.mode = m }
                else { palette.warnings.append("mode must be \"dark\" or \"light\"; ignored") }
                continue
            }
            guard let s = value.string else {
                palette.warnings.append("\(key) is a \(value.typeName), not a color; ignored")
                continue
            }
            if let color = OmarchyColor.parse(s) {
                if let canonical = legacyAliases[key] { legacy[canonical] = color } else { palette.colors[key] = color }
            } else if let list = OmarchyColor.parseList(s), list.count > 1 {
                palette.gradients[key] = list
            } else {
                palette.warnings.append("\(key) = \"\(s.prefix(40))\" is not a color Kadomo reads; ignored")
            }
        }
        for (canonical, color) in legacy where palette.colors[canonical] == nil { palette.colors[canonical] = color }
        return palette
    }
}

/// The launcher-relevant part of a theme's optional `shell.toml`: its
/// `[launcher]` section, else `[menu]`. Values that are references Kadomo cannot
/// resolve (`hyprland.active-border-foreground`, template text) are skipped and
/// the palette fills in.
public struct OmarchyShellStyle: Sendable, Equatable {
    public var section: String?
    public var background: RGBA?
    public var text: RGBA?
    public var border: [RGBA]?
    public var selectedBackground: RGBA?
    public var selectedText: RGBA?
    public var warnings: [String] = []

    public init() {}

    public static let maxBytes = 256 * 1024

    /// Never throws: shell.toml is optional, so any problem only adds a warning.
    public static func parse(_ text: String, palette: OmarchyPalette) -> OmarchyShellStyle {
        var style = OmarchyShellStyle()
        guard text.utf8.count <= maxBytes else { style.warnings.append("shell.toml is larger than 256 KB; ignored"); return style }
        let table: TOMLTable
        do { table = try TOML.parse(text) } catch {
            style.warnings.append("shell.toml is not valid TOML (line \(error.line)); ignored")
            return style
        }
        guard let name = ["launcher", "menu"].first(where: { table[$0]?.table != nil }), let section = table[name]?.table else { return style }
        style.section = name

        func alpha(_ key: String) -> Double? {
            guard let a = section[key]?.double, (0...1).contains(a) else { return nil }
            return a
        }
        func colors(_ key: String) -> [RGBA]? {
            guard let raw = section[key]?.string else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if let list = OmarchyColor.parseList(trimmed) { return list }
            if let named = palette[trimmed] { return [named] }
            style.warnings.append("[\(name)] \(key) = \"\(trimmed.prefix(40))\" is a reference Kadomo does not resolve; using the palette")
            return nil
        }
        func color(_ key: String, alphaKey: String? = nil) -> RGBA? {
            guard var c = colors(key)?.first else { return nil }
            if let alphaKey, let a = alpha(alphaKey) { c = c.with(alpha: c.a * a) }
            return c
        }
        style.background = color("background", alphaKey: "background-alpha")
        style.text = color("text")
        style.border = colors("border")
        style.selectedBackground = color("selected-background", alphaKey: "selected-background-alpha")
        style.selectedText = color("selected-text")
        return style
    }
}

/// Themes from before `colors.toml` carry their palette in `alacritty.toml`.
/// Omarchy (and the Kadomo theme manager) turn it into a colors.toml; this
/// does the same, with the same names. Only colors are read: the rest of the
/// file, which can name a program to run, is never kept.
public enum OmarchyAlacritty {
    public static let maxBytes = 64 * 1024

    public static func colorsTOML(_ text: String) throws(OmarchyFormatError) -> String {
        guard text.utf8.count <= maxBytes else { throw OmarchyFormatError("alacritty.toml is larger than 64 KB") }
        let table: TOMLTable
        do { table = try TOML.parse(text) } catch {
            throw OmarchyFormatError("alacritty.toml is not valid TOML (line \(error.line): \(error.message))")
        }
        guard let colors = table["colors"]?.table else { throw OmarchyFormatError("alacritty.toml has no [colors]") }
        func value(_ section: String, _ key: String) -> String? {
            guard var s = colors[section]?.table?[key]?.string?.lowercased() else { return nil }
            if s.hasPrefix("0x") { s = "#" + s.dropFirst(2) }
            if !s.hasPrefix("#") { s = "#" + s }
            return s.count == 7 && s.dropFirst().allSatisfy(\.isHexDigit) ? s : nil
        }
        var lines = ["# Imported from alacritty.toml by Kadomo."]
        func out(_ key: String, _ section: String, _ name: String) {
            if let v = value(section, name) { lines.append("\(key) = \"\(v)\"") }
        }
        out("background", "primary", "background")
        out("foreground", "primary", "foreground")
        out("bright_foreground", "primary", "bright_foreground")
        out("cursor", "cursor", "cursor")
        out("selection", "selection", "background")
        out("selection_foreground", "selection", "text")
        let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
        for (i, name) in names.enumerated() {
            if name != "black" && name != "white" {
                out(name, "normal", name)
                out("bright_" + name, "bright", name)
            }
            out("color\(i)", "normal", name)
            out("color\(i + 8)", "bright", name)
        }
        out("muted", "bright", "black")
        out("accent", "normal", "blue")
        guard lines.contains(where: { $0.hasPrefix("background =") }), lines.contains(where: { $0.hasPrefix("foreground =") }) else {
            throw OmarchyFormatError("alacritty.toml has no [colors.primary] background and foreground")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
