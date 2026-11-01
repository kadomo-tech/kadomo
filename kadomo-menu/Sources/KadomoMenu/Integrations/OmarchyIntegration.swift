#if canImport(KadomoOmarchy)
import AppKit
import KadomoMenuCore
import KadomoOmarchy

/// Appearance › Omarchy Themes: browse, install, preview, apply, update, and
/// remove Omarchy themes. Everything here goes through `OmarchyThemeService`;
/// the launcher sees only `ExternalThemeProvider`. Network, Git, and file work
/// runs off the main thread; menus and previews come from memory.
final class OmarchyIntegration: ExternalThemeProvider {
    let id = ThemeProviderID.omarchy
    var onChange: (() -> Void)?
    var notify: ((String, Bool) -> Void)?
    var activate: ((String) -> String?)?
    var themeGeneration: (() -> Int)?

    static let root = OmarchyCategory.root
    static let installed = OmarchyCategory.installed
    static let official = root + "/official"
    static let community = root + "/community"
    static let git = OmarchyCategory.git

    private let service = OmarchyThemeService()
    private var records: [OmarchyThemeRecord] = []
    private var problems: [String] = []
    private var cache = OmarchyCatalogCache()
    private var loaded = false
    /// Running jobs: key → what the status row says.
    private var busy: [String: String] = [:]
    private var catalogErrors: [String: String] = [:]
    /// Preview themes by item id (nil: that item has no usable palette).
    private var previews: [String: Theme?] = [:]

    // MARK: Lifecycle

