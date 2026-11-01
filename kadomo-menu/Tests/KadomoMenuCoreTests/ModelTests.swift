import Testing
@testable import KadomoMenuCore

/// Keyboard state transitions of the launcher.
@Suite struct ModelTests {
    static func catalog() -> Catalog {
        Catalog(items: Categories.home + [
            Item(id: "app:firefox", title: "Firefox", kind: .app, parent: Categories.apps, action: .openApp(path: "/Applications/Firefox.app", newInstance: false)),
            Item(id: "app:terminal", title: "Terminal", kind: .app, parent: Categories.apps,
                 secondary: [SecondaryAction("Open New Window", .exec(path: "/usr/bin/true", args: []))]),
            Item(id: "sys:sleep", title: "Sleep", parent: Categories.system, action: .exec(path: "/usr/bin/pmset", args: ["sleepnow"])),
            Item(id: "sys:restart", title: "Restart…", parent: Categories.system, action: .builtin("restart"), confirm: true),
            Item(id: "theme:dark", title: "Kadomo Dark", parent: Categories.themes, action: .builtin("theme.set:kadomo-dark"), keepOpen: true),
            Item(id: "key:enter", title: "Run", kind: .info, parent: Categories.keybinds),
        ])
    }

    func model(_ configure: (inout AppConfig) -> Void = { _ in }) -> LauncherModel {
        var config = AppConfig()
        configure(&config)
        return LauncherModel(catalog: Self.catalog(), config: config)
    }

    func cmd(_ c: KeyCommand, atEnd: Bool = true) -> LauncherEvent { .command(c, CaretContext(atStart: !atEnd, atEnd: atEnd)) }

    func titles(_ m: LauncherModel) -> [String] { m.rows.map { m.catalog.items[$0].title } }

    @Test func homeShowsOnlyNonEmptyCategoriesInOrder() {
        let m = model()
        // Services and About are empty here and hidden; Settings sits under System.
        #expect(titles(m) == ["Apps", "Appearance", "Keybinds", "System"])
    }

    @Test func keybindsOpenTheWideKeyReference() {
        let m = model()
        #expect(!m.showsKeyReference)
        for _ in 0..<2 { m.handle(cmd(.down)) } // Keybinds
        m.handle(cmd(.enter))
        #expect(m.showsKeyReference)
        // Searching inside keeps it; a search that falls back to everything does not.
        m.handle(.query("run"))
        #expect(m.showsKeyReference)
        m.handle(.query("firefox"))
        #expect(m.isGlobalFallback)
        #expect(!m.showsKeyReference)
        m.handle(.query(""))
        m.handle(cmd(.close))
        #expect(!m.showsKeyReference)
    }

    @Test func servicesOpenWide() {
        let catalog = Catalog(items: Categories.home + [
            Item.category("services/wm", "OmniWM", icon: "rectangle", parent: Categories.services),
            Item(id: "cmd:start", title: "Start", parent: "services/wm", action: .exec(path: "/usr/bin/true", args: [])),
            Item(id: "sys:sleep", title: "Sleep", parent: Categories.system, action: .exec(path: "/usr/bin/pmset", args: ["sleepnow"])),
        ])
        let m = LauncherModel(catalog: catalog, config: AppConfig())
        #expect(titles(m) == ["Services", "System"])
        #expect(!m.showsWideList)
        m.handle(cmd(.enter)) // Services
        #expect(m.showsWideList)
        m.handle(cmd(.enter)) // OmniWM
        #expect(m.state.path == [Categories.services, "services/wm"])
        #expect(m.showsWideList, "a service inside Services stays wide")
        m.handle(.query("sleep"))
        #expect(m.isGlobalFallback)
        #expect(!m.showsWideList)
        m.handle(.query(""))
        m.handle(cmd(.close))
        m.handle(cmd(.close))
        #expect(!m.showsWideList)
    }

    @Test func enterOpensCategoryAndEscapeGoesBack() {
        let m = model()
        for _ in 0..<3 { m.handle(cmd(.down)) } // System
        #expect(m.handle(cmd(.enter)) == .handled)
        #expect(m.state.path == [Categories.system])
        #expect(titles(m) == ["Restart…", "Sleep"])
        #expect(m.handle(cmd(.close)) == .handled)
        #expect(m.state.path.isEmpty)
        #expect(m.state.selection == 3, "selection restored to System")
        #expect(m.handle(cmd(.close)) == .dismiss)
    }

    @Test func rightEntersOnlyWhenCaretAtEnd() {
        let m = model()
        #expect(m.handle(cmd(.forward)) == .handled)
        #expect(m.state.path == [Categories.apps])
        m.handle(.query("ter"))
        #expect(m.handle(cmd(.forward, atEnd: false)) == .passThrough)
    }

