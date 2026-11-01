import Foundation
import KadomoMenuCore

/// Turns an Omarchy palette into Kadomo's appearance contract. The only place
/// that knows how Omarchy's color roles map onto the launcher's.
public enum OmarchyAdapter {
    /// Bump when the mapping changes; installed themes are revalidated against
    /// the new version and keep their last good appearance if that fails.
    public static let version = 1

    /// Builds the appearance. Missing colors are derived the same way every
    /// time; text is nudged until it reads against its background.
    public static func normalize(name: String, palette: OmarchyPalette, shell: OmarchyShellStyle? = nil,
                                 lightMarker: Bool = false) throws(OmarchyFormatError) -> ThemeAppearance {
        guard let paletteBackground = palette["background"] ?? palette["color0"] else {
            throw OmarchyFormatError("colors.toml has no background (or color0)")
        }
        guard let paletteForeground = palette["foreground"] ?? palette["color7"] else {
            throw OmarchyFormatError("colors.toml has no foreground (or color7)")
        }
        let background = shell?.background ?? paletteBackground
        let solid = background.with(alpha: 1)
        let mode = palette.mode ?? (lightMarker ? "light" : (solid.luminance > 0.4 ? "light" : "dark"))

        let foreground = (shell?.text ?? paletteForeground).readable(on: solid, ratio: 4.5)
        let lighter = palette["lighter_background"] ?? solid.mixed(with: foreground, 0.08)
        let accent = (palette["accent"] ?? palette["blue"] ?? palette["color4"] ?? foreground).readable(on: solid, ratio: 3)
        let secondary = (palette["dark_foreground"] ?? solid.mixed(with: foreground, 0.55)).readable(on: solid, ratio: 3)
        let border = shell?.border ?? [palette["muted"] ?? palette["color8"] ?? solid.mixed(with: foreground, 0.3)]

        let selection = shell?.selectedBackground ?? palette["selection"] ?? palette["selection_background"] ?? lighter
        // What the selected row really sits on, for the contrast check.
        let selectionSolid = solid.mixed(with: selection.with(alpha: 1), selection.a)
        let candidates = [shell?.selectedText, palette["selection_foreground"], accent, palette["bright_foreground"], foreground].compactMap { $0 }
        let selectedText = candidates.first { RGBA.contrast($0, selectionSolid) >= 4.5 }
            ?? (palette["bright_foreground"] ?? foreground).readable(on: selectionSolid, ratio: 4.5)

        let error = (palette["red"] ?? palette["color1"] ?? RGBA(hex: "#ff6b81")!).readable(on: solid, ratio: 3)
        let warning = (palette["yellow"] ?? palette["color3"] ?? RGBA(hex: "#ffc759")!).readable(on: solid, ratio: 3)

        let appearance = ThemeAppearance(
            name: name, appearance: mode, background: background, foreground: foreground, muted: secondary, accent: accent,
            selectionBackground: selection, selectionForeground: selectedText, border: border, separator: lighter,
            placeholder: secondary, caret: accent, breadcrumb: accent, hint: secondary, error: error, warning: warning).quantized
        let problems = appearance.validate()
        guard problems.isEmpty else { throw OmarchyFormatError("unusable colors: " + problems.joined(separator: "; ")) }
        return appearance
    }

    /// Reads a theme folder already copied into Kadomo's storage (or a staging
    /// copy) and builds its appearance. Only `colors.toml`, `shell.toml`, and
    /// `light.mode` are read.
    public static func normalize(directory: String, name: String) throws(OmarchyFormatError) -> (ThemeAppearance, [String]) {
        let fm = FileManager.default
        let colorsPath = directory + "/colors.toml"
        guard let data = fm.contents(atPath: colorsPath) else { throw OmarchyFormatError("no colors.toml") }
        guard let text = String(data: data, encoding: .utf8) else { throw OmarchyFormatError("colors.toml is not UTF-8 text") }
        let palette = try OmarchyPalette.parse(text)
        var warnings = palette.warnings
        var shell: OmarchyShellStyle?
        if let data = fm.contents(atPath: directory + "/shell.toml"), let text = String(data: data, encoding: .utf8) {
            let parsed = OmarchyShellStyle.parse(text, palette: palette)
            warnings += parsed.warnings
            shell = parsed
        }
        let light = fm.fileExists(atPath: directory + "/light.mode")
        let appearance = try normalize(name: name, palette: palette, shell: shell, lightMarker: light)
        return (appearance, warnings)
    }

    /// The palette a catalog entry advertises (`colors` in omarchytheme.com's
    /// JSON), for previews before anything is downloaded.
    public static func palette(fromCatalogColors colors: [String: String]) -> OmarchyPalette {
        var palette = OmarchyPalette()
        for (key, value) in colors { if let c = OmarchyColor.parse(value) { palette.colors[key] = c } }
        if palette["selection"] == nil, let s = palette["selection_background"] { palette.colors["selection"] = s }
        return palette
    }
}
