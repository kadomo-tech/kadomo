import AppKit
import KadomoMenuCore

// CoreServices also defines IconRef; ours wins inside this module.
typealias IconRef = KadomoMenuCore.IconRef

extension NSColor {
    convenience init(_ c: RGBA) {
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}

/// A theme resolved into AppKit colors and fonts. Built once per theme or
/// appearance change, never while typing.
struct Style {
    let theme: Theme
    let dark: Bool
    let geometry: ThemeGeometry
    let effects: ThemeEffects

    let background: NSColor
    let foreground: NSColor
    let muted: NSColor
    let accent: NSColor
    let selectionBackground: NSColor
    let selectionForeground: NSColor
    let border: [NSColor]
    let separator: NSColor
    let placeholder: NSColor
    let caret: NSColor
    let breadcrumb: NSColor
    let hint: NSColor
    let error: NSColor
    let warning: NSColor

    let titleFont: NSFont
    let selectedTitleFont: NSFont
    let subtitleFont: NSFont
    let hintFont: NSFont
    let searchFont: NSFont
    let breadcrumbFont: NSFont
    let footerFont: NSFont

    /// True when the selected row is filled with the accent (Minimal), so secondary text dims instead of using the hint color.
    let accentFilledSelection: Bool
    let chevronWidth: CGFloat

    /// The panel width after layout rules.
    let width: CGFloat
    /// The wider panel for Services, so service names and descriptions fit.
    let wideListWidth: CGFloat
    /// Keybinds reference: space after the key column, between an action and its note,
    /// and the most of a row the key column may take when the screen is too narrow for everything.
    let keyColumnGap: CGFloat = 16
    let keyNoteGap: CGFloat = 10
    let keyColumnMaxFraction: CGFloat = 0.5
    /// Keybinds reference rows: a line of the title font with room around it, never taller than a normal row.
    var keyRowStride: CGFloat { min(rowStride, ceil(titleFont.ascender - titleFont.descender) + 14 + CGFloat(geometry.rowSpacing)) }
    /// A Keybinds heading: a line of the subtitle font, with room above it to set the section off.
    var keyHeadingStride: CGFloat { ceil(subtitleFont.ascender - subtitleFont.descender) + 16 }
    let reduceMotion: Bool

    init(theme: Theme, dark: Bool) {
        self.theme = theme
        self.dark = dark
        geometry = theme.geometry
        effects = theme.effects
        let c = theme.colors(dark: dark)
        background = NSColor(c.background.with(alpha: c.background.a * theme.effects.backgroundOpacity))
        foreground = NSColor(c.foreground)
        muted = NSColor(c.muted)
        accent = NSColor(c.accent)
        selectionBackground = NSColor(c.selectionBackground)
        selectionForeground = NSColor(c.selectionForeground)
        switch c.border {
        case .solid(let x): border = [NSColor(x)]
        case .gradient(let xs, _): border = xs.map(NSColor.init)
        }
        separator = NSColor(c.separator)
        placeholder = NSColor(c.placeholder)
        caret = NSColor(c.caret)
        breadcrumb = NSColor(c.breadcrumb)
        hint = NSColor(c.hint)
        error = NSColor(c.error)
        warning = NSColor(c.warning)

        let f = theme.font
        titleFont = Style.font(f.family, f.size, f.weight)
        selectedTitleFont = Style.font(f.family, f.size, f.selectedWeight)
        subtitleFont = Style.font(f.family, f.subtitleSize, "regular")
        hintFont = Style.font(f.family, f.hintSize, "regular")
        searchFont = Style.font(f.searchFamily ?? f.family, f.searchSize, f.searchWeight)
        breadcrumbFont = Style.font(f.searchFamily ?? f.family, max(f.searchSize - 3, 10), "medium")
        footerFont = Style.font(f.family, max(f.hintSize - 1, 9), "regular")

        accentFilledSelection = theme.effects.selectionStyle == "fill" && RGBA.contrast(c.selectionBackground, c.background) > 2.5
        chevronWidth = ceil(("›" as NSString).size(withAttributes: [.font: titleFont]).width)
        width = theme.layout == "compact" ? min(theme.geometry.width, 460) : theme.geometry.width
        wideListWidth = max(width, min(theme.geometry.width * 1.45, 880))
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var rowStride: CGFloat { geometry.rowHeight + geometry.rowSpacing }
    var animationDuration: TimeInterval { reduceMotion ? 0 : effects.animationDuration }
    var showIcons: Bool { effects.showIcons && effects.iconStyle != "none" && geometry.iconSize > 0 }

    /// Shared paragraph styles for row text, so drawing allocates nothing per row.
    static let paragraphs: [NSTextAlignment: NSParagraphStyle] = {
        var out: [NSTextAlignment: NSParagraphStyle] = [:]
        for align in [NSTextAlignment.left, .right, .center] {
            let p = NSMutableParagraphStyle()
            p.lineBreakMode = .byTruncatingTail
            p.alignment = align
            out[align] = p
        }
        return out
    }()

    static func weight(_ name: String) -> NSFont.Weight {
        switch name {
        case "ultralight": .ultraLight
        case "thin": .thin
        case "light": .light
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        case "heavy": .heavy
        case "black": .black
        default: .regular
        }
    }

    static func font(_ family: String, _ size: Double, _ weightName: String) -> NSFont {
        let size = CGFloat(size)
        let w = weight(weightName)
        switch family.lowercased() {
        case "monospace", "mono", "sf mono":
            return .monospacedSystemFont(ofSize: size, weight: w)
        case "system", "sans", "sf pro":
            return .systemFont(ofSize: size, weight: w)
        case "rounded":
            let base = NSFont.systemFont(ofSize: size, weight: w)
            return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        default:
            let manager = NSFontManager.shared
            // NSFontManager weights run 0...15; 5 is regular, 9 bold.
            let table: [NSFont.Weight: Int] = [.ultraLight: 2, .thin: 3, .light: 4, .regular: 5, .medium: 6, .semibold: 8, .bold: 9, .heavy: 10, .black: 11]
            if let f = manager.font(withFamily: family, traits: [], weight: table[w] ?? 5, size: size) { return f }
            if let f = NSFont(name: family, size: size) { return f }
            Log.info("font family '\(family)' not found; using the monospaced system font")
            return .monospacedSystemFont(ofSize: size, weight: w)
        }
    }
}
