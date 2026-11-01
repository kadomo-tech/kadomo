import Foundation

public struct RGBA: Sendable, Equatable, Hashable {
    public var r, g, b, a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// `#rgb`, `#rrggbb`, or `#rrggbbaa`.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
        } else {
            self.init(Double((v >> 24) & 0xFF) / 255, Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
        }
    }

    public func with(alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }

    /// WCAG relative luminance.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public static func contrast(_ x: RGBA, _ y: RGBA) -> Double {
        let a = x.luminance, b = y.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// A solid color or a gradient (for borders).
public enum Paint: Sendable, Equatable {
    case solid(RGBA)
    case gradient([RGBA], angle: Double)

    public var first: RGBA {
        switch self {
        case .solid(let c): c
        case .gradient(let cs, _): cs.first ?? RGBA(0, 0, 0, 0)
        }
    }
}

public struct ThemeColors: Sendable, Equatable {
    public var background = RGBA(0, 0, 0)
    public var foreground = RGBA(0.90, 0.90, 0.90)
    public var muted = RGBA(0.55, 0.55, 0.57)
    public var accent = RGBA(0.40, 0.76, 1.0)
    public var selectionBackground = RGBA(0.16, 0.16, 0.17)
    public var selectionForeground = RGBA(0.40, 0.76, 1.0)
    public var border = Paint.gradient([RGBA(0.69, 0.42, 0.96), RGBA(0.36, 0.66, 0.96)], angle: -45)
    public var separator = RGBA(1, 1, 1, 0.08)
    public var shadow = RGBA(0, 0, 0, 0.55)
    public var placeholder = RGBA(0.45, 0.45, 0.47)
    public var caret = RGBA(0.40, 0.76, 1.0)
    public var breadcrumb = RGBA(0.69, 0.42, 0.96)
    public var hint = RGBA(0.45, 0.45, 0.47)
    public var error = RGBA(1.0, 0.42, 0.42)
    public var warning = RGBA(1.0, 0.78, 0.35)
}

public struct ThemeFont: Sendable, Equatable {
    /// "monospace", "system", "rounded", or a font family name. Falls back to the system font.
    public var family = "monospace"
    public var size = 16.0
    public var weight = "regular"
    public var searchFamily: String? = nil
    public var searchSize = 18.0
    public var searchWeight = "regular"
    public var subtitleSize = 12.0
    public var hintSize = 12.0
    /// Draw the selected row's title in this weight.
    public var selectedWeight = "medium"
}

public struct ThemeGeometry: Sendable, Equatable {
    public var width = 600.0
    public var maxRows = 9
    /// Rows the Keybinds reference shows before it scrolls. Its rows are shorter, and the screen height caps it.
    public var keybindRows = 22
    public var rowHeight = 46.0
    public var rowSpacing = 4.0
    public var padding = 20.0
    public var searchHeight = 44.0
    public var gap = 10.0
    public var cornerRadius = 16.0
    public var rowCornerRadius = 8.0
    public var borderWidth = 2.0
    public var iconSize = 18.0
    /// Fraction of the screen height above the panel's top edge (layout "center" and "top").
    public var topOffset = 0.22
    public var rowInset = 24.0
}

public struct ThemeEffects: Sendable, Equatable {
    public var backgroundOpacity = 0.97
    /// "none", "hud", "popover", "menu", "sidebar": an NSVisualEffectView behind the colors.
    public var material = "none"
    public var shadowRadius = 30.0
    /// Resize and fade, in seconds. 0 disables. Reduced Motion always disables.
    public var animationDuration = 0.08
    /// "fill", "bar" (a left accent bar), or "outline".
    public var selectionStyle = "fill"
    public var showIcons = true
    public var showSubtitles = false
    public var showHints = true
    public var showChevrons = true
    public var showBreadcrumb = true
    public var showSeparator = false
    public var showFooter = false
    /// "Go…" in the reference design.
    public var placeholder = "Go…"
    /// "auto" (app icons for apps, SF Symbols for everything else), "symbols" (monochrome symbols only), "none".
    public var iconStyle = "auto"
}

public struct Theme: Sendable, Equatable {
    public var id = "kadomo-dark"
    public var name = "Kadomo Dark"
    /// "dark", "light", or "auto" (follow macOS; uses `[colors.light]` in light mode).
    public var appearance = "dark"
    /// "center" (floating palette), "top" (top-aligned), "compact" (narrow menu).
    public var layout = "center"
    public var colors = ThemeColors()
    public var lightColors: ThemeColors? = nil
    public var font = ThemeFont()
    public var geometry = ThemeGeometry()
    public var effects = ThemeEffects()

