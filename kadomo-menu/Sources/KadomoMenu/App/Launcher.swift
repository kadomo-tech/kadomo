import AppKit
import KadomoMenuCore
import ServiceManagement

/// Owns the resident state: the model, the panel, the sources that feed the
/// catalog, and the configuration. Opening the launcher only resets the model
/// and orders the existing panel front.
final class Launcher: NSObject, NSTextFieldDelegate {
    static let version = "0.1.0"

    let model = LauncherModel()
    let store = ConfigStore()
    let icons = IconCache()
    let panel = LauncherPanel()
    private(set) var view: LauncherView
    private let toast = Toast()
    private(set) var theme: Theme
    private(set) var style: Style
    private var keymap = KeyMap()

    /// Which provider styles the launcher (`settings/active-theme.json`).
    private(set) var activeState = ActiveThemeState()
    /// The optional theme provider (Omarchy), when built in and turned on.
    private(set) var external: ExternalThemeProvider?
    /// Bumped on every theme change, so a slow install never overrides a later choice.
    private(set) var themeGeneration = 0
    /// A theme shown while a theme row is selected; `theme` stays the committed one.
    private var previewing: (itemID: String, theme: Theme)?

    /// Kadomo's built-in default: the fallback of last resort, and the base an
    /// external provider's colors are laid over.
    static let defaultTheme = ThemeLoader.resolve(BuiltinThemes.defaultID, sources: BuiltinThemes.sources).0 ?? Theme()

    /// Catalog sources. Earlier sources win when ids collide.
    private static let sourceOrder = ["builtin", "user", "kadomo", "system", "meta", "external", "apps"]
    private var sources: [String: [Item]] = [:]
    private var generation = 0
    private var rebuildScheduled = false
    private var appScanGeneration = 0

    private var watchers: [FileWatcher] = []
    private var appWatcher: FileWatcher?
    private var reloadWork: DispatchWorkItem?
    private var usageSaveWork: DispatchWorkItem?

    /// Bundle ids of the apps that run now, for rows with `running_app`. Kept up to date by
    /// watching NSWorkspace, so opening the launcher never asks.
    private var runningBundles: Set<String> = []
    private var runningObservation: NSKeyValueObservation?

    /// The app that was frontmost when the launcher opened.
    private var previousApp: NSRunningApplication?
    private var transientMessage: (String, NSColor)?
    private(set) var runFailures: [String] = []
    private var themeErrors: [Diagnostic] = []
    private var hotkeyError: String?

    /// Hotkey press → panel drawn, in milliseconds, for real opens.
    private(set) var openSamples: [Double] = []
    private(set) var readyAt: Date?
    private var benchmarking = false

    override init() {
        let theme = ThemeLoader.resolve(BuiltinThemes.defaultID, sources: BuiltinThemes.sources).0 ?? Theme()
        self.theme = theme
        style = Style(theme: theme, dark: true)
        view = LauncherView(style: style, icons: icons)
        super.init()
    }

    // MARK: Startup

    func start(interactive: Bool = true) {
        store.ensureDefaults()
        loadUsage()
        store.load()
        activeState = ActiveThemeState.load()
        configureExternalProvider()
        applyConfig()

        panel.contentView = view
        view.field.delegate = self
        panel.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        panel.onResignKey = { [weak self] in
            guard let self, self.store.config.closeOnBlur, !self.benchmarking else { return }
            self.hide()
        }
        view.onClick = { [weak self] row in self?.apply(self?.model.handle(.click(row)) ?? .handled) }
        view.onHover = { [weak self] row in
            guard let self, self.store.config.hoverSelects, row != self.model.state.selection else { return }
            self.apply(self.model.handle(.hover(row)))
        }
        icons.onLoaded = { [weak self] in self?.view.refreshVisibleRows() }
        model.dynamicActions = { [weak self] item in self?.runningActions(for: item) ?? [] }

        sources["builtin"] = Categories.home
        refreshStaticSources()
        rebuild(sync: true)
        scanApps()

        guard interactive else { return }
        HotKey.shared.onPress = { [weak self] in self?.toggle(t0: Clock.now()) }
        registerHotKey()
        startWatching()
        observeSystem()
        applyLoginItem()
        external?.start()
        readyAt = Date()
        Log.info("ready in \(Int(coldStartMilliseconds ?? 0)) ms")
    }

