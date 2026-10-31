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
        print(failures == 0 ? "PASS self-test" : "FAIL self-test: \(failures) failing")
        return failures == 0 ? 0 : 1
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
        print("config reload (sync catalog)    \(time(10) { launcher.reloadAll(sync: true) })")
        print(String(format: "memory footprint                %.1f MB", Launcher.memoryFootprint()))
        return 0
    }
}
