import Foundation
import Testing
@testable import KadomoMenuCore

@Suite struct ConfigTests {
    @Test func defaultsWhenEmpty() {
        let (config, diags) = ConfigLoader.parse("", file: "config.toml")
        #expect(diags.isEmpty)
        #expect(config == AppConfig())
    }

    @Test func readsEverySection() {
        let (c, diags) = ConfigLoader.parse("""
        theme = "kadomo-terminal"
        hotkey = "cmd+shift+space"
        display = "mouse"
        show_recent = 3
        favorites = ["app:com.apple.Safari"]
        [search]
        max_results = 20
        [search.prefixes]
        ":" = "settings"
        [keys]
        down = ["down", "ctrl+j"]
        [aliases]
        ff = "app:org.mozilla.firefox"
        [apps]
        extra_directories = ["~/Applications/Setapp"]
        [kadomo]
        mode = "off"
        [[command]]
        title = "Hello"
        exec = "/bin/echo"
        """, file: "config.toml")
        #expect(diags.isEmpty, "\(diags)")
        #expect(c.theme == "kadomo-terminal")
        #expect(c.hotkey == "cmd+shift+space")
        #expect(c.display == .mouse)
        #expect(c.recentOnHome == 3)
        #expect(c.maxResults == 20)
        #expect(c.prefixes == [":": "settings"])
        #expect(KeyMap(c.keys).command(for: KeyChord("j", .control)) == .down)
        #expect(c.aliases["ff"] == "app:org.mozilla.firefox")
        #expect(c.appDirectories.last == "~/Applications/Setapp")
        #expect(c.kadomo.mode == "off")
        #expect(c.commands.count == 1)
    }

    @Test func reportsTypeErrorsUnknownKeysAndBadChords() {
        let (c, diags) = ConfigLoader.parse("""
        hotkey = "hyper+space"
        show_recent = 9
        close_on_blur = "yes"
        thme = "typo"
        """, file: "config.toml")
        let text = diags.map(\.description)
        #expect(c.hotkey == "option+space", "invalid values keep defaults")
        #expect(text.contains("config.toml:1: error: 'hotkey': not a key chord like \"option+space\""))
        #expect(text.contains { $0.contains("'show_recent': must be between 0 and 5") })
        #expect(text.contains { $0.contains(":3: error: 'close_on_blur' must be true or false, found string") })
        #expect(text.contains("config.toml:4: warning: unknown key 'thme'"))
    }

    @Test func malformedFileIsOneError() {
        let (c, diags) = ConfigLoader.parse("theme = ", file: "config.toml")
        #expect(c == AppConfig())
        #expect(diags.count == 1 && diags[0].severity == .error)
    }

    @Test func keyChordParsing() {
        #expect(KeyChord.parse("option+space") == KeyChord("space", .option))
        #expect(KeyChord.parse("Cmd+Shift+K") == KeyChord("k", [.command, .shift]))
        #expect(KeyChord.parse("ctrl+return") == KeyChord("enter", .control))
        #expect(KeyChord.parse("hyper+k") == nil)
        #expect(KeyChord.parse("cmd+") == nil)
        #expect(KeyChord("enter", .command).symbol == "⌘↩")
    }
}

@Suite struct ThemeTests {
    @Test(arguments: Array(BuiltinThemes.all.keys))
    func builtinsResolveCleanly(_ id: String) {
        let (theme, diags) = ThemeLoader.resolve(id, sources: BuiltinThemes.sources)
        #expect(theme != nil)
        #expect(diags.isEmpty, "\(diags)")
    }

    @Test func builtinsAreReadable() {
        for id in BuiltinThemes.all.keys {
            let theme = ThemeLoader.resolve(id, sources: BuiltinThemes.sources).0!
            for dark in [true, false] {
                let c = theme.colors(dark: dark)
                #expect(RGBA.contrast(c.foreground, c.background) >= 7, "\(id) body text")
                #expect(RGBA.contrast(c.selectionForeground, c.selectionBackground) >= 4.5, "\(id) selection")
                #expect(RGBA.contrast(c.muted, c.background) >= 3, "\(id) muted")
            }
        }
    }

