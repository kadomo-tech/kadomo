import AppKit
import KadomoMenuCore

/// Picks the display the launcher should appear on.
enum ScreenLocator {
    static func screen(for target: DisplayTarget) -> NSScreen? {
        switch target {
        case .primary: return NSScreen.screens.first
        case .mouse: return screenUnderMouse()
        case .active: return screenOfFrontmostWindow() ?? screenUnderMouse()
        }
    }

    static func screenUnderMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
    }

    /// The screen holding the frontmost app's frontmost window. Window bounds
    /// need no permission (titles would). Tiling window managers and
    /// fullscreen apps report normal bounds, so this follows them too.
    static func screenOfFrontmostWindow() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"], w > 40, h > 40 else { continue }
            // CoreGraphics uses a top-left origin on the primary display.
            let center = NSPoint(x: x + w / 2, y: primary.frame.maxY - (y + h / 2))
            return NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) }
        }
        return nil
    }

    /// The panel's top edge on `screen` for the theme's layout.
    static func top(on screen: NSScreen, style: Style) -> CGFloat {
        let visible = screen.visibleFrame
        return switch style.theme.layout {
        case "top": visible.maxY - 12
        default: visible.maxY - visible.height * CGFloat(style.geometry.topOffset)
        }
    }

    /// Where the panel goes on `screen` for a given layout. The top edge stays
    /// put while the height changes, so the search line never jumps.
    static func frame(on screen: NSScreen, style: Style, width wanted: CGFloat? = nil, height: CGFloat) -> NSRect {
        let visible = screen.visibleFrame
        let width = min(wanted ?? style.width, visible.width - 32)
        let x = visible.midX - width / 2
        let top = top(on: screen, style: style)
        let h = min(height, top - visible.minY - 16)
        return NSRect(x: round(x), y: round(top - h), width: round(width), height: round(h))
    }
}