    @Test func leftEditsTextWhenQueryPresent() {
        let m = model()
        m.handle(cmd(.enter))
        m.handle(.query("fi"))
        #expect(m.handle(cmd(.back)) == .passThrough)
        m.handle(.query(""))
        #expect(m.handle(cmd(.back)) == .handled)
        #expect(m.state.path.isEmpty)
    }

    @Test func escapeClearsQueryBeforeNavigating() {
        let m = model()
        m.handle(cmd(.enter))
        m.handle(.query("fire"))
        #expect(m.handle(cmd(.close)) == .handled)
        #expect(m.state.query.isEmpty)
        #expect(m.state.path == [Categories.apps])
    }

    @Test func escapeClosesFromCategoryWhenConfigured() {
        let m = model { $0.escapeNavigatesBack = false }
        m.handle(cmd(.enter))
        #expect(m.handle(cmd(.close)) == .dismiss)
    }

    @Test func typingSearchesScopedThenGlobalFallback() {
        let m = model()
        for _ in 0..<3 { m.handle(cmd(.down)) }; m.handle(cmd(.enter)) // System
        m.handle(.query("sle"))
        #expect(titles(m) == ["Sleep"])
        #expect(!m.isGlobalFallback)
        m.handle(.query("fire"))
        #expect(titles(m) == ["Firefox"])
        #expect(m.isGlobalFallback)
    }

    @Test func enterRunsActionAndSearchResultCategoryJumps() {
        let m = model()
        m.handle(.query("fire"))
        #expect(m.handle(cmd(.enter)) == .run(itemID: "app:firefox", action: .openApp(path: "/Applications/Firefox.app", newInstance: false), secondary: nil))
        m.handle(.query("themes"))
        #expect(m.selectedItem?.id == Categories.themes)
        m.handle(cmd(.enter))
        #expect(m.state.path == [Categories.appearance, Categories.themes])
        #expect(m.state.query.isEmpty)
    }

    @Test func confirmFlow() {
        let m = model()
        m.handle(.query("restart"))
        #expect(m.handle(cmd(.enter)) == .handled)
        #expect(m.state.mode == .confirm(itemID: "sys:restart", action: nil))
        #expect(m.handle(cmd(.close)) == .handled)
        #expect(m.state.mode == .list)
        m.handle(cmd(.enter))
        #expect(m.handle(cmd(.enter)) == .run(itemID: "sys:restart", action: .builtin("restart"), secondary: nil))
    }

    @Test func actionsModeAndAlternate() {
        let m = model()
        m.handle(.query("terminal"))
        #expect(m.handle(cmd(.actions)) == .handled)
        #expect(m.state.mode == .actions(itemID: "app:terminal"))
        #expect(m.actions(for: m.selectedItem!).map(\.title) == ["Open New Window", "Add to Favorites"])
        m.handle(cmd(.down))
        #expect(m.handle(cmd(.enter)) == .toggledFavorite("app:terminal"))
        #expect(m.usage.isFavorite("app:terminal"))
        #expect(m.state.mode == .list)
        #expect(m.handle(cmd(.alternate)) == .run(itemID: "app:terminal", action: .exec(path: "/usr/bin/true", args: []), secondary: 0))
        m.handle(cmd(.actions))
        #expect(m.handle(cmd(.close)) == .handled)
        #expect(m.state.mode == .list)
    }

    @Test func favoritesShowOnHome() {
        let m = model()
        m.handle(.query("sleep"))
        #expect(m.handle(cmd(.favorite)) == .toggledFavorite("sys:sleep"))
        m.handle(.query(""))
        #expect(titles(m).first == "Sleep")
        #expect(m.favoriteRows == [0])
    }

    @Test func backspaceOnEmptyPops() {
        let m = model()
        m.handle(cmd(.enter))
        #expect(m.handle(.backspaceOnEmpty) == .handled)
        #expect(m.state.path.isEmpty)
        #expect(m.handle(.backspaceOnEmpty) == .passThrough)
    }

    @Test func selectionWrapsAndClamps() {
        let m = model()
        m.handle(cmd(.up))
        #expect(m.state.selection == m.rows.count - 1)
        m.handle(cmd(.down))
        #expect(m.state.selection == 0)
        m.handle(cmd(.last))
        m.handle(.query("fire"))
        #expect(m.state.selection == 0)
    }

