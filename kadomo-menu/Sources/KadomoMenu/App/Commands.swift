import AppKit
import KadomoMenuCore

/// Requests from the `kadomo-menu` CLI, executed inside the running app.
extension Launcher {
    func handle(_ request: IPCRequest) async -> IPCResponse {
        var args = request.args
        guard !args.isEmpty else { return .fail("no command", status: 2) }
        let command = args.removeFirst()

        switch command {
        case "ping":
            return .ok("pong")

        case "open":
            let category = option("--category", in: args) ?? option("--path", in: args)
            let query = option("--query", in: args) ?? ""
            if let category, model.catalog.item(category) == nil { return .fail("no category '\(category)'. Run `kadomo-menu commands list --categories`", status: 2) }
            show(category: category, query: query)
            return .ok()

        case "toggle":
            toggle()
            return .ok()

        case "close":
            hide()
            return .ok()

        case "reload":
            reloadAll(sync: true)
            let errors = store.errors.count, warnings = store.warnings.count
            let detail = store.diagnostics.map { "  \($0)" }.joined(separator: "\n")
            return IPCResponse(status: errors > 0 ? 1 : 0,
                               output: "reloaded: \(model.catalog.items.count) items, \(errors) errors, \(warnings) warnings" + (detail.isEmpty ? "" : "\n" + detail))

        case "status":
            return .ok(statusText())

        case "theme":
            let sub = args.first ?? "list"
            switch sub {
            case "list":
                let lines = store.themeSources.keys.sorted().map { id -> String in
                    let source = store.themeSources[id]!
                    let (t, diags) = ThemeLoader.resolve(id, sources: store.themeSources)
                    let mark = id == theme.id && activeState.activeTheme.provider == .kadomo ? "*" : " "
                    let origin = source.builtin ? "built-in" : (source.file as NSString).abbreviatingWithTildeInPath
                    let problem = t == nil ? "  INVALID: \(diags.first?.message ?? "")" : ""
                    return "\(mark) \(id.padding(toLength: 22, withPad: " ", startingAt: 0)) \((t?.name ?? "?").padding(toLength: 20, withPad: " ", startingAt: 0)) \(origin)\(problem)"
                }
                return .ok(lines.joined(separator: "\n"))
            case "current":
                return .ok(theme.id)
            case "provider":
                let active = activeState.activeTheme
                return .ok(active.provider == .kadomo ? "kadomo \(store.config.theme)" : "\(active.provider.rawValue) \(active.themeId)")
            case "set":
                guard args.count > 1 else { return .fail("usage: kadomo-menu theme set <name>", status: 2) }
                if let error = setTheme(args[1]) { return .fail(error) }
                return .ok("theme: \(theme.name)")
            default:
                return .fail("usage: kadomo-menu theme list|current|provider|set <name>", status: 2)
            }

        case "commands":
            let sub = args.first ?? "list"
            switch sub {
            case "list":
                let json = args.contains("--json")
                let categoriesOnly = args.contains("--categories")
                let filter = option("--category", in: args)
                let catalog = model.catalog
                let items = catalog.items.indices.filter { i in
                    (!categoriesOnly || catalog.items[i].kind == .category) && (filter.map { catalog.isInside(i, $0) } ?? true)
                }.map { catalog.items[$0] }
                if json {
                    let rows = items.map { ["id": $0.id, "title": $0.title, "kind": $0.kind.rawValue, "category": $0.parent, "source": $0.source] }
                    let data = (try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])) ?? Data()
                    return .ok(String(decoding: data, as: UTF8.self))
                }
                let lines = items.map { "\($0.id.padding(toLength: 46, withPad: " ", startingAt: 0)) \($0.title)" }
                return .ok(lines.joined(separator: "\n"))
            case "run":
                guard args.count > 1 else { return .fail("usage: kadomo-menu commands run <id> [--yes]", status: 2) }
                let id = args[1]
                guard let item = model.catalog.item(id) else { return .fail("no item '\(id)'. Run `kadomo-menu commands list`", status: 2) }
                if item.kind == .category { show(category: id); return .ok() }
                if item.kind == .info { return .fail("'\(id)' is informational and has no action") }
                if item.confirm, !args.contains("--yes") { return .fail("'\(item.title)' asks for confirmation; add --yes to run it") }
                if case .builtin(let name) = item.action {
                    performBuiltin(name, item: item)
                    return .ok()
                }
                model.usage.recordRun(id, query: "")
                saveUsageSoon()
                return await withCheckedContinuation { continuation in
                    Executor.run(item.action, title: item.title) { error in
                        continuation.resume(returning: error.map { .fail($0) } ?? .ok())
                    }
                }
            default:
                return .fail("usage: kadomo-menu commands list [--json] [--categories] [--category <id>] | run <id> [--yes]", status: 2)
            }

        case "omarchy":
            guard let external, external.id == .omarchy else {
                return .fail(ThemeProviders.builtIn ? "the Omarchy integration is turned off ([omarchy] enabled = false in config.toml)"
                                                    : "this build does not include the Omarchy integration")
            }
            return await external.handleCLI(args)

        case "bench-ui":
            let rounds = Int(args.first ?? "") ?? 100
            return .ok(benchmarkUI(rounds: max(1, min(rounds, 2000))))

        case "login":
            switch args.first ?? "status" {
            case "on", "off":
                guard loginItemEnabled != nil else { return .fail("launch at login needs the installed app bundle") }
                if (args.first == "on") != (loginItemEnabled == true) { performBuiltin("login.toggle", item: nil) }
                return .ok("launch at login: \(loginItemEnabled == true ? "on" : "off")")
            default:
                return .ok("launch at login: \(loginItemEnabled.map { $0 ? "on" : "off" } ?? "unavailable (not running from an app bundle)")")
            }

        case "quit":
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return .ok()

        default:
            return .fail("unknown command '\(command)'. Run `kadomo-menu help`", status: 2)
        }
    }

    private func option(_ name: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
