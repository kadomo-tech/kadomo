import Foundation

/// Turns `[[command]]` and `[[category]]` tables (from config.toml or any
/// file in a commands directory) into catalog items, and `[[keybind]]` tables
/// (commands files only) into rows of the Keybinds reference.
///
/// ```toml
/// [[command]]
/// id = "edit-dotfiles"
/// title = "Edit Dotfiles"
/// category = "development"
/// exec = "/usr/bin/open"
/// args = ["-a", "Zed", "~/dotfiles"]
///
/// [[keybind]]
/// heading = "Getting around"
///
/// [[keybind]]
/// key = "OPT + ARROWS"
/// title = "Focus left / right / up / down"
/// ```
public enum UserCommands {
    public static let idPrefix = "cmd:"
    public static let keybindPrefix = "key:"

    public static func parseFile(_ text: String, file: String, source: String) -> ([Item], [Diagnostic]) {
        let table: TOMLTable
        do { table = try TOML.parse(text) } catch {
            return ([], [Diagnostic(.error, file, line: error.line, error.message)])
        }
        let r = TableReader(table, file: file)
        let commands = r.tables("command") ?? []
        let categories = r.tables("category") ?? []
        let keybinds = r.tables("keybind") ?? []
        let (items, diags) = parse(commands: commands, categories: categories, file: file, source: source)
        let (keys, keyDiags) = parse(keybinds: keybinds, file: file, source: source)
        return (items + keys, r.finish() + diags + keyDiags)
    }

    /// Read-only rows under Keybinds: the key shows as the hint, the title says what it does.
    /// They sort before the launcher's own keys. A table with only `heading` (and `order`) is a
    /// section label: it is never selected and never found by a search.
    public static func parse(keybinds: [TOMLTable], file: String, source: String) -> ([Item], [Diagnostic]) {
        var items: [Item] = []
        var diagnostics: [Diagnostic] = []
        for (n, t) in keybinds.enumerated() {
            let r = TableReader(t, file: file, prefix: "keybind[\(n)]")
            if let heading = r.string("heading") {
                guard !heading.isEmpty, t.line(of: "key") == nil, t.line(of: "title") == nil else {
                    diagnostics.append(Diagnostic(.error, file, line: t.line(of: "heading"), "[[keybind]] #\(n + 1) has a heading, so it takes no key or title"))
                    _ = r.finish()
                    continue
                }
                var item = Item(id: keybindPrefix + "heading-" + (r.string("id") ?? slug(heading)), title: heading, kind: .info,
                                parent: Categories.keybinds, order: r.int("order") ?? 100 + n, source: source, searchable: false)
                item.isHeading = true
                items.append(item)
                diagnostics += r.finish()
                continue
            }
            guard let key = r.string("key"), !key.isEmpty, let title = r.string("title"), !title.isEmpty else {
                diagnostics.append(Diagnostic(.error, file, line: t.line(of: "key") ?? t.line(of: "title"), "[[keybind]] #\(n + 1) needs a key and a title"))
                _ = r.finish()
                continue
            }
            items.append(Item(
                id: keybindPrefix + (r.string("id") ?? slug(key + " " + title)), title: title, subtitle: r.string("subtitle") ?? "",
                kind: .info, parent: Categories.keybinds, icon: .symbol(r.string("icon") ?? "keyboard"),
                keywords: [key] + (r.strings("keywords") ?? []), hint: key, order: r.int("order") ?? 100 + n, source: source
            ))
            diagnostics += r.finish()
        }
        return (items, diagnostics)
    }