    @Test func prefixScopesSearch() {
        let m = model()
        m.handle(.query("!"))
        #expect(m.prefixScope == Categories.system)
        #expect(titles(m) == ["Restart…", "Sleep"])
        m.handle(.query("@ term"))
        #expect(titles(m) == ["Terminal"])
    }

    @Test func infoRowsDoNothing() {
        let m = model()
        m.handle(.query("run"))
        #expect(m.selectedItem?.kind == .info)
        #expect(m.handle(cmd(.enter)) == .handled)
    }

    @Test func selectionStepsOverHeadings() {
        func heading(_ id: String, _ title: String, _ order: Int) -> Item {
            var item = Item(id: id, title: title, kind: .info, parent: Categories.keybinds, order: order, searchable: false)
            item.isHeading = true
            return item
        }
        let catalog = Catalog(items: Categories.home + [
            heading("key:heading-a", "Getting around", 1),
            Item(id: "key:focus", title: "Focus", kind: .info, parent: Categories.keybinds, order: 2),
            heading("key:heading-b", "Workspaces", 3),
            Item(id: "key:go", title: "Go to workspace", kind: .info, parent: Categories.keybinds, order: 4),
        ])
        let m = LauncherModel(catalog: catalog, config: AppConfig())
        m.open(category: Categories.keybinds)
        #expect(m.selectedItem?.title == "Focus")
        m.handle(cmd(.down))
        #expect(m.selectedItem?.title == "Go to workspace")
        m.handle(cmd(.down)) // wraps past the first heading
        #expect(m.selectedItem?.title == "Focus")
        m.handle(cmd(.up))
        #expect(m.selectedItem?.title == "Go to workspace")
        m.handle(cmd(.first))
        #expect(m.selectedItem?.title == "Focus")
        m.handle(.hover(2))
        #expect(m.selectedItem?.title == "Focus")
        #expect(m.handle(.click(0)) == .handled)
        #expect(m.selectedItem?.title == "Focus")
        // A search finds rows, never headings.
        m.handle(.query("workspace"))
        #expect(titles(m) == ["Go to workspace"])
    }

    @Test func catalogSwapKeepsPathAndSelection() {
        let m = model()
        m.handle(cmd(.enter))
        m.handle(cmd(.down)) // Terminal
        m.setCatalog(Self.catalog())
        #expect(m.state.path == [Categories.apps])
        #expect(m.selectedItem?.id == "app:terminal")
    }

    @Test func rapidTypingIsConsistent() {
        let m = model()
        var q = ""
        for ch in "firefox" { q.append(ch); m.handle(.query(q)) }
        for _ in 0..<7 { q.removeLast(); m.handle(.query(q)) }
        #expect(m.state.query.isEmpty)
        #expect(titles(m) == ["Apps", "Appearance", "Keybinds", "System"])
    }

    @Test func inputCategoryKeepsItsRowsWhileTyping() {
        let items = Categories.home + [
            Item(id: "git", title: "Install from Git", kind: .category, parent: Categories.appearance, takesInput: true),
            Item(id: "git:install", title: "Install from Git URL", parent: "git", action: .builtin("omarchy.install-git"), keepOpen: true),
            Item(id: "sys:sleep", title: "Sleep", parent: Categories.system, action: .exec(path: "/usr/bin/pmset", args: ["sleepnow"])),
        ]
        let m = LauncherModel(catalog: Catalog(items: items))
        m.open(category: "git")
        #expect(m.inputText == nil)
        m.handle(.query("https://github.com/a/sleep-theme"))
        #expect(titles(m) == ["Install from Git URL"], "typing does not search, even for words that match elsewhere")
        #expect(!m.isGlobalFallback)
        #expect(m.inputText == "https://github.com/a/sleep-theme")
        #expect(m.handle(cmd(.enter)) == .run(itemID: "git:install", action: .builtin("omarchy.install-git"), secondary: nil))
        #expect(m.state.query == "https://github.com/a/sleep-theme", "the action can still read the text")
        #expect(m.handle(cmd(.close)) == .handled)
        #expect(m.state.query.isEmpty && m.state.path == ["appearance", "git"])
    }

    @Test func prefixSearchStillWorksInsideAnInputCategory() {
        let items = Categories.home + [
            Item(id: "git", title: "Install from Git", kind: .category, parent: Categories.appearance, takesInput: true),
            Item(id: "git:install", title: "Install from Git URL", parent: "git"),
            Item(id: "sys:sleep", title: "Sleep", parent: Categories.system),
        ]
        let m = LauncherModel(catalog: Catalog(items: items))
        m.open(category: "git")
        m.handle(.query("!sle"))
        #expect(titles(m) == ["Sleep"])
        #expect(m.inputText == nil)
    }
}