    func start() {
        let service = self.service
        Task.detached(priority: .utility) {
            service.library.clearStaging()
            service.library.revalidateOutdated()
            let (records, problems) = service.library.records()
            let cache = service.loadCache()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.loaded = true
                self.cache = cache
                self.setRecords(records, problems)
            }
        }
    }

    private func setRecords(_ records: [OmarchyThemeRecord], _ problems: [String]) {
        self.records = records
        self.problems = problems
        previews = [:]
        onChange?()
    }

    private func record(_ id: String) -> OmarchyThemeRecord? {
        records.first { $0.id == id }
    }

    // MARK: Themes

    func theme(for themeID: String, base: Theme) -> Result<Theme, ExternalThemeError> {
        // Before the library has loaded (at startup) this reads one metadata file.
        let appearance: Result<ThemeAppearance, ExternalThemeError> =
            loaded ? (record(themeID).map { .success($0.appearance) } ?? .failure(ExternalThemeError("it is not installed")))
                   : service.appearance(id: themeID)
        return appearance.map { $0.theme(id: "omarchy:\(themeID)", base: base) }
    }

    func desktopTheme(for themeID: String) -> (folder: String, name: String, label: String)? {
        guard let rec = record(themeID) ?? service.library.record(id: themeID) else { return nil }
        return (service.library.themeDirectory(rec.slug), "omarchy-" + rec.slug, rec.name)
    }

    func completeForDesktop(_ themeID: String) {
        guard let rec = record(themeID), (rec.files ?? 1) < OmarchyLibrary.filesVersion, rec.source.kind != .local, busy["update"] == nil else { return }
        update([themeID], message: "Fetching \(rec.name)'s wallpapers…")
    }

    func previewTheme(forItem itemID: String, base: Theme) -> Theme? {
        if let cached = previews[itemID] { return cached }
        var theme: Theme?
        if let id = installedID(forItem: itemID), let rec = record(id) {
            theme = rec.appearance.theme(id: "preview:\(id)", base: base)
        } else if let entry = catalogEntry(forItem: itemID), !entry.colors.isEmpty {
            let palette = OmarchyAdapter.palette(fromCatalogColors: entry.colors)
            theme = (try? OmarchyAdapter.normalize(name: entry.name, palette: palette))?.theme(id: "preview:\(entry.slug)", base: base)
        }
        previews[itemID] = theme
        return theme
    }

    /// The installed theme a row stands for, if it is installed.
    private func installedID(forItem itemID: String) -> String? {
        if itemID.hasPrefix("omarchy-theme:") { return String(itemID.dropFirst("omarchy-theme:".count)) }
        if itemID.hasPrefix("omarchy-official:") { return "official:" + itemID.dropFirst("omarchy-official:".count) }
        if itemID.hasPrefix("omarchy-community:"), let entry = catalogEntry(forItem: itemID) { return installID(entry) }
        return nil
    }

    private func catalogEntry(forItem itemID: String) -> OmarchyCommunityTheme? {
        let themes = cache.community?.themes ?? []
        if itemID.hasPrefix("omarchy-community:") {
            let slug = itemID.dropFirst("omarchy-community:".count)
            return themes.first { $0.slug == slug }
        }
        if itemID.hasPrefix("omarchy-official:") {
            let name = itemID.dropFirst("omarchy-official:".count)
            return themes.first { $0.builtin && $0.slug == name }
        }
        return nil
    }

    /// The Omarchy release a retired official theme comes from, per the catalog.
    private func retiredRelease(_ name: String) -> String? {
        cache.community?.themes.first { $0.builtin && $0.slug == name }.flatMap { service.officialRelease(of: $0) }
    }

    /// The id a catalog entry gets once installed.
    private func installID(_ entry: OmarchyCommunityTheme) -> String? {
        if entry.builtin { return "official:" + entry.slug }
        guard let loc = try? OmarchyGitLocation.parse(entry.repository) else { return nil }
        return OmarchySource(kind: .git, location: loc.repository, ref: loc.ref, subpath: loc.subpath).themeID
    }

    // MARK: Menu

    func items(activeThemeID: String?) -> [Item] {
        let root = Self.root
        var items: [Item] = [
            .category(root, "Omarchy Themes", subtitle: "Themes from the Omarchy community", icon: "swatchpalette.fill",
                      parent: Categories.appearance, order: 0, keywords: ["omarchy", "theme", "community"]),
            Item(id: Self.installed, title: "Installed", subtitle: "\(records.count) Omarchy theme\(records.count == 1 ? "" : "s")",
                 kind: .category, parent: root, icon: .symbol("checkmark.circle"), keywords: ["omarchy"], order: 0, source: "omarchy"),
            Item(id: Self.official, title: "Official Themes", subtitle: "From github.com/omacom/omarchy", kind: .category, parent: root,
                 icon: .symbol("star"), keywords: ["omarchy", "browse"], order: 1, source: "omarchy"),
            Item(id: Self.community, title: "Community Themes", subtitle: "From omarchytheme.com", kind: .category, parent: root,
                 icon: .symbol("person.3"), keywords: ["omarchy", "browse", "gallery"], order: 2, source: "omarchy"),
            Item(id: Self.git, title: "Install from Git", subtitle: "Any public https:// repository", kind: .category, parent: root,
                 icon: .symbol("arrow.down.circle"), keywords: ["omarchy", "install", "url", "repository"], order: 3, source: "omarchy",
                 takesInput: true),
            Item(id: "omarchy-git:install", title: "Install from Git URL", subtitle: "Type or paste an https:// URL, then press ↩",
                 parent: Self.git, icon: .symbol("arrow.down.circle"), action: .builtin("omarchy.install-git"), keepOpen: true,
                 source: "omarchy", searchable: false),
            Item(id: "omarchy:import", title: "Import Local Theme…", subtitle: "A folder with a colors.toml", parent: root,
                 icon: .symbol("folder.badge.plus"), keywords: ["omarchy", "import", "folder"], action: .builtin("omarchy.import-local"),
                 order: 4, source: "omarchy"),
        ]
        if !records.isEmpty {
            items.append(Item(id: "omarchy:update-all", title: "Check for Updates", subtitle: "Fetch newer versions of installed themes",
                              parent: root, icon: .symbol("arrow.triangle.2.circlepath"), keywords: ["omarchy", "update"],
                              action: .builtin("omarchy.update-all"), keepOpen: true, order: 5, source: "omarchy"))
        }
        if activeThemeID != nil {
            items.append(Item(id: "omarchy:use-kadomo", title: "Use Kadomo Theme", subtitle: "Switch back to Kadomo's own theme",
                              parent: root, icon: .symbol("arrow.uturn.backward"), keywords: ["kadomo", "theme", "reset"],
                              action: .builtin("theme.provider:kadomo"), keepOpen: true, order: -5, source: "omarchy"))
        }
        if let status = statusRow() { items.append(status) }

        let installedIDs = Set(records.map(\.id))
        for rec in records {
            var subtitle = rec.source.summary
            if rec.compatibilityStatus == .stale { subtitle += " · using its last good colors" }
            if let error = rec.lastError { subtitle += " · \(error)" }
            items.append(Item(
                id: "omarchy-theme:\(rec.id)", title: rec.name, subtitle: subtitle, parent: Self.installed,
                icon: .symbol("swatchpalette"), keywords: ["omarchy", "theme", rec.author ?? ""].filter { !$0.isEmpty },
                action: .builtin("omarchy.apply:\(rec.id)"),
                secondary: [
                    SecondaryAction("Apply", .builtin("omarchy.apply:\(rec.id)"), icon: .symbol("checkmark")),
                    SecondaryAction("Update", .builtin("omarchy.update:\(rec.id)"), icon: .symbol("arrow.triangle.2.circlepath")),
                    SecondaryAction("Show in Finder", .revealInFinder(service.library.themeDirectory(rec.slug)), icon: .symbol("folder")),
                    SecondaryAction("Remove", .builtin("omarchy.remove:\(rec.id)"), icon: .symbol("trash"), confirm: true),
                ],
                hint: rec.id == activeThemeID ? "current" : nil, keepOpen: true, order: rec.id == activeThemeID ? -1 : 0, source: "omarchy"))
        }

        if let official = cache.official {
            for name in official.themes {
                let id = "official:\(name)"
                let have = installedIDs.contains(id)
                items.append(Item(
                    id: "omarchy-official:\(name)", title: OmarchyNames.display(name),
                    subtitle: have ? "Installed · ↩ applies it" : "↩ installs and applies it", parent: Self.official,
                    icon: .symbol("swatchpalette"), keywords: ["omarchy", "official", name],
                    action: .builtin(have ? "omarchy.apply:\(id)" : "omarchy.install-official:\(name)"),
                    hint: id == activeThemeID ? "current" : (have ? "installed" : nil), keepOpen: true, source: "omarchy"))
            }
        }
        // Official themes Omarchy has since dropped, from the release the
        // community catalog names.
        let current = Set(cache.official?.themes ?? [])
        for entry in cache.community?.themes ?? [] where entry.builtin && !current.contains(entry.slug) && cache.official != nil {
            guard let release = service.officialRelease(of: entry) else { continue }
            let id = "official:\(entry.slug)"
            let have = installedIDs.contains(id)
            items.append(Item(
                id: "omarchy-official:\(entry.slug)", title: entry.name,
                subtitle: "From Omarchy \(release), no longer in Omarchy · " + (have ? "Installed · ↩ applies it" : "↩ installs and applies it"),
                parent: Self.official, icon: .symbol("swatchpalette"), keywords: ["omarchy", "official", entry.slug, release],
                action: .builtin(have ? "omarchy.apply:\(id)" : "omarchy.install-official:\(entry.slug)"),
                hint: id == activeThemeID ? "current" : (have ? "installed" : nil), keepOpen: true, order: 1, source: "omarchy"))
        }
        items.append(Item(id: "omarchy:refresh-official", title: cache.official == nil ? "Load Official Themes" : "Refresh List",
                          subtitle: cache.official.map { "Fetched \($0.fetchedAt.formatted(date: .abbreviated, time: .shortened)) · \($0.branch)" }
                              ?? "Lists the themes in Omarchy's repository",
                          parent: Self.official, icon: .symbol("arrow.clockwise"), action: .builtin("omarchy.refresh-official"),
                          keepOpen: true, order: cache.official == nil ? -1 : 1000, source: "omarchy", searchable: false))

        if let community = cache.community {
            for entry in community.themes {
                let id = installID(entry)
                let have = id.map(installedIDs.contains) ?? false
                var subtitle = [entry.author.map { "by \($0)" }, entry.description].compactMap { $0 }.joined(separator: " · ")
                if entry.builtin { subtitle = "Official · " + subtitle }
                var secondary = [SecondaryAction("Open Repository", .openURL(entry.repository), icon: .symbol("safari"))]
                if let id, have { secondary.insert(SecondaryAction("Apply", .builtin("omarchy.apply:\(id)"), icon: .symbol("checkmark")), at: 0) }
                items.append(Item(
                    id: "omarchy-community:\(entry.slug)", title: entry.name, subtitle: subtitle, parent: Self.community,
                    icon: .symbol("swatchpalette"), keywords: ["omarchy", entry.author ?? "", entry.slug].filter { !$0.isEmpty },
                    action: .builtin(have ? "omarchy.apply:\(id ?? "")" : "omarchy.install-community:\(entry.slug)"),
                    secondary: secondary, hint: id != nil && id == activeThemeID ? "current" : (have ? "installed" : nil),
                    keepOpen: true, source: "omarchy"))
            }
        }
        items.append(Item(id: "omarchy:refresh-community", title: cache.community == nil ? "Load Community Themes" : "Refresh List",
                          subtitle: cache.community.map { "\($0.themes.count) themes · fetched \($0.fetchedAt.formatted(date: .abbreviated, time: .shortened))" }
                              ?? "omarchytheme.com, a third-party catalog",
                          parent: Self.community, icon: .symbol("arrow.clockwise"), action: .builtin("omarchy.refresh-community"),
                          keepOpen: true, order: cache.community == nil ? -1 : 1000, source: "omarchy", searchable: false))
        return items
    }

    private func statusRow() -> Item? {
        let text: String, icon: String
        if let job = busy.values.sorted().first {
            text = job + (busy.count > 1 ? " (+\(busy.count - 1) more)" : "")
            icon = "hourglass"
        } else if let problem = catalogErrors.values.sorted().first ?? problems.first {
            text = problem
            icon = "exclamationmark.triangle"
        } else {
            return nil
        }
        return Item(id: "omarchy:status", title: text, kind: .info, parent: Self.root, icon: .symbol(icon), order: -10,
                    source: "omarchy", searchable: false)
    }

    // MARK: Commands

    func perform(_ verb: String, _ arg: String, input: String?) -> Bool {
        switch verb {
        case "omarchy.apply":
            if let error = activate?(arg) { notify?(error, true) }
        case "omarchy.install-official":
            let revision = cache.official?.themes.contains(arg) == true ? cache.official?.revision : nil
            let fallback = retiredRelease(arg)
            install("official:\(arg)", "Installing \(OmarchyNames.display(arg))…") { s in
                try await s.installOfficial(arg, revision: revision, fallback: fallback)
            }
        case "omarchy.install-community":
            guard let entry = cache.community?.themes.first(where: { $0.slug == arg }) else {
                notify?("No community theme '\(arg)'; refresh the list", true)
                break
            }
            install(installID(entry) ?? arg, "Installing \(entry.name)…") { s in try await s.installCommunity(entry) }
        case "omarchy.install-git":
            guard let url = input, !url.isEmpty else {
                notify?("Type or paste an https:// Git URL, then press ↩", true)
                break
            }
            do {
                let loc = try OmarchyGitLocation.parse(url)
                install("git:\(loc.repository)", "Installing \(loc.themeName)…") { s in try s.installFromGit(url) }
            } catch {
                notify?(error.message, true)
            }
        case "omarchy.import-local":
            chooseFolder()
            return false
        case "omarchy.update":
            update([arg])
        case "omarchy.update-all":
            update(records.map(\.id))
        case "omarchy.remove":
            let name = record(arg)?.name ?? arg
            run("remove:\(arg)", "Removing \(name)…", apply: false) { s in
                try s.removeTheme(id: arg)
                return ("Removed \(name)", nil)
            }
        case "omarchy.refresh-official":
            refreshCatalog(official: true)
        case "omarchy.refresh-community":
            refreshCatalog(official: false)
        default:
            notify?("Unknown Omarchy command '\(verb)'", true)
        }
        return true
    }

    private func install(_ key: String, _ message: String, _ work: @escaping @Sendable (OmarchyThemeService) async throws -> OmarchyThemeRecord) {
        run(key, message, apply: true) { s in
            let rec = try await work(s)
            let warning = rec.warnings.isEmpty ? "" : " (\(rec.warnings.count) note\(rec.warnings.count == 1 ? "" : "s"): kadomo-menu omarchy list)"
            return ("Installed \(rec.name)\(warning)", rec.id)
        }
    }

    private func update(_ ids: [String], message: String? = nil) {
        guard !ids.isEmpty else { return }
        run("update", message ?? (ids.count == 1 ? "Checking \(record(ids[0])?.name ?? ids[0]) for updates…" : "Checking \(ids.count) themes for updates…"), apply: true) { s in
            var updated: [String] = [], failed: [String] = []
            let active = ActiveThemeState.load().activeTheme
            var reapply: String?
            for id in ids {
                do {
                    if case .updated(let rec) = try await s.updateTheme(id: id) {
                        updated.append(rec.name)
                        // The theme on screen changed: show the new version everywhere.
                        if active.provider == .omarchy, active.themeId == id { reapply = id }
                    }
                } catch {
                    failed.append("\(s.library.record(id: id)?.name ?? id): \(error)")
                }
            }
            if !failed.isEmpty { throw OmarchyInstallError("update failed for " + failed.joined(separator: "; ")) }
            return (updated.isEmpty ? "Omarchy themes are up to date" : "Updated " + updated.joined(separator: ", "), reapply)
        }
    }

    private func refreshCatalog(official: Bool) {
        let key = official ? "official" : "community"
        run("catalog:\(key)", official ? "Loading official themes…" : "Loading community themes…", apply: false) { s in
            if official {
                let listing = try await s.discoverOfficialThemes()
                return ("\(listing.themes.count) official themes", nil)
            }
            let listing = try await s.discoverCommunityThemes()
            return ("\(listing.themes.count) community themes", nil)
        }
    }

    /// Runs a job off the main thread, then reloads the library and the cache
    /// and, for installs, applies the theme unless the user picked another
    /// theme in the meantime.
    private func run(_ key: String, _ message: String, apply: Bool,
                     _ work: @escaping @Sendable (OmarchyThemeService) async throws -> (String, String?)) {
        guard busy[key] == nil else { notify?("Already working on it: \(message)", false); return }
        busy[key] = message
        onChange?()
        let generation = themeGeneration?() ?? 0
        let service = self.service
        Task.detached(priority: .userInitiated) {
            let outcome: Result<(String, String?), Error>
            do { outcome = .success(try await work(service)) } catch { outcome = .failure(error) }
            let (records, problems) = service.library.records()
            let cache = service.loadCache()
            let failure: String? = if case .failure(let e) = outcome { (e as? OmarchyInstallError)?.message ?? e.localizedDescription } else { nil }
            let success: (String, String?)? = try? outcome.get()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.busy[key] = nil
                self.cache = cache
                if key.hasPrefix("catalog:") { self.catalogErrors[key] = failure.map { "Could not refresh: \($0)" } }
                self.setRecords(records, problems)
                if let failure {
                    self.notify?(failure, true)
                } else if let (text, themeID) = success {
                    if apply, let themeID, (self.themeGeneration?() ?? 0) == generation {
                        if let error = self.activate?(themeID) { self.notify?(error, true); return }
                    }
                    self.notify?(text, false)
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Import an Omarchy Theme"
        panel.message = "Choose a theme folder with a colors.toml. Kadomo copies its colors and preview; nothing in it runs."
        panel.prompt = "Import"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = false
        NSApp.activate()
        panel.begin { [weak self] response in
            guard response == .OK, let path = panel.url?.path else { return }
            MainActor.assumeIsolated {
                self?.install("local:\(path)", "Importing \((path as NSString).lastPathComponent)…") { s in try s.importLocalTheme(path) }
            }
        }
    }

    // MARK: Status and CLI

    func statusLines(activeThemeID: String?) -> [String] {
        var lines = ["Omarchy themes: \(records.count) installed in \((service.library.root as NSString).abbreviatingWithTildeInPath) · adapter \(OmarchyAdapter.version)"]
        if let o = cache.official { lines.append("  official list: \(o.themes.count) themes at \(o.branch)@\(o.revision.prefix(7)), fetched \(o.fetchedAt.formatted())") }
        if let c = cache.community { lines.append("  community list: \(c.themes.count) themes, fetched \(c.fetchedAt.formatted())") }
        for rec in records where rec.compatibilityStatus != .compatible || rec.lastError != nil {
            lines.append("  \(rec.id): \(rec.compatibilityStatus.rawValue)\(rec.lastError.map { " · \($0)" } ?? "")")
        }
        lines += (problems + catalogErrors.values.sorted()).map { "  \($0)" }
        lines += busy.values.sorted().map { "  running: \($0)" }
        return lines
    }

    static let cliHelp = """
    usage: kadomo-menu omarchy <command>
      status                         installed count, catalogs, problems
      list                           installed Omarchy themes (* active)
      official [--refresh]           themes in Omarchy's repository
      community [<text>] [--refresh] themes in the omarchytheme.com catalog
      install <name|slug|https-url>  install, then apply (--no-apply to only install)
      import <folder>                copy a local theme folder in, then apply
      check <folder>                 would this folder install? nothing is copied
      apply <id>                     make an installed theme the active one
      update [<id>]                  fetch newer versions (all when no id)
      remove <id>                    delete an installed theme
    """

    func handleCLI(_ args: [String]) async -> IPCResponse {
        let sub = args.first ?? "status"
        let rest = Array(args.dropFirst())
        let service = self.service
        func reload() async {
            let (records, problems) = await Task.detached { service.library.records() }.value
            cache = service.loadCache()
            loaded = true
            setRecords(records, problems)
        }
        func offMain<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async -> Result<T, OmarchyInstallError> {
            await Task.detached(priority: .userInitiated) { () -> Result<T, OmarchyInstallError> in
                do { return .success(try await work()) } catch {
                    return .failure((error as? OmarchyInstallError) ?? OmarchyInstallError(error.localizedDescription))
                }
            }.value
        }
        func installThenApply(_ work: @escaping @Sendable () async throws -> OmarchyThemeRecord) async -> IPCResponse {
            switch await offMain(work) {
            case .failure(let error):
                await reload()
                return .fail(error.message)
            case .success(let rec):
                await reload()
                var out = "installed \(rec.name) (\(rec.id))"
                if !rec.warnings.isEmpty { out += "\n" + rec.warnings.map { "  note: \($0)" }.joined(separator: "\n") }
                if !rest.contains("--no-apply") {
                    if let error = activate?(rec.id) { return .fail(out + "\n" + error) }
                    out += "\napplied"
                }
                return .ok(out)
            }
        }

        switch sub {
        case "status":
            if !loaded { await reload() }
            return .ok(statusLines(activeThemeID: nil).joined(separator: "\n"))
        case "list":
            await reload()
            let active = await MainActor.run { ActiveThemeState.load().activeTheme }
            if records.isEmpty { return .ok("no Omarchy themes installed (kadomo-menu omarchy official, then install <name>)") }
            return .ok(records.map { rec in
                let mark = active.provider == .omarchy && active.themeId == rec.id ? "*" : " "
                var line = "\(mark) \(rec.id.padding(toLength: 44, withPad: " ", startingAt: 0)) \(rec.name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(rec.compatibilityStatus.rawValue)"
                if let rev = rec.sourceRevision { line += " @\(rev.prefix(7))" }
                if let e = rec.lastError { line += "  (\(e))" }
                return line + rec.warnings.map { "\n    note: \($0)" }.joined()
            }.joined(separator: "\n"))
        case "official":
            if rest.contains("--refresh") || cache.official == nil {
                if case .failure(let m) = await offMain({ try await service.discoverOfficialThemes() }) {
                    if cache.official == nil { return .fail("could not list official themes: \(m.message)") }
                }
                await reload()
            }
            guard let official = cache.official else { return .fail("no official list") }
            let have = Set(records.map(\.id))
            let retired = (cache.community?.themes ?? []).filter { $0.builtin && !official.themes.contains($0.slug) }
                .compactMap { e in service.officialRelease(of: e).map { (e.slug, $0) } }
            return .ok((official.themes.map { "\(have.contains("official:\($0)") ? "i" : " ") \($0)" }
                        + retired.map { "\(have.contains("official:\($0.0)") ? "i" : " ") \($0.0)  (Omarchy \($0.1); no longer in Omarchy)" })
                .joined(separator: "\n"))
        case "community":
            if rest.contains("--refresh") || cache.community == nil {
                if case .failure(let m) = await offMain({ try await service.discoverCommunityThemes() }) {
                    if cache.community == nil { return .fail("the community catalog is unavailable: \(m.message)") }
                }
                await reload()
            }
            let query = rest.first { !$0.hasPrefix("--") }?.lowercased()
            let themes = (cache.community?.themes ?? []).filter { t in
                guard let query else { return true }
                return [t.slug, t.name, t.author ?? "", t.description ?? ""].contains { $0.lowercased().contains(query) }
            }
            return .ok(themes.map { "\($0.slug.padding(toLength: 28, withPad: " ", startingAt: 0)) \($0.name)\($0.author.map { " · by \($0)" } ?? "")\($0.builtin ? " · official" : "")" }
                .joined(separator: "\n"))
        case "install":
            guard let what = rest.first(where: { !$0.hasPrefix("--") }) else { return .fail("usage: kadomo-menu omarchy install <name|slug|https-url>", status: 2) }
            if what.lowercased().hasPrefix("https://") {
                return await installThenApply { try service.installFromGit(what) }
            }
            if let entry = cache.community?.themes.first(where: { $0.slug == what }), !entry.builtin {
                return await installThenApply { try await service.installCommunity(entry) }
            }
            let revision = cache.official?.themes.contains(what) == true ? cache.official?.revision : nil
            let fallback = retiredRelease(what)
            return await installThenApply { try await service.installOfficial(what, revision: revision, fallback: fallback) }
        case "import":
            guard let path = rest.first(where: { !$0.hasPrefix("--") }) else { return .fail("usage: kadomo-menu omarchy import <folder>", status: 2) }
            return await installThenApply { try service.importLocalTheme(path) }
        case "check":
            guard let path = rest.first else { return .fail("usage: kadomo-menu omarchy check <folder>", status: 2) }
            switch service.checkCompatibility(path) {
            case .failure(let e): return .fail("incompatible: \(e.message)")
            case .success(let (appearance, warnings)):
                return .ok((["compatible: \(appearance.appearance), background \(appearance.background.hexString), accent \(appearance.accent.hexString)"]
                            + warnings.map { "  note: \($0)" }).joined(separator: "\n"))
            }
        case "apply":
            guard let id = rest.first else { return .fail("usage: kadomo-menu omarchy apply <id>", status: 2) }
            if !loaded { await reload() }
            if let error = activate?(id) { return .fail(error) }
            return .ok("applied \(record(id)?.name ?? id)")
        case "update":
            let ids = rest.first.map { [$0] } ?? records.map(\.id)
            var lines: [String] = [], failed = false
            for id in ids {
                switch await offMain({ try await service.updateTheme(id: id) }) {
                case .success(.updated(let rec)): lines.append("updated \(rec.name) @\(rec.sourceRevision?.prefix(7) ?? "?")")
                case .success(.upToDate): lines.append("\(id): up to date")
                case .success(.notApplicable): lines.append("\(id): imported from a folder; import it again to update")
                case .failure(let m): lines.append("\(id): \(m.message) (the installed version stays)"); failed = true
                }
            }
            await reload()
            if let active = activeIDIfOmarchy(), ids.contains(active) { _ = activate?(active) }
            return IPCResponse(status: failed ? 1 : 0, output: lines.isEmpty ? "nothing installed" : lines.joined(separator: "\n"))
        case "remove":
            guard let id = rest.first else { return .fail("usage: kadomo-menu omarchy remove <id>", status: 2) }
            let result = await offMain { try service.removeTheme(id: id) }
            await reload()
            if case .failure(let m) = result { return .fail(m.message) }
            return .ok("removed \(id)")
        case "help", "-h", "--help":
            return .ok(Self.cliHelp)
        default:
            return .fail(Self.cliHelp, status: 2)
        }
    }

    private func activeIDIfOmarchy() -> String? {
        let active = ActiveThemeState.load().activeTheme
        return active.provider == .omarchy ? active.themeId : nil
    }
}
#endif
