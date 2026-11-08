import AppKit
import KadomoMenuCore

/// `KADOMO_MENU_SELFTEST=1`: drives the real launcher in-process through the
/// same handler the CLI socket uses, on whatever config dir is set, then
/// exits 0 when every check passes. `tools/check-cli.sh` covers the socket.
enum SelfTest {
    static func run() async -> Int32 {
        let launcher = Launcher()
        launcher.start(interactive: false)
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            print("\(ok ? "PASS" : "FAIL") \(name)\(ok ? "" : ": \(detail())")")
            if !ok { failures += 1 }
        }
        func call(_ args: String...) async -> IPCResponse { await launcher.handle(IPCRequest(args: args)) }

        // Let the background app scan land.
        for _ in 0..<100 where !launcher.model.catalog.items.contains(where: { $0.kind == .app }) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let apps = launcher.model.catalog.items.filter { $0.kind == .app }.count
        check("apps discovered", apps > 10, "\(apps)")
        check("no duplicate app ids", Set(launcher.model.catalog.items.map(\.id)).count == launcher.model.catalog.items.count)

        let status = await call("status")
        check("status", status.status == 0 && status.output.contains("Kadomo Menu"), status.output)

        check("theme set", await call("theme", "set", "kadomo-terminal").status == 0)
        check("theme current", await call("theme", "current").output == "kadomo-terminal")
        let saved = (try? String(contentsOfFile: Paths.configFile, encoding: .utf8)) ?? ""
        check("theme saved to config.toml", saved.contains("theme = \"kadomo-terminal\""), saved)
        check("unknown theme rejected", await call("theme", "set", "nope").status != 0)
        check("theme still terminal", launcher.theme.id == "kadomo-terminal")

        let list = await call("commands", "list")
        check("user command listed", list.output.contains("cmd:touch"), String(list.output.prefix(200)))
        check("json list", await call("commands", "list", "--json").output.contains("\"id\" : \"sys:sleep\""))

        let marker = (Paths.configDirectory as NSString).deletingLastPathComponent + "/marker"
        try? FileManager.default.removeItem(atPath: marker)
        check("run exec command", await call("commands", "run", "cmd:touch").status == 0)
        check("exec command ran", FileManager.default.fileExists(atPath: marker), marker)
        let failed = await call("commands", "run", "cmd:fails")
        check("failure reported", failed.status == 1 && failed.output.contains("status 3") && failed.output.contains("nope"), failed.output)
        check("unknown id exits 2", await call("commands", "run", "sys:nope").status == 2)
        check("confirm needs --yes", await call("commands", "run", "win:quit-current").status == 1)

        // Search through the live catalog, the way typing does.
        launcher.model.reset()
        launcher.model.handle(.query("zz"))
        check("config alias", launcher.model.selectedItem?.id == "sys:sleep", launcher.model.selectedItem?.id ?? "nil")
        launcher.model.handle(.query("bluetooth"))
        check("settings search", launcher.model.selectedItem?.id == "set:com.apple.BluetoothSettings", launcher.model.selectedItem?.id ?? "nil")
        launcher.model.handle(.query("term"))
        check("app search", launcher.model.selectedItem?.kind == .app, launcher.model.selectedItem?.title ?? "nil")

        // Real key events through the panel, the way a person types.
        launcher.show()
        for ch in "term" {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                            windowNumber: launcher.panel.windowNumber, context: nil,
                                            characters: String(ch), charactersIgnoringModifiers: String(ch),
                                            isARepeat: false, keyCode: 0) { launcher.panel.sendEvent(e) }
            }
        }
        check("typing searches", launcher.model.state.query == "term", "query=\(launcher.model.state.query) field=\(launcher.view.field.stringValue) key=\(launcher.panel.isKeyWindow)")
        launcher.hide()

        // Hot reload picks up new files; a broken config keeps the last good one.
        let late = Paths.commandsDirectory + "/late.toml"
        try? "[[command]]\nid = \"late\"\ntitle = \"Added Later\"\nurl = \"https://example.com\"\n".write(toFile: late, atomically: false, encoding: .utf8)
        _ = await call("reload")
        check("reload adds command", launcher.model.catalog.item("cmd:late") != nil)
        let original = saved
        try? (original + "\ntheme = \n").write(toFile: Paths.configFile, atomically: false, encoding: .utf8)
        let broken = await call("reload")
        check("broken config reload fails", broken.status == 1, broken.output)
        check("kept previous config", launcher.theme.id == "kadomo-terminal")
        try? original.write(toFile: Paths.configFile, atomically: false, encoding: .utf8)
        check("recovers after fix", await call("reload").status == 0)

        // Rapid open/close with typing in between (offscreen when no window server).
        for _ in 0..<50 {
            launcher.show()
            launcher.model.handle(.query("f"))
            launcher.render()
            launcher.hide()
        }
        check("rapid open/close", launcher.model.state.path.isEmpty)

        check("unknown command exits 2", await call("bogus").status == 2)
        await omarchy(launcher, check: { check($0, $1, $2) }, call: { await launcher.handle(IPCRequest(args: $0)) })
        print(failures == 0 ? "PASS self-test" : "FAIL self-test: \(failures) failing")
        return failures == 0 ? 0 : 1
    }
}