    public static func parse(commands: [TOMLTable], categories: [TOMLTable], file: String, source: String) -> ([Item], [Diagnostic]) {
        var items: [Item] = []
        var diagnostics: [Diagnostic] = []
        var defined = Set<String>()

        for (n, t) in categories.enumerated() {
            let r = TableReader(t, file: file, prefix: "category[\(n)]")
            guard let id = r.string("id"), !id.isEmpty else {
                diagnostics.append(Diagnostic(.error, file, "[[category]] #\(n + 1) needs an id"))
                continue
            }
            let parentFromPath = id.contains("/") ? String(id[..<id.lastIndex(of: "/")!]) : Catalog.rootID
            let title = r.string("title") ?? titleFromID(id)
            var item = Item.category(id, title, subtitle: r.string("subtitle") ?? "", icon: r.string("icon") ?? "folder",
                                     parent: r.string("parent") ?? parentFromPath, order: r.int("order") ?? 100,
                                     keywords: r.strings("keywords") ?? [])
            item.source = source
            item.runningApp = r.string("running_app")
            items.append(item)
            defined.insert(id)
            diagnostics += r.finish()
        }

        for (n, t) in commands.enumerated() {
            let r = TableReader(t, file: file, prefix: "command[\(n)]")
            let line = t.line(of: "id") ?? t.line(of: "title")
            guard let title = r.string("title"), !title.isEmpty else {
                diagnostics.append(Diagnostic(.error, file, line: line, "[[command]] #\(n + 1) needs a title"))
                _ = r.finish()
                continue
            }
            let rawID = r.string("id") ?? slug(title)
            guard let action = parseAction(r, what: "command '\(title)'") else {
                diagnostics += r.diagnostics
                continue
            }
            let category = r.string("category") ?? Catalog.rootID
            var secondary: [SecondaryAction] = []
            for (m, a) in (r.tables("action") ?? []).enumerated() {
                let ar = TableReader(a, file: file, prefix: "command[\(n)].action[\(m)]")
                guard let atitle = ar.string("title") else {
                    diagnostics.append(Diagnostic(.error, file, line: line, "secondary action #\(m + 1) of '\(title)' needs a title"))
                    continue
                }
                if let act = parseAction(ar, what: "action '\(atitle)'") {
                    secondary.append(SecondaryAction(atitle, act, icon: ar.string("icon").map(IconRef.symbol) ?? .none,
                                                     hint: nil, confirm: ar.bool("confirm") ?? false))
                }
                diagnostics += ar.finish()
            }
            let icon: IconRef = if let s = r.string("icon") { s.hasPrefix("/") || s.hasPrefix("~") ? .file(Paths.expand(s)) : .symbol(s) }
                else if let g = r.string("glyph") { .glyph(g) } else { .symbol("terminal") }
            let confirm = r.bool("confirm") ?? false
            var hotkey: KeyChord?
            if let v = r.string("hotkey") {
                // A shortcut runs at once, so nothing would ask for the second Enter.
                if confirm { r.error("hotkey", "a command with confirm can't have one") }
                else if let chord = KeyChord.parse(v) { hotkey = chord }
                else { r.error("hotkey", "not a key chord like \"option+shift+m\"") }
            }
            var item = Item(
                id: idPrefix + rawID, title: title, subtitle: r.string("subtitle") ?? r.string("description") ?? "",
                kind: .action, parent: category, alsoIn: r.strings("also_in") ?? [], icon: icon,
                keywords: r.strings("keywords") ?? [], aliases: r.strings("aliases") ?? [], action: action,
                secondary: secondary, hint: r.string("hint") ?? hotkey?.symbol, confirm: confirm,
                keepOpen: r.bool("keep_open") ?? false, order: r.int("order") ?? 0, source: source,
                runningApp: r.string("running_app")
            )
            item.hotkey = hotkey
            items.append(item)
            diagnostics += r.finish()

            // A command may name a nested category that nobody defined: create it.
            var path = category
            while path.contains("/"), !defined.contains(path), !builtinCategoryIDs.contains(path) {
                let parent = String(path[..<path.lastIndex(of: "/")!])
                var cat = Item.category(path, titleFromID(path), icon: "folder", parent: parent, order: 100)
                cat.source = source
                items.append(cat)
                defined.insert(path)
                path = parent
            }
        }
        return (items, diagnostics)
    }

    static let builtinCategoryIDs = Set(Categories.home.map(\.id))

    /// Exactly one of exec, shell, url, open, app.
    static func parseAction(_ r: TableReader, what: String) -> Action? {
        let exec = r.string("exec")
        let args = r.strings("args")
        let shell = r.string("shell")
        let shellPath = r.string("shell_path")
        let url = r.string("url")
        let open = r.string("open")
        let app = r.string("app")
        let given = [exec, shell, url, open, app].compactMap { $0 }
        guard given.count == 1 else {
            r.diagnostics.append(Diagnostic(.error, r.file, line: r.table.line(of: "title"),
                                            given.isEmpty ? "\(what) needs one of exec, shell, url, open, or app"
                                                          : "\(what) has more than one of exec, shell, url, open, app"))
            return nil
        }
        if args != nil, exec == nil {
            r.error("args", "only applies with exec")
        }
        if let exec { return .exec(path: exec, args: args ?? []) }
        if let shell { return .shell(script: shell, shell: shellPath ?? "/bin/zsh") }
        if let url {
            guard URL(string: url)?.scheme != nil else { r.error("url", "not a URL with a scheme"); return nil }
            return .openURL(url)
        }
        if let open { return .openPath(Paths.expand(open)) }
        if let app { return .openApp(path: app, newInstance: false) }
        return nil
    }

    public static func titleFromID(_ id: String) -> String {
        let last = id.split(separator: "/").last.map(String.init) ?? id
        return last.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    public static func slug(_ s: String) -> String {
        Fold.string(s).map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
    }
}