    private func observeSystem() {
        runningObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.initial]) { [weak self] workspace, _ in
            let ids = Set(workspace.runningApplications.compactMap(\.bundleIdentifier))
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.runningAppsChanged(ids) } }
        }
        let ws = NSWorkspace.shared.notificationCenter
        DistributedNotificationCenter.default().addObserver(forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restyle() }
        }
        ws.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restyle() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                self.hide()
            }
        }
    }

    private func runningAppsChanged(_ ids: Set<String>) {
        let watched = Set(model.catalog.items.compactMap(\.runningApp))
        let changed = runningBundles.intersection(watched) != ids.intersection(watched)
        runningBundles = ids
        if changed, panel.isVisible { render(animated: false) }
    }

    // MARK: Configuration

    private func applyConfig() {
        let config = store.config
        keymap = KeyMap(config.keys)
        model.config = config
        resolveActiveTheme()
        restyle()
    }

    /// Draws the active provider's theme. A native theme resolves exactly as it
    /// always has; an external one comes from its cached appearance, and when
    /// that is unavailable the Kadomo theme takes over and says why.
    private func resolveActiveTheme() {
        let native = { [store] in store.resolveTheme() }
        let external = self.external.map { provider in
            { (selection: ThemeSelection) -> Result<Theme, ExternalThemeError> in
                provider.id == selection.provider ? provider.theme(for: selection.themeId, base: Launcher.defaultTheme)
                                                  : .failure(ExternalThemeError("no such provider"))
            }
        }
        let resolution = ActiveThemeResolver.resolve(activeState, native: native, external: external)
        themeErrors = resolution.diagnostics
        if let resolved = resolution.theme {
            theme = resolved
        } else {
            Log.error("theme '\(store.config.theme)' is invalid; keeping \(theme.id)")
        }
        // The provider is on but the theme is gone or unreadable: switch to
        // Kadomo for good rather than warn on every reload. A turned-off
        // provider keeps its selection for when it is turned on again.
        if resolution.fellBack, self.external?.id == activeState.activeTheme.provider {
            let lost = activeState.activeTheme.themeId
            selectNative(store.config.theme)
            // Its files may be gone, and the desktop may still be showing them.
            if themesDesktop { DesktopThemes.restoreNative() }
            Log.error("theme \(lost) unavailable; using the Kadomo theme")
            toast.show("Theme \(lost) is unavailable · using the Kadomo theme", style: style, color: style.warning, on: nil)
        }
    }

    /// Creates or drops the optional provider to match config.toml.
    private func configureExternalProvider() {
        let wanted = store.config.omarchyEnabled && ThemeProviders.builtIn
        if wanted, external != nil { return }
        if !wanted { external = nil; return }
        guard let provider = ThemeProviders.make(config: store.config) else { return }
        provider.onChange = { [weak self] in self?.externalChanged() }
        provider.notify = { [weak self] message, isError in self?.show(message: message, error: isError) }
        provider.activate = { [weak self] id in self?.setExternalTheme(id) }
        provider.themeGeneration = { [weak self] in self?.themeGeneration ?? 0 }
        external = provider
        if readyAt != nil { provider.start() }
    }

    /// The provider's rows changed (install, removal, catalog). Its active
    /// theme may have changed or gone, so resolve again.
    private func externalChanged() {
        let hadPreview = previewing != nil
        previewing = nil
        let external = activeState.activeTheme.provider != .kadomo
        if external { resolveActiveTheme() }
        if external || hadPreview { restyle() }
        refreshStaticSources()
        rebuild()
    }

    /// A result from a background job: in the panel when it is open, else a toast.
    private func show(message: String, error: Bool) {
        if error { Log.error(message) }
        if panel.isVisible {
            transientMessage = ((error ? "✕ " : "") + message, error ? style.error : style.muted)
            render()
        } else {
            toast.show((error ? "✕ " : "") + message, style: style, color: error ? style.error : style.foreground, on: nil)
        }
    }

    /// The theme on screen: a preview while one is selected, else the active theme.
    var shownTheme: Theme { previewing?.theme ?? theme }

    var isDark: Bool {
        switch shownTheme.appearance {
        case "light": false
        case "dark": true
        default: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    func restyle() {
        let next = Style(theme: shownTheme, dark: isDark)
        let sizeChanged = next.geometry.iconSize != style.geometry.iconSize
        style = next
        keybindFit = nil
        if sizeChanged { icons.clear() }
        view.apply(style)
        panel.fieldEditor.insertionPointColor = style.caret
        panel.hasShadow = style.effects.shadowRadius > 0
        if panel.isVisible { render(animated: false) }
    }

    /// `sync` installs the new catalog before returning (explicit reloads), so
    /// the CLI's next command already sees it.
    func reloadAll(sync: Bool = false) {
        store.load()
        configureExternalProvider()
        applyConfig()
        registerHotKey()
        refreshStaticSources()
        rebuild(sync: sync)
        scanApps()
        startWatching()
        applyLoginItem()
        Log.info("reloaded: \(store.errors.count) errors, \(store.warnings.count) warnings")
    }

    /// Re-reads config after a burst of file events settles.
    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reloadAll() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func startWatching() {
        watchers.forEach { $0.stop() }
        let paths = Array(Set(store.watchPaths))
        let watcher = FileWatcher(paths: paths) { [weak self] in self?.scheduleReload() }
        watcher.start()
        watchers = [watcher]
    }

    private func registerHotKey() {
        let wanted = store.config.hotkey
        if HotKey.shared.chord == KeyChord.parse(wanted), HotKey.shared.lastError == nil { return }
        hotkeyError = HotKey.shared.register(wanted)
    }

    private func applyLoginItem() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let service = SMAppService.mainApp
        do {
            if store.config.launchAtLogin, service.status != .enabled, service.status != .requiresApproval {
                try service.register()
            } else if !store.config.launchAtLogin, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            Log.error("launch at login: \(error.localizedDescription)")
        }
    }

    var loginItemEnabled: Bool? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return SMAppService.mainApp.status == .enabled
    }

    // MARK: Sources

    private func refreshStaticSources() {
        let userCommands = store.userItems.filter { $0.source == "user" }
        sources["user"] = userCommands
        sources["kadomo"] = store.userItems.filter { $0.source == "kadomo" }
        // With Kadomo's desktop themes, a theme always styles every app, so the
        // items for the launcher's own themes are left out.
        let appearance = SystemProvider.appearance().filter { !kadomoThemes || !SystemProvider.launcherThemeItems.contains($0.id) }
        sources["system"] = SystemProvider.system() + SystemProvider.settings() + appearance
        let active = activeState.activeTheme
        sources["external"] = external?.items(activeThemeID: active.provider == external?.id ? active.themeId : nil) ?? []
        refreshMetaSource()
    }

    /// Whether Kadomo lists its desktop themes under Appearance › Themes. Picking
    /// one there styles every app, the launcher included, so the launcher's own
    /// themes are not offered.
    private var kadomoThemes: Bool {
        store.userItems.contains { $0.source == "kadomo" && $0.parent == Categories.themes && $0.kind != .category }
    }

    /// Themes, keybinds, About, and command helpers: they mirror current state.
    private func refreshMetaSource() {
        var items: [Item] = []
        let launcherThemes = kadomoThemes ? [:] : store.themeSources
        for (id, source) in launcherThemes.sorted(by: { $0.key < $1.key }) {
            let (resolved, diags) = ThemeLoader.resolve(id, sources: store.themeSources)
            let broken = diags.first { $0.severity == .error }
            let order = source.builtin ? 0 : (id == "kadomo" ? -1 : 10)
            items.append(Item(
                id: "theme:\(id)", title: resolved?.name ?? id,
                subtitle: broken.map { "Invalid: \($0.message)" } ?? (source.builtin ? "Built-in theme" : (source.file as NSString).abbreviatingWithTildeInPath),
                parent: Categories.themes, icon: .symbol("swatchpalette"), keywords: ["theme", id],
                action: .builtin("theme.set:\(id)"), keepOpen: true, order: order, source: "meta"))
        }
        // Another provider is styling the launcher: one step back to Kadomo's own.
        if activeState.activeTheme.provider != .kadomo {
            items.append(Item(id: "theme-provider:kadomo", title: "Use Kadomo Theme", subtitle: "Instead of the \(theme.name) theme",
                              parent: Categories.themes, icon: .symbol("arrow.uturn.backward"), keywords: ["theme", "kadomo", "reset", "default"],
                              action: .builtin("theme.provider:kadomo"), keepOpen: true, order: -2, source: "meta"))
        }
        items += SystemProvider.keybinds(keys: keymap, hotkey: store.config.hotkey, prefixes: store.config.prefixes) { [weak self] id in
            self?.model.catalog.item(id)?.title ?? UserCommands.titleFromID(id)
        }
        items += SystemProvider.about(version: Launcher.version, loginEnabled: loginItemEnabled, themeName: theme.name,
                                      itemCount: model.catalog.items.count)
        sources["meta"] = items
    }

    /// Hide and Quit for apps that are running right now.
    private func runningActions(for item: Item) -> [SecondaryAction] {
        guard item.id.hasPrefix("app:") else { return [] }
        let bundleID = String(item.id.dropFirst(4))
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return [] }
        let pid = app.processIdentifier
        return [
            SecondaryAction(app.isHidden ? "Show" : "Hide", .builtin(app.isHidden ? "app.activate:\(pid)" : "app.hide:\(pid)"), icon: .symbol("eye.slash")),
            SecondaryAction("Quit", .builtin("app.quit:\(pid)"), icon: .symbol("xmark.circle"), confirm: true),
        ]
    }

    func scanApps() {
        appScanGeneration += 1
        let gen = appScanGeneration
        let dirs = store.config.appDirectories
        let exclude = Set(store.config.appExclude)
        let iconSize = CGFloat(style.geometry.iconSize)
        Task.detached(priority: .userInitiated) {
            let start = Clock.now()
            let apps = AppProvider.scan(directories: dirs, exclude: exclude)
            let elapsed = Clock.now() - start
            await MainActor.run { [weak self] in
                guard let self, gen == self.appScanGeneration else { return }
                Log.info("scanned \(apps.count) apps in \(Int(elapsed)) ms")
                self.sources["apps"] = apps
                self.rebuild()
                self.icons.prewarm(apps.compactMap { if case .file(let p) = $0.icon { p } else { nil } }, size: iconSize)
                self.watchApps(dirs)
            }
        }
    }

    private func watchApps(_ dirs: [String]) {
        appWatcher?.stop()
        // Coalesced generously: installers touch many files.
        appWatcher = FileWatcher(paths: dirs.map(Paths.expand), latency: 1.5) { [weak self] in self?.scanApps() }
        appWatcher?.start()
    }

    private func scheduleRebuild() {
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.rebuildScheduled = false
            self?.rebuild()
        }
    }

    /// Builds a new catalog snapshot off the main thread (or inline at startup).
    func rebuild(sync: Bool = false) {
        var all = Launcher.sourceOrder.flatMap { sources[$0] ?? [] }
        let aliases = store.config.aliases
        if !aliases.isEmpty {
            var byID: [String: [String]] = [:]
            for (alias, id) in aliases { byID[id, default: []].append(alias) }
            for i in all.indices { if let extra = byID[all[i].id] { all[i].aliases += extra } }
        }
        let hidden = Set(store.config.hidden)
        generation += 1
        let gen = generation
        if sync {
            install(Catalog(items: all, hidden: hidden))
            return
        }
        let items = all
        Task.detached(priority: .userInitiated) {
            let catalog = Catalog(items: items, hidden: hidden)
            await MainActor.run { [weak self] in
                guard let self, gen == self.generation else { return }
                self.install(catalog)
            }
        }
    }

    private func install(_ catalog: Catalog) {
        if !catalog.duplicates.isEmpty { Log.debug("duplicate ids ignored: \(catalog.duplicates.prefix(10))") }
        model.setCatalog(catalog)
        keybindFit = nil
        if panel.isVisible { render() }
    }

    // MARK: Showing

    func toggle(t0: Double = Clock.now()) {
        if panel.isVisible { hide() } else { show(t0: t0) }
    }

    func show(category: String? = nil, query: String = "", t0: Double = Clock.now()) {
        if panel.isVisible {
            if category != nil || !query.isEmpty { model.open(category: category, query: query); render() }
            return
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        transientMessage = nil
        if category != nil || !query.isEmpty { model.open(category: category, query: query) } else { model.reset() }
        if theme.appearance == "auto", style.dark != isDark { restyle() }

        let screen = ScreenLocator.screen(for: store.config.display) ?? NSScreen.main
        view.field.stringValue = model.state.query
        if let screen { fitList(top: ScreenLocator.top(on: screen, style: style), bottom: screen.visibleFrame.minY) }
        let height = view.show(rows: rowData(), selection: currentSelection, crumb: crumbText(), emptyText: model.emptyMessage, footer: footerMessage())
        if let screen { panel.setFrame(ScreenLocator.frame(on: screen, style: style, width: panelWidth, height: height), display: false) }
        view.layoutSubtreeIfNeeded()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(view.field)
        if let editor = view.field.currentEditor() { editor.selectedRange = NSRange(location: (model.state.query as NSString).length, length: 0) }
        panel.displayIfNeeded()
        CATransaction.flush()
        if !benchmarking {
            openSamples.append(Clock.now() - t0)
            if openSamples.count > 500 { openSamples.removeFirst(openSamples.count - 500) }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        cancelPreview()
        // A non-activating panel leaves the previous app frontmost. If something
        // activated us anyway (a click on About, say), hand focus back.
        if NSApp.isActive, let previousApp, !previousApp.isTerminated { previousApp.activate() }
    }

    // MARK: Rendering

    var currentSelection: Int {
        if case .actions = model.state.mode { return model.state.actionSelection }
        return model.state.selection
    }

    func rowData() -> [RowData] {
        let catalog = model.catalog
        if case .actions = model.state.mode, let item = model.actionsItem {
            return model.actions(for: item).map { RowData(title: $0.title, icon: $0.icon, hint: $0.hint) }
        }
        let currentTheme = "theme:\(theme.id)"
        let showSubs = style.effects.showSubtitles
        let input = model.inputText
        let keyReference = model.showsKeyReference
        return model.rows.enumerated().map { n, position in
            let item = catalog.items[position]
            let running = item.runningApp.map(runningBundles.contains) ?? false
            return RowData(title: input.map { "\(item.title): \($0)" } ?? item.title, subtitle: showSubs ? item.subtitle : "", icon: item.icon,
                           hint: running ? "running" : item.hint, chevron: item.kind == .category, favorite: model.favoriteRows.contains(n),
                           info: item.kind == .info, current: item.id == currentTheme || running, keybind: keyReference && item.kind == .info,
                           heading: item.isHeading)
        }
    }

    func crumbText() -> String? {
        if case .actions = model.state.mode, let item = model.actionsItem { return "\(item.title) ›" }
        if let scope = model.prefixScope, let title = model.catalog.item(scope)?.title { return "\(title) ›" }
        let crumbs = model.breadcrumb
        return crumbs.isEmpty ? nil : crumbs.joined(separator: " › ") + " ›"
    }

    func footerMessage() -> (String, NSColor)? {
        if case .confirm(let id, let action) = model.state.mode, let item = model.catalog.item(id) {
            let what = action.flatMap { model.actions(for: item).indices.contains($0) ? model.actions(for: item)[$0].title : nil } ?? item.title
            return ("Press ↩ again to confirm “\(what)” · esc to cancel", style.warning)
        }
        if let transientMessage { return transientMessage }
        if let error = hotkeyError { return ("⚠︎ \(error)", style.warning) }
        let errors = store.errors + themeErrors.filter { $0.severity == .error }
        if let first = errors.first {
            return ("⚠︎ \(first.description)\(errors.count > 1 ? "  (+\(errors.count - 1) more: kadomo-menu config check)" : "")", style.error)
        }
        if model.isGlobalFallback, let category = model.currentCategory {
            return ("No matches in \(category.title) · showing everything", style.muted)
        }
        if style.effects.showFooter {
            let enter = keymap.primary(.enter)?.symbol ?? "↩", tab = keymap.primary(.actions)?.symbol ?? "⇥"
            return ("\(enter) open   \(tab) actions   esc back   ⌘D favorite", style.hint)
        }
        return nil
    }

    /// The field shows the query, except in the actions list, where typing starts a new search.
    var fieldText: String {
        if case .actions = model.state.mode { return "" }
        return model.state.query
    }

    func render(animated: Bool = true) {
        let text = fieldText
        if view.field.stringValue != text {
            view.field.stringValue = text
            if let editor = view.field.currentEditor() { editor.selectedRange = NSRange(location: (text as NSString).length, length: 0) }
        }
        fitList(top: panel.frame.maxY, bottom: (panel.screen?.visibleFrame ?? panel.frame).minY)
        let height = view.show(rows: rowData(), selection: currentSelection, crumb: crumbText(),
                               emptyText: model.emptyMessage, footer: footerMessage())
        resize(to: height, animated: animated)
    }

    /// The Keybinds reference uses short rows, as many as the theme allows and the screen
    /// fits below the panel's top edge (with room for a footer line); the rest scroll.
    func fitList(top: CGFloat, bottom: CGFloat) {
        view.compact = model.showsKeyReference
        let chrome = view.listTop + style.geometry.padding + ceil(style.footerFont.ascender - style.footerFont.descender) + 10
        view.maxListHeight = max(top - bottom - 16 - chrome, style.rowStride)
    }

    /// Wider while the Keybinds reference or Services is open.
    var panelWidth: CGFloat {
        if model.showsKeyReference {
            let fit = measuredKeybindFit()
            view.keyColumnWidth = fit.key
            return fit.width
        }
        return model.showsWideList ? style.wideListWidth : style.width
    }

    /// The widest key, and the panel width that fits every keybind row (key → action  note)
    /// without truncation. Measured from all keybinds, not just the filtered ones, so the panel
    /// doesn't change width while typing. Recomputed when the catalog or theme changes.
    private var keybindFit: (key: CGFloat, width: CGFloat)?

    private func measuredKeybindFit() -> (key: CGFloat, width: CGFloat) {
        if let keybindFit { return keybindFit }
        let fonts = [style.titleFont, style.selectedTitleFont]
        func measure(_ text: String, _ font: NSFont) -> CGFloat { ceil((text as NSString).size(withAttributes: [.font: font]).width) }
        func widest(_ text: String) -> CGFloat { fonts.map { measure(text, $0) }.max() ?? 0 }
        let showSubs = style.effects.showSubtitles
        var key: CGFloat = 0, action: CGFloat = 0
        for item in model.catalog.items where item.kind == .info && item.parent == Categories.keybinds && !item.isHeading {
            key = max(key, widest(item.hint ?? ""))
            var w = widest("→ ") + widest(item.title)
            if showSubs, !item.subtitle.isEmpty { w += style.keyNoteGap + measure(item.subtitle, style.subtitleFont) }
            action = max(action, w)
        }
        let g = style.geometry
        let chrome = 2 * (CGFloat(g.padding) + CGFloat(g.rowInset)) + 4
        let fit = (key: key, width: max(style.width, ceil(key + style.keyColumnGap + action + chrome)))
        keybindFit = fit
        return fit
    }

    private func resize(to height: CGFloat, animated: Bool) {
        var frame = panel.frame
        // The width follows the open list, centered where the panel is; the top edge stays put.
        let visible = panel.screen?.visibleFrame ?? frame
        let width = round(min(panelWidth, visible.width - 32))
        guard abs(frame.height - height) > 0.5 || abs(frame.width - width) > 0.5 else { return }
        let top = frame.maxY
        frame.origin.x = round(frame.midX - width / 2)
        frame.size.width = width
        frame.size.height = height
        frame.origin.y = top - height
        if animated, style.animationDuration > 0, panel.isVisible {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = style.animationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }, completionHandler: { [panel] in MainActor.assumeIsolated { panel.invalidateShadow() } })
        } else {
            panel.setFrame(frame, display: panel.isVisible)
            panel.invalidateShadow()
        }
    }

    // MARK: Input

    func controlTextDidChange(_ obj: Notification) {
        transientMessage = nil
        // The field isn't in single-line mode, so a paste can carry newlines.
        if view.field.stringValue.contains(where: \.isNewline) {
            view.field.stringValue = String(view.field.stringValue.map { $0.isNewline ? " " : $0 })
        }
        apply(model.handle(.query(view.field.stringValue)))
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard let chord = KeyChord(event: event) else { return false }
        if chord == KeyChord("backspace"), view.field.stringValue.isEmpty {
            let effect = model.handle(.backspaceOnEmpty)
            if effect == .passThrough { return true }
            apply(effect)
            return true
        }
        if chord == KeyChord(",", .command) { performBuiltin("config.edit", item: nil); hide(); return true }
        if chord == KeyChord("r", .command) { reloadAll(); transientMessage = ("Reloaded configuration", style.muted); render(); return true }
        guard let command = keymap.command(for: chord) else { return false }
        let caret = view.field.caret
        let effect = model.handle(.command(command, CaretContext(atStart: caret.atStart, atEnd: caret.atEnd, hasSelection: caret.hasSelection)))
        if effect == .passThrough { return false }
        apply(effect)
        return true
    }

    func apply(_ effect: LauncherEffect) {
        defer { syncPreview() }
        switch effect {
        case .handled, .passThrough:
            render()
        case .dismiss:
            hide()
        case .toggledFavorite:
            saveUsageSoon()
            render()
        case .run(let id, let action, let secondary):
            run(itemID: id, action: action, secondary: secondary)
        }
    }

    // MARK: Running

    func run(itemID: String, action: Action, secondary: Int?) {
        guard let item = model.catalog.item(itemID) else { return }
        model.usage.recordRun(itemID, query: model.state.query)
        saveUsageSoon()
        let keepOpen = item.keepOpen && secondary == nil
        let screen = panel.screen
        if case .builtin(let name) = action {
            let stays = performBuiltin(name, item: item)
            if keepOpen || stays { refreshMetaSource(); rebuild(); render() } else { hide() }
            return
        }
        if !keepOpen { hide() }
        Log.info("run \(itemID)")
        Executor.run(action, title: item.title) { [weak self] error in
            guard let self, let error else { return }
            self.report(error, screen: screen)
            if case .openApp = action { self.scanApps() }
        }
    }

    func report(_ message: String, screen: NSScreen?) {
        Log.error(message)
        runFailures.append("\(Date().formatted(date: .omitted, time: .standard))  \(message)")
        if runFailures.count > 20 { runFailures.removeFirst() }
        if panel.isVisible {
            transientMessage = ("✕ \(message)", style.error)
            render()
        } else {
            toast.show("✕ \(message)", style: style, color: style.error, on: screen)
        }
    }

    /// Runs a launcher command. Returns true when the launcher should stay open.
    @discardableResult
    func performBuiltin(_ name: String, item: Item?) -> Bool {
        let (verb, arg) = name.split(separator: ":", maxSplits: 1).map(String.init).splitPair
        switch verb {
        case "reload":
            reloadAll(sync: true)
            transientMessage = ("Reloaded · \(model.catalog.items.count) items", style.muted)
            return true
        case "quit":
            NSApp.terminate(nil)
        case "theme.set":
            setTheme(arg)
            return true
        case "theme.provider":
            // Back to Kadomo's own theme: the one config.toml names.
            setTheme(store.config.theme)
            return true
        case "theme.customize":
            do {
                let (id, path) = try store.customizeTheme(theme.id == "kadomo" || activeState.activeTheme.provider != .kadomo ? BuiltinThemes.defaultID : theme.id, theme: theme)
                try store.setTheme(id)
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                reloadAll()
            } catch {
                report("Could not create a theme file: \(error.localizedDescription)", screen: panel.screen)
            }
        case "folder.themes": openFolder(Paths.themesDirectory)
        case "folder.config": openFolder(Paths.configDirectory)
        case "config.edit":
            Executor.run(.exec(path: "/usr/bin/open", args: ["-t", Paths.configFile]), title: "Edit config") { [weak self] e in
                if let e { self?.report(e, screen: nil) }
            }
        case "login.toggle":
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            } catch {
                report("Launch at login: \(error.localizedDescription)", screen: panel.screen)
            }
            return true
        case "diagnostics.copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(statusText(), forType: .string)
            transientMessage = ("Copied diagnostics", style.muted)
            return true
        case "app.hide-others":
            let keep = previousApp?.processIdentifier
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != keep && app != .current {
                app.hide()
            }
        case "app.show-all":
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular { app.unhide() }
        case "app.hide-front":
            previousApp?.hide()
        case "app.quit-front":
            previousApp?.terminate()
        case "app.activate":
            if let pid = pid_t(arg), let app = NSRunningApplication(processIdentifier: pid) { app.unhide(); app.activate() }
        case "app.hide":
            if let pid = pid_t(arg) { NSRunningApplication(processIdentifier: pid)?.hide() }
        case "app.quit":
            if let pid = pid_t(arg) { NSRunningApplication(processIdentifier: pid)?.terminate() }
        default:
            if let external, verb.hasPrefix(external.id.rawValue + ".") {
                return external.perform(verb, arg, input: model.inputText)
            }
            if verb.hasPrefix("omarchy.") {
                report("The Omarchy integration is turned off ([omarchy] enabled = false in config.toml)", screen: panel.screen)
                return true
            }
            report("Unknown launcher command '\(name)'", screen: panel.screen)
        }
        return false
    }

    private func openFolder(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Switches theme live and saves the choice to config.toml.
    @discardableResult
    func setTheme(_ id: String, persist: Bool = true) -> String? {
        let (resolved, diags) = store.resolveTheme(id)
        guard let resolved else {
            let message = diags.first?.description ?? "unknown theme '\(id)'"
            report(message, screen: panel.screen)
            return message
        }
        previewing = nil
        theme = resolved
        themeErrors = []
        restyle()
        if persist {
            do { try store.setTheme(id) } catch { Log.error("could not save theme: \(error.localizedDescription)") }
            // Leaving another provider's theme: the desktop goes back to Kadomo's too.
            if activeState.activeTheme.provider != .kadomo, themesDesktop {
                DesktopThemes.restoreNative { [weak self] error in
                    if let error { self?.show(message: "Could not restore the Kadomo desktop theme: \(error)", error: true) }
                }
            }
            selectNative(id)
        } else {
            themeGeneration += 1
        }
        refreshStaticSources()
        rebuild()
        return nil
    }

    /// Makes the Kadomo provider active again. Its theme id stays in config.toml.
    private func selectNative(_ id: String) {
        themeGeneration += 1
        guard activeState.activeTheme.provider != .kadomo || activeState.lastSelected["kadomo"] != id else { return }
        activeState.select(ThemeSelection(provider: .kadomo, themeId: id))
        saveActiveState()
    }

    /// Applies one of the external provider's themes and remembers it.
    /// Returns an error message; the current theme stays when it fails.
    @discardableResult
    func setExternalTheme(_ id: String) -> String? {
        guard let external else { return "The Omarchy integration is turned off ([omarchy] enabled = false in config.toml)" }
        switch external.theme(for: id, base: Launcher.defaultTheme) {
        case .failure(let error):
            return "Cannot apply \(id): \(error.message)"
        case .success(let resolved):
            previewing = nil
            theme = resolved
            themeErrors = []
            themeGeneration += 1
            activeState.select(ThemeSelection(provider: external.id, themeId: id))
            saveActiveState()
            restyle()
            refreshStaticSources()
            rebuild()
            applyToDesktop(id)
            return nil
        }
    }

    /// Whether external themes also style every app and the wallpaper.
    var themesDesktop: Bool {
        store.config.omarchyDesktop && store.config.kadomo.mode != "off" && DesktopThemes.available
    }

    /// Hands an external theme to the theme manager so every app, the
    /// wallpaper, and light/dark mode follow it. In the background; the
    /// launcher already shows it.
    private func applyToDesktop(_ id: String) {
        guard themesDesktop, let external, let desktop = external.desktopTheme(for: id) else { return }
        // Installed before its wallpapers were kept, or they failed to download:
        // fetch them now; the theme is applied again when they arrive.
        external.completeForDesktop(id)
        let generation = themeGeneration
        DesktopThemes.applyExternal(folder: desktop.folder, name: desktop.name, label: desktop.label) { [weak self] error in
            guard let self, let error, generation == self.themeGeneration else { return }
            self.show(message: "\(desktop.label) styles the launcher, but not the other apps: \(error)", error: true)
        }
    }

    private func saveActiveState() {
        do { try activeState.save() } catch { Log.error("could not save the active theme: \(error.localizedDescription)") }
    }

    // MARK: Previews

    /// Shows the selected theme row's look while it is selected. Only colors
    /// already in memory; the active theme is not touched until ↩.
    private func syncPreview() {
        var wanted: (String, Theme)?
        if panel.isVisible, case .list = model.state.mode, let item = model.selectedItem, let external,
           item.source == external.id.rawValue, let preview = external.previewTheme(forItem: item.id, base: Launcher.defaultTheme) {
            wanted = (item.id, preview)
        }
        switch (previewing, wanted) {
        case (nil, nil): return
        case (let current?, let next?) where current.itemID == next.0: return
        default:
            previewing = wanted.map { (itemID: $0.0, theme: $0.1) }
            restyle()
        }
    }

    /// Draws `theme` without making it active (snapshots only).
    func showForSnapshot(_ theme: Theme) {
        previewing = nil
        self.theme = theme
        restyle()
    }

    private func cancelPreview() {
        guard previewing != nil else { return }
        previewing = nil
        restyle()
    }

    // MARK: Usage

    private func loadUsage() {
        guard let data = FileManager.default.contents(atPath: Paths.usageFile),
              let usage = try? JSONDecoder().decode(Usage.self, from: data) else { return }
        model.usage = usage
    }

    func saveUsageSoon() {
        usageSaveWork?.cancel()
        let usage = model.usage
        let work = DispatchWorkItem {
            DispatchQueue.global(qos: .utility).async {
                guard let data = try? JSONEncoder().encode(usage) else { return }
                try? FileManager.default.createDirectory(atPath: Paths.stateDirectory, withIntermediateDirectories: true)
                try? data.write(to: URL(fileURLWithPath: Paths.usageFile), options: .atomic)
            }
        }
        usageSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func flushUsage() {
        usageSaveWork?.cancel()
        if let data = try? JSONEncoder().encode(model.usage) { try? data.write(to: URL(fileURLWithPath: Paths.usageFile), options: .atomic) }
    }

    // MARK: Measurements

    var coldStartMilliseconds: Double? {
        guard let readyAt, let started = Launcher.processStart() else { return nil }
        return readyAt.timeIntervalSince(started) * 1000
    }

    static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }

    static func memoryFootprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return s(usage.ru_utime) + s(usage.ru_stime)
    }

    /// Opens and closes the real panel `rounds` times and types a query each
    /// time, timing each step until the frame is committed.
    func benchmarkUI(rounds: Int) -> String {
        benchmarking = true
        defer { benchmarking = false; hide() }
        var opens: [Double] = [], queries: [Double] = [], moves: [Double] = [], hides: [Double] = []
        let wasVisible = panel.isVisible
        if wasVisible { hide() }
        for _ in 0..<rounds {
            let t = Clock.now()
            show(t0: t)
            opens.append(Clock.now() - t)
            for q in ["f", "fi", "fir", "fire", "s", "sa", "saf", "term", "sys"] {
                let tq = Clock.now()
                view.field.stringValue = q
                apply(model.handle(.query(q)))
                panel.displayIfNeeded()
                CATransaction.flush()
                queries.append(Clock.now() - tq)
            }
            for _ in 0..<3 {
                let tm = Clock.now()
                apply(model.handle(.command(.down, CaretContext())))
                panel.displayIfNeeded()
                CATransaction.flush()
                moves.append(Clock.now() - tm)
            }
            let th = Clock.now()
            hide()
            hides.append(Clock.now() - th)
        }
        return [
            "panel open → drawn     \(LatencyStats(opens))",
            "query → results drawn  \(LatencyStats(queries))",
            "selection move → drawn \(LatencyStats(moves))",
            "close                  \(LatencyStats(hides))",
        ].joined(separator: "\n")
    }

    func statusText() -> String {
        var lines: [String] = []
        lines.append("Kadomo Menu \(Launcher.version) · pid \(getpid()) · \(Bundle.main.bundlePath)")
        lines.append("Hotkey: \(HotKey.shared.chord?.symbol ?? store.config.hotkey) \(hotkeyError.map { "— \($0)" } ?? "(registered)")")
        lines.append("Theme: \(theme.name) (\(theme.id)) · provider \(activeState.activeTheme.provider.rawValue)")
        lines.append("Font: \(style.titleFont.fontName) \(Int(style.titleFont.pointSize))pt (theme asks for \"\(theme.font.family)\")")
        var counts: [String: Int] = [:]
        for item in model.catalog.items { counts[item.source, default: 0] += 1 }
        lines.append("Items: \(model.catalog.items.count) — " + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        lines.append("Config: \(Paths.configFile)")
        let diags = store.diagnostics + themeErrors
        lines.append(diags.isEmpty ? "Config check: OK" : "Config check: \(diags.filter { $0.severity == .error }.count) errors, \(diags.filter { $0.severity == .warning }.count) warnings")
        for d in diags.prefix(20) { lines.append("  \(d)") }
        lines.append(String(format: "Memory: %.1f MB footprint · CPU time %.2f s", Launcher.memoryFootprint(), Launcher.cpuSeconds()))
        if let cold = coldStartMilliseconds { lines.append(String(format: "Cold start → ready: %.0f ms", cold)) }
        if !openSamples.isEmpty { lines.append("Hotkey → panel drawn: \(LatencyStats(openSamples))") }
        if let login = loginItemEnabled { lines.append("Launch at login: \(login ? "on" : "off")") }
        if let external {
            let active = activeState.activeTheme
            lines += external.statusLines(activeThemeID: active.provider == external.id ? active.themeId : nil)
        } else {
            lines.append("Omarchy themes: \(ThemeProviders.builtIn ? "turned off in config.toml" : "not built into this binary")")
        }
        if !runFailures.isEmpty {
            lines.append("Recent failures:")
            lines += runFailures.suffix(5).map { "  \($0)" }
        }
        return lines.joined(separator: "\n")
    }
}

private extension Array where Element == String {
    var splitPair: (String, String) { (first ?? "", count > 1 ? self[1] : "") }
}

extension KeyChord {
    init?(event: NSEvent) {
        var mods: Modifiers = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if let named = KeyChord.namedKeyCodes[event.keyCode] {
            self.init(named, mods)
            return
        }
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1 else { return nil }
        self.init(chars, mods)
    }

    static let namedKeyCodes: [UInt16: String] = [
        36: "enter", 76: "enter", 48: "tab", 53: "escape", 51: "backspace", 117: "delete", 123: "left", 124: "right",
        125: "down", 126: "up", 115: "home", 119: "end", 116: "pageup", 121: "pagedown", 49: "space",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
    ]
}
