import AppKit
import KadomoMenuCore

/// Decoded icons, sized for the current theme. File icons are rendered to
/// bitmaps on a background queue; a row draws without its icon until the
/// bitmap arrives, so the main thread never waits on IconServices.
final class IconCache {
    private let cache = NSCache<NSString, NSImage>()
    private var pending = Set<String>()
    private var notifyScheduled = false
    private let queue = DispatchQueue(label: "kadomo-menu.icons", qos: .userInitiated, attributes: .concurrent)
    /// Called (coalesced) after background icons arrive.
    var onLoaded: (() -> Void)?

    init() {
        cache.countLimit = 800
    }

    func clear() {
        cache.removeAllObjects()
        pending.removeAll()
    }

    func image(_ icon: IconRef, size: CGFloat, tint: NSColor, monochromeApps: Bool) -> NSImage? {
        guard size > 0 else { return nil }
        switch icon {
        case .none, .glyph:
            return nil
        case .symbol(let name):
            return symbol(name, size: size, tint: tint)
        case .file(let path):
            if monochromeApps { return symbol("app", size: size, tint: tint) }
            let key = "file:\(Int(size)):\(path)" as NSString
            if let image = cache.object(forKey: key) { return image }
            load(path, size: size, key: key)
            return nil
        }
    }

    func symbol(_ name: String, size: CGFloat, tint: NSColor) -> NSImage? {
        let key = "sym:\(name):\(Int(size)):\(tint.hexKey)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.82, weight: .regular).applying(.init(paletteColors: [tint]))
        guard let image = base.withSymbolConfiguration(config) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Renders file icons ahead of time, in the background, at low priority.
    func prewarm(_ paths: [String], size: CGFloat) {
        guard size > 0 else { return }
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let work = paths.prefix(600).filter { cache.object(forKey: "file:\(Int(size)):\($0)" as NSString) == nil }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for path in work {
                let image = IconCache.render(path, size: size, scale: scale)
                DispatchQueue.main.async { self?.cache.setObject(image.image, forKey: "file:\(Int(size)):\(path)" as NSString) }
            }
        }
    }

    /// Renders synchronously. Only for snapshots.
    func loadNow(_ path: String, size: CGFloat) {
        let key = "file:\(Int(size)):\(path)" as NSString
        guard cache.object(forKey: key) == nil else { return }
        cache.setObject(IconCache.render(path, size: size, scale: 2).image, forKey: key)
    }

    private func load(_ path: String, size: CGFloat, key: NSString) {
        let keyString = key as String
        guard pending.insert(keyString).inserted else { return }
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        queue.async { [weak self] in
            let image = IconCache.render(path, size: size, scale: scale)
            DispatchQueue.main.async {
                guard let self else { return }
                self.cache.setObject(image.image, forKey: keyString as NSString)
                self.pending.remove(keyString)
                self.scheduleNotify()
            }
        }
    }

    private func scheduleNotify() {
        guard !notifyScheduled else { return }
        notifyScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.notifyScheduled = false
            self?.onLoaded?()
        }
    }

    nonisolated struct Rendered: @unchecked Sendable { let image: NSImage }

    /// Draws the Finder icon into a bitmap so later drawing is a plain blit.
    nonisolated static func render(_ path: String, size: CGFloat, scale: CGFloat) -> Rendered {
        let source = NSWorkspace.shared.icon(forFile: path)
        let px = Int(size * scale)
        let image = NSImage(size: NSSize(width: size, height: size))
        if px > 0, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            rep.size = NSSize(width: size, height: size)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        return Rendered(image: image)
    }
}

extension NSColor {
    var hexKey: String {
        guard let c = usingColorSpace(.sRGB) else { return description }
        return String(format: "%02x%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255), Int(c.alphaComponent * 255))
    }
}