    @Test func inheritanceOverridesOnlyGivenTokens() {
        var sources = BuiltinThemes.sources
        sources["mine"] = ThemeSource(id: "mine", text: """
        extends = "kadomo-dark"
        [colors]
        accent = "#ff79c6"
        [geometry]
        width = 700
        """, file: "mine.toml", builtin: false)
        let (theme, diags) = ThemeLoader.resolve("mine", sources: sources)
        #expect(diags.isEmpty)
        #expect(theme?.colors.accent == RGBA(hex: "#ff79c6"))
        #expect(theme?.geometry.width == 700)
        #expect(theme?.geometry.rowHeight == 48, "inherited from kadomo-dark")
        #expect(theme?.colors.border == .gradient([RGBA(hex: "#b26cf3")!, RGBA(hex: "#5ea8f5")!], angle: -45))
    }

    @Test func invalidThemeIsRejectedWithErrors() {
        var sources = BuiltinThemes.sources
        sources["bad"] = ThemeSource(id: "bad", text: """
        [colors]
        accent = "pink"
        [geometry]
        width = 10
        """, file: "bad.toml", builtin: false)
        let (theme, diags) = ThemeLoader.resolve("bad", sources: sources)
        #expect(theme == nil)
        #expect(diags.contains { $0.message.contains("'colors.accent': not a color") })
        #expect(diags.contains { $0.message.contains("'geometry.width': must be between") })
    }

    @Test func cyclesAndUnknownParents() {
        var sources: [String: ThemeSource] = [:]
        sources["a"] = ThemeSource(id: "a", text: "extends = \"b\"", file: "a.toml", builtin: false)
        sources["b"] = ThemeSource(id: "b", text: "extends = \"a\"", file: "b.toml", builtin: false)
        sources["c"] = ThemeSource(id: "c", text: "extends = \"nope\"", file: "c.toml", builtin: false)
        #expect(ThemeLoader.resolve("a", sources: sources).0 == nil)
        #expect(ThemeLoader.resolve("c", sources: sources).1.first?.message.contains("unknown theme 'nope'") == true)
    }

    @Test func colorParsing() {
        #expect(RGBA(hex: "#fff") == RGBA(1, 1, 1))
        #expect(RGBA(hex: "#00000080")?.a ?? 0 > 0.5)
        #expect(RGBA(hex: "red") == nil)
        #expect(RGBA(hex: "#12345") == nil)
    }
}

@Suite struct UserCommandTests {
    @Test func parsesCommandsCategoriesAndActions() {
        let (items, diags) = UserCommands.parseFile("""
        [[category]]
        id = "development/projects"
        title = "Projects"

        [[command]]
        id = "kadomo"
        title = "Open Kadomo Project"
        category = "development/projects"
        keywords = ["repo"]
        exec = "/usr/bin/open"
        args = ["-a", "Terminal", "~/Code/kadomo"]
        [[command.action]]
        title = "Reveal"
        open = "~/Code/kadomo"

        [[command]]
        title = "Deploy Site"
        category = "work/ops/deploy"
        shell = "make deploy"
        confirm = true
        """, file: "dev.toml", source: "user")
        #expect(diags.isEmpty, "\(diags)")
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        #expect(byID["development/projects"]?.parent == Categories.development)
        let open = byID["cmd:kadomo"]!
        #expect(open.action == .exec(path: "/usr/bin/open", args: ["-a", "Terminal", "~/Code/kadomo"]))
        #expect(open.secondary.first?.title == "Reveal")
        let deploy = byID["cmd:deploy-site"]!
        #expect(deploy.confirm)
        #expect(deploy.action == .shell(script: "make deploy", shell: "/bin/zsh"))
        // Missing intermediate categories are created.
        #expect(byID["work/ops/deploy"]?.parent == "work/ops")
        #expect(byID["work/ops"]?.parent == "work")
    }

    @Test func rejectsAmbiguousOrMissingActions() {
        let (items, diags) = UserCommands.parseFile("""
        [[command]]
        title = "Two"
        exec = "/bin/ls"
        url = "https://example.com"
        [[command]]
        title = "None"
        [[command]]
        exec = "/bin/ls"
        """, file: "bad.toml", source: "user")
        #expect(items.isEmpty)
        #expect(diags.count == 3)
        #expect(diags.allSatisfy { $0.severity == .error })
    }