    public init() {}

    public func colors(dark: Bool) -> ThemeColors {
        if appearance == "auto", !dark, let light = lightColors { return light }
        return colors
    }
}

public struct ThemeSource: Sendable, Equatable {
    public var id: String
    public var text: String
    public var file: String
    public var builtin: Bool

    public init(id: String, text: String, file: String, builtin: Bool) {
        self.id = id; self.text = text; self.file = file; self.builtin = builtin
    }
}

public enum ThemeLoader {
    static let weights = ["ultralight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"]
    static let materials = ["none", "hud", "popover", "menu", "sidebar", "under-window"]

    /// Resolves `id` and its `extends` chain. Returns nil and errors when any
    /// layer is invalid, so the caller can keep the last valid theme.
    public static func resolve(_ id: String, sources: [String: ThemeSource]) -> (Theme?, [Diagnostic]) {
        var chain: [ThemeSource] = []
        var current: String? = id
        var visited = Set<String>()
        var tables: [String: TOMLTable] = [:]
        var diagnostics: [Diagnostic] = []

        while let name = current {
            guard let source = sources[name] else {
                let known = sources.keys.sorted().joined(separator: ", ")
                diagnostics.append(Diagnostic(.error, chain.last?.file ?? "config.toml", "unknown theme '\(name)'. Available: \(known)"))
                return (nil, diagnostics)
            }
            guard !visited.contains(name), visited.count < 8 else {
                diagnostics.append(Diagnostic(.error, source.file, "theme inheritance loops back to '\(name)'"))
                return (nil, diagnostics)
            }
            visited.insert(name)
            let table: TOMLTable
            do { table = try TOML.parse(source.text) } catch {
                diagnostics.append(Diagnostic(.error, source.file, line: error.line, error.message))
                return (nil, diagnostics)
            }
            tables[name] = table
            chain.append(source)
            current = table["extends"]?.string
        }

        var theme = Theme()
        for source in chain.reversed() {
            let errors = apply(tables[source.id]!, to: &theme, file: source.file)
            diagnostics += errors
        }
        theme.id = id
        if diagnostics.contains(where: { $0.severity == .error }) { return (nil, diagnostics) }
        return (theme, diagnostics)
    }

