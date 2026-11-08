import AppKit

/// A borderless, non-activating panel: it takes keyboard input while the app
/// you were using stays frontmost, so focus returns to it on dismiss.
final class LauncherPanel: NSPanel, NSWindowDelegate {
    /// Gets every key-down first. Return true to swallow it.
    var keyHandler: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?
    let fieldEditor = FieldEditor()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        // Join every Space and appear over fullscreen apps without switching Spaces.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        delegate = self
        setAccessibilityTitle("Kadomo Menu")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    /// An accessory app has no Edit menu, so the standard editing shortcuts
    /// would otherwise never reach the field editor.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let action: Selector? = switch (flags, event.charactersIgnoringModifiers?.lowercased()) {
        case ([.command], "v"): #selector(NSText.paste(_:))
        case ([.command], "c"): #selector(NSText.copy(_:))
        case ([.command], "x"): #selector(NSText.cut(_:))
        case ([.command], "a"): #selector(NSText.selectAll(_:))
        case ([.command], "z"): Selector(("undo:"))
        case ([.command, .shift], "z"): Selector(("redo:"))
        default: nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }

    func windowDidResignKey(_ notification: Notification) { onResignKey?() }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        client is SearchField ? fieldEditor : nil
    }
}

/// The shared text editor behind the search field, so the caret takes the theme color.
final class FieldEditor: NSTextView {
    init() {
        // A nil container leaves the view with no text storage, and typing goes nowhere.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isFieldEditor = true
        isRichText = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class SearchField: NSTextField {
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        // Not usesSingleLineMode: with some fonts (JetBrainsMono Nerd Font) it
        // draws the text ~3pt above where AppKit reports the baseline, so the
        // breadcrumb can't line up with it. Launcher flattens pasted newlines.
        lineBreakMode = .byClipping
        cell?.isScrollable = true
        cell?.wraps = false
        setAccessibilityLabel("Search")
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Where the caret is, for arrows that navigate only at the text's edges.
    var caret: (atStart: Bool, atEnd: Bool, hasSelection: Bool) {
        guard let editor = currentEditor() else { return (true, true, false) }
        let r = editor.selectedRange
        let length = (stringValue as NSString).length
        return (r.location == 0 && r.length == 0, r.location + r.length >= length && r.length == 0, r.length > 0)
    }
}

/// A list that never takes focus from the search field.
final class ListTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
    override func drawBackground(inClipRect clipRect: NSRect) {}
}
