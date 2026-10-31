import Testing
@testable import KadomoMenuCore

/// Keyboard state transitions of the launcher.
@Suite struct ModelTests {
    static func catalog() -> Catalog {
        Catalog(items: Categories.home + [
            Item(id: "app:firefox", title: "Firefox", kind: .app, parent: Categories.apps, action: .openApp(path: "/Applications/Firefox.app", newInstance: false)),
            Item(id: "app:terminal", title: "Terminal", kind: .app, parent: Categories.apps, alsoIn: [Categories.development],
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
        // Windows, Workspaces, Settings, Commands, About are empty here and hidden.
        #expect(titles(m) == ["Apps", "System", "Appearance", "Development", "Keybinds"])
    }

    @Test func enterOpensCategoryAndEscapeGoesBack() {
        let m = model()
        m.handle(cmd(.down)) // System
        #expect(m.handle(cmd(.enter)) == .handled)
        #expect(m.state.path == [Categories.system])
        #expect(titles(m) == ["Restart…", "Sleep"])
        #expect(m.handle(cmd(.close)) == .handled)
        #expect(m.state.path.isEmpty)
        #expect(m.state.selection == 1, "selection restored to System")
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
        m.handle(cmd(.down)); m.handle(cmd(.enter)) // System
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
        #expect(titles(m) == ["Apps", "System", "Appearance", "Development", "Keybinds"])
    }
}