    @Test func userCommandsAreSearchableInCatalog() {
        let (items, _) = UserCommands.parseFile("""
        [[command]]
        title = "Edit Dotfiles"
        aliases = ["dots"]
        exec = "/usr/bin/true"
        """, file: "c.toml", source: "user")
        let catalog = Catalog(items: Categories.home + items)
        let hits = catalog.index.search("dots", limit: 5)
        #expect(hits.first.map { catalog.items[$0.index].id } == "cmd:edit-dotfiles")
        #expect(catalog.children(of: Catalog.rootID).map { catalog.items[$0].id } == [Categories.commands])
    }
}

@Suite struct CatalogTests {
    @Test func duplicatesKeepFirstSource() {
        let c = Catalog(items: Categories.home + [
            Item(id: "app:x", title: "First", kind: .app, parent: Categories.apps),
            Item(id: "app:x", title: "Second", kind: .app, parent: Categories.apps),
        ])
        #expect(c.item("app:x")?.title == "First")
        #expect(c.duplicates == ["app:x"])
    }

    @Test func hiddenItemsAndEmptyCategoriesDisappear() {
        let c = Catalog(items: Categories.home + [Item(id: "a", title: "A", parent: Categories.system)], hidden: ["a"])
        #expect(c.children(of: Catalog.rootID).isEmpty)
    }

    @Test func pathsAndContainment() {
        let c = Catalog(items: Categories.home + [Item(id: "t", title: "T", parent: Categories.themes)])
        #expect(c.path(to: Categories.themes) == [Categories.appearance, Categories.themes])
        #expect(c.isInside(c.position(of: "t")!, Categories.appearance))
        #expect(!c.isInside(c.position(of: "t")!, Categories.system))
    }

    @Test func concurrentSnapshotsAreIndependent() async {
        // Build catalogs on many tasks while searching the current one.
        let base = Catalog(items: SyntheticRegistry.items(2000))
        await withTaskGroup(of: Int.self) { group in
            for n in 0..<8 {
                group.addTask {
                    let c = Catalog(items: SyntheticRegistry.items(1000 + n * 100, seed: UInt64(n)))
                    return c.index.search("fire", limit: 10).count
                }
                group.addTask { base.index.search("studio", limit: 10).count }
            }
            for await count in group { #expect(count > 0) }
        }
    }
}

@Suite struct UsageTests {
    @Test func frecencyIsBoundedAndDecays() {
        var u = Usage()
        let now = 1_000_000.0
        for _ in 0..<1000 { u.recordRun("a", query: "", now: now) }
        #expect(u.frecency("a", now: now) == 50)
        let later = u.frecency("a", now: now + 86_400 * 60)
        #expect(later < 25 && later < u.frecency("a", now: now + 86_400 * 7))
        #expect(u.boost("a", query: "", now: now) <= 99)
    }

    @Test func learnsQueryPicks() {
        var u = Usage()
        u.recordRun("app:firefox", query: "F ")
        #expect(u.picks["f"] == "app:firefox")
        #expect(u.boost("app:firefox", query: "f") > u.boost("app:firefox", query: "g"))
    }

    @Test func codableRoundTrip() throws {
        var u = Usage()
        u.recordRun("x", query: "q")
        u.toggleFavorite("x")
        let data = try JSONEncoder().encode(u)
        #expect(try JSONDecoder().decode(Usage.self, from: data) == u)
    }
}

@Suite struct BenchTests {
    @Test func searchIsFastOnTenThousandItems() {
        let r = SearchBenchmark.run(count: 10_000, rounds: 5)
        #expect(r.items == 10_040)
        // Unoptimized debug builds are ~20x slower; this only catches pathological
        // regressions. Release numbers come from `kadomo-menu benchmark`.
        #expect(r.search.p95 < 250, "\(r.search)")
    }

    @Test func percentiles() {
        let s = LatencyStats((1...100).map(Double.init))
        #expect(s.p50 == 51 || s.p50 == 50)
        #expect(s.p99 >= 99)
    }

    @Test func ipcRoundTrip() {
        let data = IPCCodec.encode(IPCRequest(args: ["theme", "set", "kadomo-dark"]))
        #expect(IPCCodec.decode(IPCRequest.self, data)?.args == ["theme", "set", "kadomo-dark"])
    }
}
