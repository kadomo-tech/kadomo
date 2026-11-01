import Foundation

// The appearance contract between theme providers and the renderer.
//
// Kadomo's native themes (TOML, `ThemeLoader`) resolve straight to a `Theme`
// and never pass through this file's provider machinery. Another provider (the
// optional Omarchy integration) hands the launcher a `ThemeAppearance`: the
// colors and light/dark mode only, laid over the built-in default theme. Fonts,
// geometry, effects, key bindings, and commands stay Kadomo's, so an external
// theme can change how the panel looks and nothing else.
//
// This contract belongs to Kadomo. Providers adapt to it; it never adapts to a
// provider's source format.

extension RGBA {
    /// `#rrggbb`, or `#rrggbbaa` when not opaque.
    public var hexString: String {
        func byte(_ v: Double) -> String { String(format: "%02x", Int((min(max(v, 0), 1) * 255).rounded())) }
        return "#" + byte(r) + byte(g) + byte(b) + (a < 1 ? byte(a) : "")
    }

    /// Rounded to 8 bits per channel: exactly what `hexString` stores.
    public var quantized: RGBA {
        func q(_ v: Double) -> Double { (min(max(v, 0), 1) * 255).rounded() / 255 }
        return RGBA(q(r), q(g), q(b), q(a))
    }

    /// Linear blend toward `other`: 0 is self, 1 is `other`.
    public func mixed(with other: RGBA, _ t: Double) -> RGBA {
        RGBA(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t, a + (other.a - a) * t)
    }

    /// Self, moved toward black or white just far enough to reach `ratio`
    /// contrast against `background` (the WCAG check the theme manager uses).
    public func readable(on background: RGBA, ratio: Double) -> RGBA {
        if RGBA.contrast(self, background) >= ratio { return self }
        let target = background.luminance > 0.4 ? RGBA(0, 0, 0, a) : RGBA(1, 1, 1, a)
        // Checked after rounding to 8 bits, so the stored color passes too.
        var low = 0.0, high = 1.0
        for _ in 0..<20 {
            let mid = (low + high) / 2
            if RGBA.contrast(mixed(with: target, mid).quantized, background) >= ratio { high = mid } else { low = mid }
        }
        return mixed(with: target, high).quantized
    }
}

/// The resolved look a non-native provider gives the launcher. Every color is
/// required: providers derive what their source format leaves out.
public struct ThemeAppearance: Sendable, Equatable, Codable {
    /// Bumped only when the fields below change meaning.
    public static let contractVersion = 1

    public var name: String
    /// "dark" or "light".
    public var appearance: String
    public var background: RGBA
    public var foreground: RGBA
    public var muted: RGBA
    public var accent: RGBA
    public var selectionBackground: RGBA
    public var selectionForeground: RGBA
    /// One color, or two or more for a diagonal gradient.
    public var border: [RGBA]
    public var separator: RGBA
    public var placeholder: RGBA
    public var caret: RGBA
    public var breadcrumb: RGBA
    public var hint: RGBA
    public var error: RGBA
    public var warning: RGBA

    public init(name: String, appearance: String, background: RGBA, foreground: RGBA, muted: RGBA, accent: RGBA,
                selectionBackground: RGBA, selectionForeground: RGBA, border: [RGBA], separator: RGBA,
                placeholder: RGBA, caret: RGBA, breadcrumb: RGBA, hint: RGBA, error: RGBA, warning: RGBA) {
        self.name = name; self.appearance = appearance
        self.background = background; self.foreground = foreground; self.muted = muted; self.accent = accent
        self.selectionBackground = selectionBackground; self.selectionForeground = selectionForeground
        self.border = border; self.separator = separator; self.placeholder = placeholder; self.caret = caret
        self.breadcrumb = breadcrumb; self.hint = hint; self.error = error; self.warning = warning
    }

    /// Every color rounded to what JSON stores, so a cached appearance equals
    /// the one that was validated.
    public var quantized: ThemeAppearance {
        var a = self
        for kp in [\ThemeAppearance.background, \.foreground, \.muted, \.accent, \.selectionBackground, \.selectionForeground,
                   \.separator, \.placeholder, \.caret, \.breadcrumb, \.hint, \.error, \.warning] {
            a[keyPath: kp] = a[keyPath: kp].quantized
        }
        a.border = border.map(\.quantized)
        return a
    }