    /// Applies one theme file's tokens on top of `theme`.
    static func apply(_ table: TOMLTable, to theme: inout Theme, file: String) -> [Diagnostic] {
        let r = TableReader(table, file: file)
        var out: [Diagnostic] = []
        _ = r.string("extends")
        _ = r.string("description")
        _ = r.string("author")
        if let v = r.string("name") { theme.name = v }
        if let v = r.oneOf("appearance", ["dark", "light", "auto"]) { theme.appearance = v }
        if let v = r.oneOf("layout", ["center", "top", "compact"]) { theme.layout = v }

        if let t = r.table("colors") {
            let c = TableReader(t, file: file, prefix: "colors")
            applyColors(c, to: &theme.colors)
            if let light = c.table("light") {
                var lc = theme.lightColors ?? theme.colors
                let l = TableReader(light, file: file, prefix: "colors.light")
                applyColors(l, to: &lc)
                out += l.finish()
                theme.lightColors = lc
            }
            out += c.finish()
        }
        if let t = r.table("font") {
            let f = TableReader(t, file: file, prefix: "font")
            if let v = f.string("family") { theme.font.family = v }
            if let v = f.double("size", in: 8...40) { theme.font.size = v }
            if let v = f.oneOf("weight", weights) { theme.font.weight = v }
            if let v = f.string("search_family") { theme.font.searchFamily = v }
            if let v = f.double("search_size", in: 8...48) { theme.font.searchSize = v }
            if let v = f.oneOf("search_weight", weights) { theme.font.searchWeight = v }
            if let v = f.double("subtitle_size", in: 7...32) { theme.font.subtitleSize = v }
            if let v = f.double("hint_size", in: 7...32) { theme.font.hintSize = v }
            if let v = f.oneOf("selected_weight", weights) { theme.font.selectedWeight = v }
            out += f.finish()
        }
        if let t = r.table("geometry") {
            let g = TableReader(t, file: file, prefix: "geometry")
            if let v = g.double("width", in: 240...1600) { theme.geometry.width = v }
            if let v = g.int("max_rows", in: 1...30) { theme.geometry.maxRows = v }
            if let v = g.int("keybind_rows", in: 1...60) { theme.geometry.keybindRows = v }
            if let v = g.double("row_height", in: 16...120) { theme.geometry.rowHeight = v }
            if let v = g.double("row_spacing", in: 0...24) { theme.geometry.rowSpacing = v }
            if let v = g.double("padding", in: 0...64) { theme.geometry.padding = v }
            if let v = g.double("search_height", in: 20...120) { theme.geometry.searchHeight = v }
            if let v = g.double("gap", in: 0...64) { theme.geometry.gap = v }
            if let v = g.double("corner_radius", in: 0...64) { theme.geometry.cornerRadius = v }
            if let v = g.double("row_corner_radius", in: 0...32) { theme.geometry.rowCornerRadius = v }
            if let v = g.double("border_width", in: 0...8) { theme.geometry.borderWidth = v }
            if let v = g.double("icon_size", in: 0...64) { theme.geometry.iconSize = v }
            if let v = g.double("top_offset", in: 0...0.8) { theme.geometry.topOffset = v }
            if let v = g.double("row_inset", in: 0...64) { theme.geometry.rowInset = v }
            out += g.finish()
        }
        if let t = r.table("effects") {
            let e = TableReader(t, file: file, prefix: "effects")
            if let v = e.double("background_opacity", in: 0...1) { theme.effects.backgroundOpacity = v }
            if let v = e.oneOf("material", materials) { theme.effects.material = v }
            if let v = e.double("shadow_radius", in: 0...80) { theme.effects.shadowRadius = v }
            if let v = e.double("animation_duration", in: 0...1) { theme.effects.animationDuration = v }
            if let v = e.oneOf("selection_style", ["fill", "bar", "outline"]) { theme.effects.selectionStyle = v }
            if let v = e.bool("show_icons") { theme.effects.showIcons = v }
            if let v = e.bool("show_subtitles") { theme.effects.showSubtitles = v }
            if let v = e.bool("show_hints") { theme.effects.showHints = v }
            if let v = e.bool("show_chevrons") { theme.effects.showChevrons = v }
            if let v = e.bool("show_breadcrumb") { theme.effects.showBreadcrumb = v }
            if let v = e.bool("show_separator") { theme.effects.showSeparator = v }
            if let v = e.bool("show_footer") { theme.effects.showFooter = v }
            if let v = e.string("placeholder") { theme.effects.placeholder = v }
            if let v = e.oneOf("icon_style", ["auto", "symbols", "none"]) { theme.effects.iconStyle = v }
            out += e.finish()
        }
        return r.finish() + out
    }

    static func applyColors(_ c: TableReader, to colors: inout ThemeColors) {
        func color(_ key: String, _ assign: (RGBA) -> Void) {
            guard let s = c.string(key) else { return }
            guard let v = RGBA(hex: s) else { c.error(key, "not a color; use #rgb, #rrggbb, or #rrggbbaa"); return }
            assign(v)
        }
        color("background") { colors.background = $0 }
        color("foreground") { colors.foreground = $0 }
        color("muted") { colors.muted = $0 }
        color("accent") { colors.accent = $0 }
        color("selection_background") { colors.selectionBackground = $0 }
        color("selection_foreground") { colors.selectionForeground = $0 }
        color("separator") { colors.separator = $0 }
        color("shadow") { colors.shadow = $0 }
        color("placeholder") { colors.placeholder = $0 }
        color("caret") { colors.caret = $0 }
        color("breadcrumb") { colors.breadcrumb = $0 }
        color("hint") { colors.hint = $0 }
        color("error") { colors.error = $0 }
        color("warning") { colors.warning = $0 }
        if let v = c.raw("border") {
            if let s = v.string {
                if let rgba = RGBA(hex: s) { colors.border = .solid(rgba) } else { c.error("border", "not a color") }
            } else if let a = v.array {
                let parsed = a.compactMap { $0.string.flatMap(RGBA.init(hex:)) }
                if parsed.count == a.count, parsed.count >= 2 { colors.border = .gradient(parsed, angle: -45) }
                else { c.error("border", "a gradient needs two or more colors like [\"#b06cf4\", \"#5ca8f5\"]") }
            } else {
                c.typeError("border", "a color or an array of colors")
            }
        }
    }
}
