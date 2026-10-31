import AppKit

/// A short, non-activating message near the top of a screen, for failures
/// that happen after the launcher has closed. Fades out by itself.
final class Toast {
    private let panel: NSPanel
    private let label = NSTextField(wrappingLabelWithString: "")
    private let chrome = ChromeView()
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 60), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let content = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        chrome.frame = content.bounds
        chrome.autoresizingMask = [.width, .height]
        content.addSubview(chrome)
        label.maximumNumberOfLines = 3
        content.addSubview(label)
        panel.contentView = content
    }

    func show(_ message: String, style: Style, color: NSColor, on screen: NSScreen?) {
        chrome.style = style
        chrome.needsDisplay = true
        label.font = style.hintFont.withSize(max(style.hintFont.pointSize, 12))
        label.textColor = color
        label.stringValue = message
        label.setAccessibilityLabel(message)
        let width: CGFloat = 460
        let pad: CGFloat = 16
        label.preferredMaxLayoutWidth = width - 2 * pad
        let size = label.fittingSize
        let height = size.height + 2 * pad - 4
        label.frame = NSRect(x: pad, y: (height - size.height) / 2, width: width - 2 * pad, height: size.height)
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: visible.midX - width / 2, y: visible.maxY - height - 40, width: width, height: height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        NSAccessibility.post(element: label, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide(style: style) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: work)
    }

    private func hide(style: Style) {
        if style.reduceMotion {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}