    /// Problems that would make the panel unreadable or unrenderable.
    public func validate() -> [String] {
        var problems: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { problems.append("no name") }
        if appearance != "dark" && appearance != "light" { problems.append("appearance must be dark or light") }
        if border.isEmpty { problems.append("no border color") }
        let all = [background, foreground, muted, accent, selectionBackground, selectionForeground, separator,
                   placeholder, caret, breadcrumb, hint, error, warning] + border
        if all.contains(where: { ![$0.r, $0.g, $0.b, $0.a].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 } }) {
            problems.append("a color is out of range")
        }
        if RGBA.contrast(foreground, background.with(alpha: 1)) < 3 { problems.append("text does not contrast with the background") }
        if RGBA.contrast(selectionForeground, selectionBackground.with(alpha: 1)) < 2 && RGBA.contrast(selectionForeground, background.with(alpha: 1)) < 3 {
            problems.append("selected text does not contrast with the selection")
        }
        return problems
    }

    /// The renderable theme: `base` (Kadomo's built-in default) with these
    /// colors and this mode. Nothing but colors, name, and mode changes.
    public func theme(id: String, base: Theme) -> Theme {
        var t = base
        t.id = id
        t.name = name
        t.appearance = appearance
        t.lightColors = nil
        var c = t.colors
        c.background = background
        c.foreground = foreground
        c.muted = muted
        c.accent = accent
        c.selectionBackground = selectionBackground
        c.selectionForeground = selectionForeground
        c.border = border.count >= 2 ? .gradient(border, angle: -45) : .solid(border.first ?? accent)
        c.separator = separator
        c.placeholder = placeholder
        c.caret = caret
        c.breadcrumb = breadcrumb
        c.hint = hint
        c.error = error
        c.warning = warning
        t.colors = c
        return t
    }
}

extension RGBA: Codable {
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let v = RGBA(hex: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a color: \(s)"))
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hexString)
    }
}

// MARK: - The one active theme

/// Who supplies the launcher's look. Native Kadomo themes are always available;
/// anything else is an optional integration.
public enum ThemeProviderID: String, Sendable, Codable, CaseIterable {
    case kadomo
    case omarchy
}

public struct ThemeSelection: Sendable, Equatable, Codable {
    public var provider: ThemeProviderID
    public var themeId: String

    public init(provider: ThemeProviderID, themeId: String) {
        self.provider = provider; self.themeId = themeId
    }
}

/// `settings/active-theme.json`: which provider styles the launcher, and each
/// provider's last pick so switching back is one step. For the Kadomo provider
/// the theme id lives where it always has, `theme =` in config.toml; the copy
/// here is informational.
public struct ActiveThemeState: Sendable, Equatable, Codable {
    public var activeTheme: ThemeSelection
    public var lastSelected: [String: String]

    public init(activeTheme: ThemeSelection = ThemeSelection(provider: .kadomo, themeId: ""), lastSelected: [String: String] = [:]) {
        self.activeTheme = activeTheme
        self.lastSelected = lastSelected
    }

    public static var file: String { Paths.stateDirectory + "/settings/active-theme.json" }

    /// A missing or unreadable file means the native provider: Kadomo behaves
    /// exactly as it did before there was a second provider.
    public static func load(from path: String = file) -> ActiveThemeState {
        guard let data = FileManager.default.contents(atPath: path),
              let state = try? JSONDecoder().decode(ActiveThemeState.self, from: data) else { return ActiveThemeState() }
        return state
    }

    public func save(to path: String = file) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try AtomicFile.write(try encoder.encode(self), to: path)
    }

    /// Makes `selection` active and remembers it as that provider's last pick.
    public mutating func select(_ selection: ThemeSelection) {
        activeTheme = selection
        lastSelected[selection.provider.rawValue] = selection.themeId
    }
}

/// What the launcher should draw, and why.
public struct ThemeResolution: Sendable {
    public var theme: Theme?
    /// The provider actually drawing: `.kadomo` after any fallback.
    public var provider: ThemeProviderID
    public var diagnostics: [Diagnostic]
    /// The external theme could not be drawn and the native theme stands in.
    public var fellBack: Bool
}

public enum ActiveThemeResolver {
    /// Picks the theme to draw. The native resolver is the only one consulted
    /// for the Kadomo provider; the external one is consulted only for its own
    /// provider, and when it is missing (integration disabled or excluded) or
    /// fails, the native theme stands in and says why.
    public static func resolve(
        _ state: ActiveThemeState,
        native: () -> (Theme?, [Diagnostic]),
        external: ((ThemeSelection) -> Result<Theme, ExternalThemeError>)?
    ) -> ThemeResolution {
        let selection = state.activeTheme
        guard selection.provider != .kadomo else {
            let (theme, diags) = native()
            return ThemeResolution(theme: theme, provider: .kadomo, diagnostics: diags, fellBack: false)
        }
        let reason: String
        if let external {
            switch external(selection) {
            case .success(let theme):
                return ThemeResolution(theme: theme, provider: selection.provider, diagnostics: [], fellBack: false)
            case .failure(let error):
                reason = error.message
            }
        } else {
            reason = "the \(selection.provider.rawValue) integration is turned off"
        }
        let (theme, diags) = native()
        let note = Diagnostic(.warning, ActiveThemeState.file,
                              "\(selection.provider.rawValue) theme '\(selection.themeId)' is not available (\(reason)); showing the Kadomo theme")
        return ThemeResolution(theme: theme, provider: .kadomo, diagnostics: [note] + diags, fellBack: true)
    }
}

public struct ExternalThemeError: Error, Sendable, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

/// Writes a file so readers see the old or the new contents, never half of
/// one: a temporary file in the same folder, then rename(2) over the target.
public enum AtomicFile {
    public static func write(_ data: Data, to path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let temp = dir + "/." + (path as NSString).lastPathComponent + ".tmp-" + UUID().uuidString
        try data.write(to: URL(fileURLWithPath: temp))
        guard rename(temp, path) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(atPath: temp)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
}
