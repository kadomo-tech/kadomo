import AppKit
import KadomoMenuCore

/// `KADOMO_MENU_SNAPSHOT=<dir>`: renders the real panel offscreen for every
/// theme in a few states and writes PNGs, then exits. For checking the design
/// without opening anything on screen.
///
///   KADOMO_MENU_SNAPSHOT_THEMES=kadomo-dark,kadomo-terminal   limit themes
///   KADOMO_MENU_SNAPSHOT_STATES=home,apps                     limit states
enum Snapshot {
    static func run(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let launcher = Launcher()
        launcher.start(interactive: false)
        let deadline = Date().addingTimeInterval(8)
        while !launcher.model.catalog.items.contains(where: { $0.kind == .app }), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let env = ProcessInfo.processInfo.environment
        let themes = env["KADOMO_MENU_SNAPSHOT_THEMES"].map { $0.split(separator: ",").map(String.init) } ?? BuiltinThemes.all.keys.sorted()
        let wanted = env["KADOMO_MENU_SNAPSHOT_STATES"].map { Set($0.split(separator: ",").map(String.init)) }
        let model = launcher.model

        let states: [(String, () -> Void)] = [
            ("home", { model.reset() }),
            ("apps", { model.open(category: Categories.apps) }),
            ("system", { model.open(category: Categories.system); model.handle(.command(.down, CaretContext())) }),
            ("search", { model.reset(); model.handle(.query("term")) }),
            ("settings", { model.reset(); model.handle(.query("blue")) }),
            ("actions", { model.reset(); model.handle(.query("safari")); model.handle(.command(.actions, CaretContext())) }),
            ("themes", { model.open(category: Categories.themes) }),
            ("confirm", { model.reset(); model.handle(.query("quit current")); model.handle(.command(.enter, CaretContext())) }),
            ("empty", { model.reset(); model.handle(.query("zzzqqq")) }),
        ]

        for theme in themes {
            if let error = launcher.setTheme(theme, persist: false) { print("skip \(theme): \(error)"); continue }
            for (name, setup) in states where wanted?.contains(name) ?? true {
                setup()
                let file = "\(dir)/\(theme)-\(name).png"
                capture(launcher, to: file)
                print(file)
            }
        }
    }

    static func capture(_ launcher: Launcher, to file: String) {
        let view = launcher.view
        let style = launcher.style
        launcher.view.field.stringValue = launcher.fieldText
        let height = view.show(rows: launcher.rowData(), selection: launcher.currentSelection, crumb: launcher.crumbText(),
                               emptyText: launcher.model.emptyMessage, footer: launcher.footerMessage())
        launcher.panel.setFrame(NSRect(x: 0, y: 0, width: style.width, height: height), display: false)
        view.frame = NSRect(x: 0, y: 0, width: style.width, height: height)
        view.layoutSubtreeIfNeeded()
        for row in launcher.rowData() {
            if case .file(let path) = row.icon { launcher.icons.loadNow(path, size: CGFloat(style.geometry.iconSize)) }
        }
        view.table.reloadData()
        view.table.layoutSubtreeIfNeeded()
        // Offscreen, NSTableView only makes row views on demand.
        for row in 0..<view.table.numberOfRows { _ = view.table.rowView(atRow: row, makeIfNecessary: true) }
        view.layoutSubtreeIfNeeded()
        view.display()
        if ProcessInfo.processInfo.environment["KADOMO_MENU_SNAPSHOT_DEBUG"] != nil {
            print("rows=\(view.table.numberOfRows) table=\(view.table.frame) scroll=\(view.scroll.frame) rv0=\(String(describing: view.table.rowView(atRow: 0, makeIfNecessary: false)))")
        }

        // Render at 2x even with no screen attached, where the backing scale is 1.
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)

        // Place it on a desktop-like backdrop, 2x, with a margin.
        let margin: CGFloat = 32
        let size = NSSize(width: view.bounds.width + 2 * margin, height: view.bounds.height + 2 * margin)
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        out.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        (style.dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.86, alpha: 1)).setFill()
        NSRect(origin: .zero, size: size).fill()
        rep.draw(in: NSRect(x: margin, y: margin, width: view.bounds.width, height: view.bounds.height), from: .zero,
                 operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        try? out.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
    }
}