extension SelfTest {
    /// The Omarchy provider end to end, on a local theme folder (no network
    /// unless KADOMO_SELFTEST_NETWORK=1), and Kadomo's themes around it.
    static func omarchy(_ launcher: Launcher, check report: (String, Bool, String) -> Void,
                        call: ([String]) async -> IPCResponse) async {
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") { report(name, ok, ok ? "" : detail()) }
        guard launcher.external != nil else {
            check("omarchy off: command refused", await call(["omarchy", "list"]).status == 1, "")
            return
        }
        let base = (Paths.configDirectory as NSString).deletingLastPathComponent
        let folder = base + "/omarchy-tokyo-test-theme"
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? Data("""
        mode = "dark"
        accent = "#7aa2f7"
        selection = "#292e42"
        muted = "#414868"
        bg = "#1a1b26"
        foreground = "#a9b1d6"
        dark_foreground = "#565f89"
        red = "#f7768e"
        """.utf8).write(to: URL(fileURLWithPath: folder + "/colors.toml"))
        try? Data("#!/bin/sh\ntouch \(base)/pwned\n".utf8).write(to: URL(fileURLWithPath: folder + "/install.sh"))

        let checked = await call(["omarchy", "check", folder])
        check("omarchy check", checked.status == 0 && checked.output.contains("#1a1b26"), checked.output)
        let imported = await call(["omarchy", "import", folder])
        check("omarchy import applies", imported.status == 0 && launcher.theme.id == "omarchy:local:omarchy-tokyo-test-theme", imported.output + " " + launcher.theme.id)
        check("omarchy theme colors", launcher.theme.colors.background == RGBA(hex: "#1a1b26"), launcher.theme.colors.background.hexString)
        check("omarchy keeps Kadomo geometry", launcher.theme.geometry == Launcher.defaultTheme.geometry)
        check("theme provider", await call(["theme", "provider"]).output == "omarchy local:omarchy-tokyo-test-theme")
        // Every app follows it through the theme manager (a stub here).
        let log = base + "/theme-set.log"
        func themeSetCalls() async -> String {
            for _ in 0..<40 {
                if let text = try? String(contentsOfFile: log, encoding: .utf8), !text.isEmpty { return text }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return ""
        }
        if DesktopThemes.available {
            let calls = await themeSetCalls()
            check("desktop: theme-set --external", calls.hasPrefix("--external|") && calls.contains("/integrations/omarchy/themes/")
                  && calls.contains("|omarchy-omarchy-tokyo-test-theme-") && calls.contains("|Tokyo Test|"), calls)
            try? FileManager.default.removeItem(atPath: log)
        }
        check("nothing executed", !FileManager.default.fileExists(atPath: base + "/pwned"))
        let state = ActiveThemeState.load()
        check("selection persisted", state.activeTheme == ThemeSelection(provider: .omarchy, themeId: "local:omarchy-tokyo-test-theme"), "\(state)")
        launcher.rebuild(sync: true)
        check("separate menus", launcher.model.catalog.item("appearance/omarchy") != nil && launcher.model.catalog.item(Categories.themes) != nil)
        check("installed row", launcher.model.catalog.item("omarchy-theme:local:omarchy-tokyo-test-theme")?.hint == "current")
        check("kadomo list has no omarchy rows", !launcher.model.catalog.items.contains { $0.parent == Categories.themes && $0.source == "omarchy" })
        check("use kadomo row", launcher.model.catalog.item("theme-provider:kadomo") != nil)

        // Back to Kadomo: the Omarchy pick is remembered, nothing is uninstalled.
        check("switch to kadomo", await call(["theme", "set", "kadomo-dark"]).status == 0 && launcher.theme.id == "kadomo-dark")
        if DesktopThemes.available {
            let calls = await themeSetCalls()
            check("desktop: back with theme-set --native", calls.hasPrefix("--native|"), calls)
            try? FileManager.default.removeItem(atPath: log)
        }
        check("provider kadomo", launcher.activeState.activeTheme.provider == .kadomo && launcher.activeState.lastSelected["omarchy"] == "local:omarchy-tokyo-test-theme")
        check("still installed", await call(["omarchy", "list"]).output.contains("local:omarchy-tokyo-test-theme"))

        // Preview while selected; leaving restores; the active theme never changes.
        launcher.rebuild(sync: true)
        launcher.show(category: OmarchyCategory.installed)
        launcher.apply(.handled)
        check("preview shows", launcher.shownTheme.id.hasPrefix("preview:") && launcher.theme.id == "kadomo-dark", launcher.shownTheme.id)
        launcher.apply(launcher.model.handle(.command(.close, CaretContext())))
        check("preview ends on leaving the row", launcher.shownTheme.id == "kadomo-dark", launcher.shownTheme.id)
        launcher.show(category: OmarchyCategory.installed)
        launcher.apply(.handled)
        launcher.hide()
        check("cancel restores", launcher.shownTheme.id == "kadomo-dark" && ActiveThemeState.load().activeTheme.provider == .kadomo)

        // Typing in Install from Git is input, not search.
        launcher.show(category: OmarchyCategory.git)
        launcher.model.handle(.query("https://example.com/a/b"))
        check("git input", launcher.model.inputText == "https://example.com/a/b" && launcher.model.selectedItem?.id == "omarchy-git:install")
        launcher.hide()
        let refused = await call(["omarchy", "install", "https://user:pw@example.com/a/b"])
        check("unsafe url refused", refused.status == 1, refused.output)

        // The active Omarchy theme's metadata breaks: the Kadomo theme takes over.
        check("apply again", await call(["omarchy", "apply", "local:omarchy-tokyo-test-theme"]).status == 0)
        let metadata = Paths.stateDirectory + "/integrations/omarchy/metadata"
        for f in (try? FileManager.default.contentsOfDirectory(atPath: metadata)) ?? [] {
            try? Data("{".utf8).write(to: URL(fileURLWithPath: metadata + "/" + f))
        }
        // The in-memory last good appearance stays until the library is read again.
        _ = await call(["reload"])
        check("last good appearance kept", launcher.theme.id.hasPrefix("omarchy:"), launcher.theme.id)
        _ = await call(["omarchy", "list"])
        check("corrupt omarchy falls back", launcher.activeState.activeTheme.provider == .kadomo && !launcher.theme.id.hasPrefix("omarchy:"), launcher.theme.id)
        check("removal of a broken theme", await call(["omarchy", "remove", "local:omarchy-tokyo-test-theme"]).status == 0)

        // Turned off: no Omarchy menu or commands; Kadomo themes as before.
        let config = (try? String(contentsOfFile: Paths.configFile, encoding: .utf8)) ?? ""
        try? (config + "\n[omarchy]\nenabled = false\n").write(toFile: Paths.configFile, atomically: false, encoding: .utf8)
        _ = await call(["reload"])
        check("off: no menu", launcher.model.catalog.item("appearance/omarchy") == nil && launcher.external == nil)
        check("off: command refused", await call(["omarchy", "list"]).status == 1)
        check("off: kadomo themes work", await call(["theme", "set", "kadomo-terminal"]).status == 0 && launcher.theme.id == "kadomo-terminal")
        try? config.write(toFile: Paths.configFile, atomically: false, encoding: .utf8)
        _ = await call(["reload"])
        check("on again", launcher.model.catalog.item("appearance/omarchy") != nil)

        guard ProcessInfo.processInfo.environment["KADOMO_SELFTEST_NETWORK"] == "1" else { return }
        let official = await call(["omarchy", "official", "--refresh"])
        check("net: official list", official.status == 0 && official.output.contains("tokyo-night"), String(official.output.prefix(300)))
        let nord = await call(["omarchy", "install", "nord"])
        check("net: official install", nord.status == 0 && launcher.theme.id == "omarchy:official:nord", nord.output)
        let community = await call(["omarchy", "community", "lumon", "--refresh"])
        check("net: community list", community.status == 0 && community.output.contains("lumon"), String(community.output.prefix(300)))
        let bundled = await call(["omarchy", "community", "robzee84"])
        check("net: bundled community theme", bundled.status == 0 && bundled.output.lowercased().contains("robzee84"), String(bundled.output.prefix(300)))
        let robzee = await call(["omarchy", "install", "robzee84"])
        check("net: bundled community install", robzee.status == 0 && launcher.theme.id.contains("robzee84"), robzee.output + " " + launcher.theme.id)
        let lumon = await call(["omarchy", "install", "https://github.com/OldJobobo/omarchy-lumon-theme.git"])
        check("net: git install", lumon.status == 0 && launcher.theme.id.hasPrefix("omarchy:git:github.com/oldjobobo/omarchy-lumon-theme"), lumon.output)
        let update = await call(["omarchy", "update"])
        check("net: update", update.status == 0 && update.output.contains("up to date"), update.output)
        print((await call(["omarchy", "list"])).output)
    }
}

/// `KADOMO_MENU_PROFILE=1`: times the main operations of a normal session in
/// this process, for finding the expensive ones. Drawing goes to an offscreen
/// bitmap, so it works without a window server.
enum Profile {
    static func run() async -> Int32 {
        func time(_ n: Int, _ body: () -> Void) -> LatencyStats {
            var samples: [Double] = []
            for _ in 0..<n { samples.append(Clock.measure(body)) }
            return LatencyStats(samples)
        }
        print(String(format: "memory at process start         %.1f MB", Launcher.memoryFootprint()))

        let t0 = Clock.now()
        let launcher = Launcher()
        launcher.start(interactive: false)
        let started = Clock.now() - t0
        for _ in 0..<200 where !launcher.model.catalog.items.contains(where: { $0.kind == .app }) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        let withApps = Clock.now() - t0
        print(String(format: "launcher start → searchable      %.1f ms (apps indexed at %.1f ms)", started, withApps))
        print(String(format: "memory after start + app scan   %.1f MB", Launcher.memoryFootprint()))
        let items = launcher.model.catalog.items
        let dirs = AppConfig.defaultAppDirectories
        var apps: [Item] = []
        let scan = time(5) { apps = AppProvider.scan(directories: dirs, exclude: []) }
        print("app scan (\(apps.count) apps)           \(scan)")
        print("catalog build (\(items.count) items)    \(time(20) { _ = Catalog(items: items) })")

        let paths = apps.prefix(40).compactMap { if case .file(let p) = $0.icon { p } else { nil } }
        var i = 0
        print("app icon render (1 icon)        \(time(paths.count) { _ = IconCache.render(paths[i % paths.count], size: 18, scale: 2); i += 1 })")

        let view = launcher.view
        func draw() {
            view.layoutSubtreeIfNeeded()
            for r in 0..<view.table.numberOfRows { _ = view.table.rowView(atRow: r, makeIfNecessary: true) }
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: rep) }
        }
        print("screen locate (active window)   \(time(50) { _ = ScreenLocator.screen(for: .active) })")
        print("open: reset + rows + layout     \(time(200) { launcher.model.reset(); launcher.render(animated: false); view.layoutSubtreeIfNeeded() })")
        print("open: full offscreen draw       \(time(100) { launcher.model.reset(); launcher.render(animated: false); draw() })")
        let queries = ["f", "fi", "fir", "fire", "s", "sa", "saf", "term", "blue", "sys"]
        var q = 0
        print("query → model + rows + layout   \(time(500) { launcher.model.handle(.query(queries[q % queries.count])); launcher.render(animated: false); view.layoutSubtreeIfNeeded(); q += 1 })")
        print("query → full offscreen draw     \(time(200) { launcher.model.handle(.query(queries[q % queries.count])); launcher.render(animated: false); draw(); q += 1 })")
        print("selection move → rows redrawn   \(time(200) { launcher.apply(launcher.model.handle(.command(.down, CaretContext()))); draw() })")
        print("theme switch (resolve + style)  \(time(20) { _ = launcher.setTheme(q % 2 == 0 ? "kadomo-minimal" : "kadomo-dark", persist: false); q += 1 })")
        // What applying an installed Omarchy theme costs once its appearance is
        // cached: contract → Theme → Style. (Saving the selection is one small file.)
        let cached = ThemeAppearance(
            name: "Tokyo Night", appearance: "dark", background: RGBA(hex: "#1a1b26")!, foreground: RGBA(hex: "#a9b1d6")!,
            muted: RGBA(hex: "#7a83ad")!, accent: RGBA(hex: "#7aa2f7")!, selectionBackground: RGBA(hex: "#292e42")!,
            selectionForeground: RGBA(hex: "#7aa2f7")!, border: [RGBA(hex: "#414868")!], separator: RGBA(hex: "#24283b")!,
            placeholder: RGBA(hex: "#7a83ad")!, caret: RGBA(hex: "#7aa2f7")!, breadcrumb: RGBA(hex: "#7aa2f7")!,
            hint: RGBA(hex: "#7a83ad")!, error: RGBA(hex: "#f7768e")!, warning: RGBA(hex: "#e0af68")!)
        print("cached external theme switch    \(time(20) { launcher.showForSnapshot(cached.theme(id: "omarchy:x", base: Launcher.defaultTheme)) })")
        _ = launcher.setTheme("kadomo-dark", persist: false)
        print("config reload (sync catalog)    \(time(10) { launcher.reloadAll(sync: true) })")
        print(String(format: "memory footprint                %.1f MB", Launcher.memoryFootprint()))
        return 0
    }
}
