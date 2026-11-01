import AppKit
import KadomoMenuCore

/// What one list row shows.
struct RowData: Equatable {
    var title: String
    var subtitle = ""
    var icon = IconRef.none
    var hint: String?
    var chevron = false
    var favorite = false
    var info = false
    /// Marks the active choice in a list, like the current theme.
    var current = false
    /// A row of the Keybinds reference: the hint is the key, drawn first, then → title.
    var keybind = false
    /// A section label in the Keybinds reference.
    var heading = false
}

/// The panel's content: chrome (background, border), the search line with
/// breadcrumb, the result list, and a footer for messages. Layout is plain
/// frame math so typing never triggers an Auto Layout pass.
final class LauncherView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let chrome = ChromeView()
    let field = SearchField()
    let crumb = NSTextField(labelWithString: "")
    let footer = NSTextField(labelWithString: "")
    let empty = NSTextField(labelWithString: "")
    let scroll = NSScrollView()
    let table = ListTable()
    private var effect: NSVisualEffectView?
    private(set) var style: Style
    let icons: IconCache

    private(set) var rows: [RowData] = []
    /// Width of the widest key in the Keybinds reference, so every row lines up.
    var keyColumnWidth: CGFloat = 0
    /// The Keybinds reference is open: shorter rows and headings, and more of them on screen.
    var compact = false
    /// The most the list may take, so a long Keybinds list stays on screen. Set by the launcher.
    var maxListHeight: CGFloat = .greatestFiniteMagnitude
    private(set) var selection = -1
    var onClick: ((Int) -> Void)?
    var onHover: ((Int) -> Void)?
    private var footerMessage: (String, NSColor)?
    private var tracking: NSTrackingArea?

    init(style: Style, icons: IconCache) {
        self.style = style
        self.icons = icons
        super.init(frame: NSRect(x: 0, y: 0, width: style.width, height: 300))
        wantsLayer = true
        autoresizingMask = [.width, .height]

        chrome.frame = bounds
        chrome.autoresizingMask = [.width, .height]
        addSubview(chrome)

        crumb.lineBreakMode = .byTruncatingHead
        crumb.isHidden = true
        addSubview(crumb)
        addSubview(field)

        table.addTableColumn(NSTableColumn(identifier: .init("main")))
        table.headerView = nil
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.gridStyleMask = []
        table.focusRingType = .none
        table.style = .plain
        table.usesAutomaticRowHeights = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        table.setAccessibilityLabel("Results")
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.contentView.drawsBackground = false
        addSubview(scroll)

        empty.alignment = .center
        empty.lineBreakMode = .byTruncatingTail
        empty.isHidden = true
        addSubview(empty)

        footer.lineBreakMode = .byTruncatingTail
        footer.isHidden = true
        addSubview(footer)

        apply(style)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: Style

    func apply(_ style: Style) {
        self.style = style
        let g = style.geometry
        chrome.style = style
        chrome.needsDisplay = true

        if style.effects.material != "none" {
            let view = effect ?? NSVisualEffectView()
            view.material = switch style.effects.material {
            case "hud": .hudWindow
            case "menu": .menu
            case "sidebar": .sidebar
            case "under-window": .underWindowBackground
            default: .popover
            }
            view.blendingMode = .behindWindow
            view.state = .active
            view.maskImage = LauncherView.mask(radius: g.cornerRadius)
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            if effect == nil { addSubview(view, positioned: .below, relativeTo: chrome) }
            effect = view
        } else {
            effect?.removeFromSuperview()
            effect = nil
        }
        appearance = NSAppearance(named: style.dark ? .darkAqua : .aqua)

        field.font = style.searchFont
        field.textColor = style.foreground
        field.placeholderAttributedString = NSAttributedString(string: style.effects.placeholder, attributes: [
            .foregroundColor: style.placeholder, .font: style.searchFont,
        ])
        crumb.font = style.breadcrumbFont
        crumb.textColor = style.breadcrumb
        empty.font = style.titleFont
        empty.textColor = style.muted
        footer.font = style.footerFont
        table.rowHeight = style.rowStride
        table.enumerateAvailableRowViews { view, _ in view.needsDisplay = true }
        needsLayout = true
    }

    static func mask(radius: Double) -> NSImage {
        let r = CGFloat(radius)
        let edge = 2 * r + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }

    // MARK: Content

    /// Replaces the rows. Returns the panel height they need.
    @discardableResult
    func show(rows: [RowData], selection: Int, crumb text: String?, emptyText: String?, footer message: (String, NSColor)?) -> CGFloat {
        let changed = rows != self.rows
        self.rows = rows
        let oldSelection = self.selection
        self.selection = selection
        if changed {
            table.reloadData()
        } else if oldSelection != selection {
            redraw(row: oldSelection)
            redraw(row: selection)
        }
        if rows.indices.contains(selection) { table.scrollRowToVisible(selection) }

        let crumbText = style.effects.showBreadcrumb ? (text ?? "") : ""
        if crumb.stringValue != crumbText { crumb.stringValue = crumbText; needsLayout = true }
        crumb.isHidden = crumbText.isEmpty
        empty.stringValue = emptyText ?? ""
        empty.isHidden = emptyText == nil || !rows.isEmpty
        footerMessage = message
        footer.isHidden = message == nil
        if let message {
            footer.stringValue = message.0
            footer.textColor = message.1
        }
        needsLayout = true
        return preferredHeight
    }

    func redraw(row: Int) {
        guard rows.indices.contains(row), let view = table.rowView(atRow: row, makeIfNecessary: false) else { return }
        view.needsDisplay = true
    }

    func refreshVisibleRows() {
        table.enumerateAvailableRowViews { view, _ in view.needsDisplay = true }
    }

    var visibleRowCount: Int { max(1, min(rows.count, compact ? style.geometry.keybindRows : style.geometry.maxRows)) }

    func height(ofRow row: Int) -> CGFloat {
        guard compact else { return style.rowStride }
        return rows.indices.contains(row) && rows[row].heading ? style.keyHeadingStride : style.keyRowStride
    }

    /// The first rows' heights (whole rows only), within `maxListHeight`.
    var listHeight: CGFloat {
        guard compact else { return CGFloat(visibleRowCount) * style.rowStride }
        var total: CGFloat = 0
        for row in 0..<visibleRowCount {
            let h = height(ofRow: row)
            if total + h > maxListHeight, total > 0 { break }
            total += h
        }
        return total
    }

    var footerHeight: CGFloat { footer.isHidden ? 0 : ceil(style.footerFont.ascender - style.footerFont.descender) + 10 }

    var listTop: CGFloat {
        let g = style.geometry
        return g.padding + g.searchHeight + g.gap
    }

    var preferredHeight: CGFloat {
        listTop + listHeight + footerHeight + style.geometry.padding
    }

    override func layout() {
        super.layout()
        let g = style.geometry
        let w = bounds.width
        let lineHeight = ceil(style.searchFont.ascender - style.searchFont.descender + style.searchFont.leading) + 2
        let textX = g.padding + g.rowInset - 2
        let fieldY = g.padding + (g.searchHeight - lineHeight) / 2
        var fieldX = textX
        if !crumb.isHidden {
            crumb.sizeToFit()
            let cw = min(crumb.frame.width, w * 0.45)
            let ch = crumb.frame.height
            // The crumb uses a smaller font than the query, so centering each
            // one leaves them on different lines. Put both on one baseline.
            let fieldBaseline = fieldY + Self.textTop(field, height: lineHeight) + style.searchFont.ascender
            let crumbY = fieldBaseline - Self.textTop(crumb, height: ch) - style.breadcrumbFont.ascender
            crumb.frame = NSRect(x: textX, y: crumbY.rounded(), width: cw, height: ch)
            fieldX = textX + cw + 6
        }
        field.frame = NSRect(x: fieldX, y: fieldY, width: w - fieldX - g.padding - g.rowInset / 2, height: lineHeight)
        let listHeight = bounds.height - listTop - footerHeight - g.padding
        scroll.frame = NSRect(x: g.padding, y: listTop, width: w - 2 * g.padding, height: max(listHeight, 0))
        table.tableColumns.first?.width = scroll.frame.width
        empty.sizeToFit()
        empty.frame = NSRect(x: g.padding, y: listTop + (style.rowStride - empty.frame.height) / 2, width: w - 2 * g.padding, height: empty.frame.height)
        if !footer.isHidden {
            footer.sizeToFit()
            footer.frame = NSRect(x: textX, y: bounds.height - g.padding - footerHeight + 4, width: w - textX - g.padding, height: footer.frame.height)
        }
        chrome.separatorY = style.effects.showSeparator ? g.padding + g.searchHeight + g.gap / 2 : nil
    }

    /// How far below a text field's top edge its cell starts drawing text.
    private static func textTop(_ view: NSTextField, height: CGFloat) -> CGFloat {
        guard let cell = view.cell else { return 0 }
        return cell.titleRect(forBounds: NSRect(x: 0, y: 0, width: 1000, height: height)).minY
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let p = table.convert(event.locationInWindow, from: nil)
        let row = table.row(at: p)
        if row >= 0 { onHover?(row) }
    }

    @objc private func clicked() {
        let row = table.clickedRow
        if row >= 0 { onClick?(row) }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { nil }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { height(ofRow: row) }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("row")
        let view = (tableView.makeView(withIdentifier: id, owner: nil) as? RowView) ?? RowView()
        view.identifier = id
        view.host = self
        view.index = row
        view.needsDisplay = true
        return view
    }
}

/// Background fill, gradient border, and the optional separator.
final class ChromeView: NSView {
    var style: Style?
    var separatorY: CGFloat? { didSet { if oldValue != separatorY { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let style, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let g = style.geometry
        let bw = CGFloat(g.borderWidth)
        let rect = bounds.insetBy(dx: bw / 2, dy: bw / 2)
        let radius = max(CGFloat(g.cornerRadius) - bw / 2, 0)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        style.background.setFill()
        path.fill()

        if let y = separatorY {
            style.separator.setFill()
            NSRect(x: bw, y: bounds.height - y - 0.5, width: bounds.width - 2 * bw, height: 1).fill()
        }

        guard bw > 0 else { return }
        ctx.saveGState()
        ctx.addPath(path.cgPath.copy(strokingWithWidth: bw, lineCap: .butt, lineJoin: .round, miterLimit: 10))
        ctx.clip()
        if style.border.count > 1, let gradient = NSGradient(colors: style.border) {
            gradient.draw(in: bounds, angle: -35)
        } else {
            (style.border.first ?? .clear).setFill()
            bounds.fill()
        }
        ctx.restoreGState()
    }
}
