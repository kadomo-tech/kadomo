import AppKit
import KadomoMenuCore

/// Draws a whole result row in one pass: selection, icon, title, subtitle,
/// hint, chevron. No subviews, so scrolling and reloading stay cheap.
final class RowView: NSTableRowView {
    weak var host: LauncherView?
    var index = 0

    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}

    override func draw(_ dirtyRect: NSRect) {
        guard let host, host.rows.indices.contains(index) else { return }
        let s = host.style
        let g = s.geometry
        let data = host.rows[index]
        let selected = index == host.selection
        let rect = bounds.insetBy(dx: 0, dy: CGFloat(g.rowSpacing) / 2)
        let radius = CGFloat(g.rowCornerRadius)

        if selected {
            switch s.effects.selectionStyle {
            case "bar":
                s.selectionBackground.setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                s.accent.setFill()
                NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY + 6, width: 3, height: rect.height - 12), xRadius: 1.5, yRadius: 1.5).fill()
            case "outline":
                s.selectionForeground.withAlphaComponent(0.6).setStroke()
                let p = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
                p.lineWidth = 1
                p.stroke()
            default:
                s.selectionBackground.setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            }
        }

        let fg = selected && s.effects.selectionStyle != "outline" ? s.selectionForeground : (data.info ? s.foreground.withAlphaComponent(0.85) : s.foreground)
        let quiet = selected && s.accentFilledSelection ? s.selectionForeground.withAlphaComponent(0.75) : s.hint
        var x = rect.minX + CGFloat(g.rowInset)
        var right = rect.maxX - CGFloat(g.rowInset)

        if s.showIcons {
            let size = CGFloat(g.iconSize)
            let iconRect = NSRect(x: x, y: rect.midY - size / 2, width: size, height: size)
            if case .glyph(let glyph) = data.icon {
                draw(glyph, font: s.titleFont, color: fg, in: iconRect, align: .center)
            } else if let image = host.icons.image(data.icon, size: size, tint: fg, monochromeApps: s.effects.iconStyle == "symbols") {
                image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            x += size + max(14, size * 0.8)
        }

        if data.chevron && s.effects.showChevrons {
            let w = s.chevronWidth
            draw("›", font: s.titleFont, color: selected ? fg : s.hint, in: NSRect(x: right - w, y: rect.minY, width: w, height: rect.height), align: .right)
            right -= w + 10
        }
        if s.effects.showHints, let hint = data.hint, !hint.isEmpty {
            let w = min(measure(hint, s.hintFont), rect.width * 0.4)
            draw(hint, font: s.hintFont, color: quiet, in: NSRect(x: right - w, y: rect.minY, width: w, height: rect.height), align: .right)
            right -= w + 12
        }
        if data.favorite || data.current {
            let mark = data.current ? "●" : "★"
            let w = measure(mark, s.hintFont)
            draw(mark, font: s.hintFont, color: selected ? fg : s.accent, in: NSRect(x: right - w, y: rect.minY, width: w, height: rect.height), align: .right)
            right -= w + 10
        }

        let titleFont = selected ? s.selectedTitleFont : s.titleFont
        let available = max(right - x, 0)
        let wantsSubtitle = s.effects.showSubtitles && !data.subtitle.isEmpty
        // Measuring is only needed to place a subtitle after the title.
        let titleWidth = wantsSubtitle ? measure(data.title, titleFont) : 0
        if wantsSubtitle, titleWidth + 40 < available {
            draw(data.title, font: titleFont, color: fg, in: NSRect(x: x, y: rect.minY, width: titleWidth + 1, height: rect.height), align: .left)
            let sx = x + titleWidth + 10
            draw(data.subtitle, font: s.subtitleFont, color: selected && quiet != s.hint ? quiet : s.muted,
                 in: NSRect(x: sx, y: rect.minY, width: right - sx, height: rect.height), align: .left)
        } else {
            draw(data.title, font: titleFont, color: fg, in: NSRect(x: x, y: rect.minY, width: available, height: rect.height), align: .left)
        }
    }

    private func measure(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// One line, vertically centered in `rect`, truncated with an ellipsis.
    private func draw(_ text: String, font: NSFont, color: NSColor, in rect: NSRect, align: NSTextAlignment) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: Style.paragraphs[align]!]
        let lineHeight = ceil(font.ascender - font.descender)
        let r = NSRect(x: rect.minX, y: rect.midY - lineHeight / 2, width: rect.width, height: lineHeight + 2)
        (text as NSString).draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    override func accessibilityLabel() -> String? {
        guard let host, host.rows.indices.contains(index) else { return nil }
        let d = host.rows[index]
        return [d.title, d.subtitle, d.chevron ? "category" : nil, d.hint].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .row }
    override func isAccessibilitySelected() -> Bool { index == host?.selection }
}
