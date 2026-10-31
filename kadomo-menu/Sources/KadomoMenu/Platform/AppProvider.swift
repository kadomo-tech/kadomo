import AppKit
import KadomoMenuCore

/// Discovers installed applications. Runs off the main thread at startup and
/// when FSEvents reports a change in an application folder; never on open.
nonisolated enum AppProvider {
    /// Apps that also appear under Development.
    static let developerApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.github.wez.wezterm", "org.alacritty",
        "net.kovidgoyal.kitty", "dev.warp.Warp-Stable", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.apple.dt.Xcode", "com.sublimetext.4", "com.panic.Nova",
        "com.jetbrains.intellij", "com.jetbrains.pycharm", "com.jetbrains.goland", "com.jetbrains.rustrover",
        "com.fournova.Tower3", "com.DanPristupov.Fork", "com.github.GitHubClient", "com.docker.docker",
        "com.apple.iphonesimulator", "com.postmanlabs.mac", "com.tinyapp.TablePlus", "com.apple.Console",
        "com.apple.ActivityMonitor", "com.openai.codex", "com.anthropic.claudefordesktop",
    ]

    /// Extra search words for well-known apps people call by another name.
    static let knownAliases: [String: [String]] = [
        "com.microsoft.VSCode": ["vscode", "code"],
        "com.apple.systempreferences": ["preferences", "prefs", "settings"],
        "com.apple.Terminal": ["term", "shell"],
        "com.mitchellh.ghostty": ["terminal", "term"],
        "com.googlecode.iterm2": ["terminal", "term"],
        "com.apple.ActivityMonitor": ["task manager", "top", "processes"],
        "com.apple.finder": ["files", "explorer"],
        "org.mozilla.firefox": ["browser"],
        "com.google.Chrome": ["browser"],
        "com.apple.Safari": ["browser"],
        "com.apple.dt.Xcode": ["ide"],
    ]

    static func scan(directories: [String], exclude: Set<String>) -> [Item] {
        var seen = Set<String>()
        var items: [Item] = []
        let fm = FileManager.default
        var candidates: [String] = []
        for dir in directories.map(Paths.expand) {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in entries.sorted() {
                let path = "\(dir)/\(name)"
                if name.hasSuffix(".app") {
                    candidates.append(path)
                } else if !name.hasPrefix("."), (try? fm.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeDirectory {
                    // One level of folders, for /Applications/Setapp and friends.
                    for sub in ((try? fm.contentsOfDirectory(atPath: path)) ?? []).sorted() where sub.hasSuffix(".app") {
                        candidates.append("\(path)/\(sub)")
                    }
                }
            }
        }
        // Finder lives outside the application folders.
        candidates.append("/System/Library/CoreServices/Finder.app")

        for path in candidates {
            guard let item = item(at: path), !exclude.contains(item.id), !exclude.contains(String(item.id.dropFirst(4))) else { continue }
            guard seen.insert(item.id).inserted else { continue }
            items.append(item)
        }
        return items
    }

    static func item(at path: String) -> Item? {
        let url = URL(fileURLWithPath: path)
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else { return nil }
        if (info["LSBackgroundOnly"] as? Bool) == true || (info["LSBackgroundOnly"] as? String) == "1" { return nil }
        let bundleID = info["CFBundleIdentifier"] as? String
        let fileName = url.deletingPathExtension().lastPathComponent
        let display = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        let title = display.isEmpty ? fileName : display

        var keywords: [String] = []
        if fileName != title { keywords.append(fileName) }
        if let bundleID, let last = bundleID.split(separator: ".").last, last.lowercased() != title.lowercased() {
            keywords.append(String(last))
        }
        if let name = info["CFBundleName"] as? String, name != title, name != fileName { keywords.append(name) }
        let aliases = bundleID.flatMap { knownAliases[$0] } ?? []

        let dir = (path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        let id = "app:" + (bundleID ?? path)
        return Item(
            id: id, title: title, subtitle: dir, kind: .app, parent: Categories.apps,
            alsoIn: bundleID.map { developerApps.contains($0) } == true ? [Categories.development] : [],
            icon: .file(path), keywords: keywords, aliases: aliases,
            action: .openApp(path: path, newInstance: false),
            secondary: [
                SecondaryAction("Open New Instance", .openApp(path: path, newInstance: true), icon: .symbol("plus.square.on.square")),
                SecondaryAction("Reveal in Finder", .revealInFinder(path), icon: .symbol("folder")),
                SecondaryAction("Copy Path", .copy(path), icon: .symbol("doc.on.doc")),
                SecondaryAction("Copy Bundle Identifier", .copy(bundleID ?? ""), icon: .symbol("number")),
            ].filter { $0.action != .copy("") },
            source: "apps"
        )
    }
}
