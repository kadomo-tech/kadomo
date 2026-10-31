import Foundation

/// The launcher's keyboard and navigation state machine. Platform-free: the
/// AppKit layer turns key events into `LauncherEvent`s, applies the returned
/// `LauncherEffect`, and redraws from `rows`.
public enum LauncherMode: Equatable, Sendable {
    case list
    /// The secondary actions of one item.
    case actions(itemID: String)
    /// Waiting for Enter to confirm. `action` nil is the primary action.
    case confirm(itemID: String, action: Int?)
}

public struct LauncherState: Equatable, Sendable {
    /// Category ids from home down to the open one. Empty is home.
    public var path: [String] = []
    public var query = ""
    public var selection = 0
    public var actionSelection = 0
    public var mode = LauncherMode.list
    /// The selection to restore in each parent when going back.
    var parentSelections: [Int] = []

    public init() {}
}

/// Where the text caret is, so arrows only navigate when they would not edit text.
public struct CaretContext: Equatable, Sendable {
    public var atStart: Bool
    public var atEnd: Bool
    public var hasSelection: Bool

    public init(atStart: Bool = true, atEnd: Bool = true, hasSelection: Bool = false) {
        self.atStart = atStart; self.atEnd = atEnd; self.hasSelection = hasSelection
    }
}

public enum LauncherEvent: Equatable, Sendable {
    case query(String)
    case command(KeyCommand, CaretContext)
    /// Backspace with an empty query.
    case backspaceOnEmpty
    case hover(Int)
    case click(Int)
}

public enum LauncherEffect: Equatable, Sendable {
    /// Handled; redraw.
    case handled
    /// Not ours: let the text field have the key.
    case passThrough
    /// Run an item's action. `secondary` is the index into `actions(for:)`, nil for the primary action.
    case run(itemID: String, action: Action, secondary: Int?)
    case dismiss
    case toggledFavorite(String)
}

public final class LauncherModel {
    public private(set) var catalog: Catalog
    public var usage: Usage
    public var config: AppConfig {
        didSet { refresh() }
    }
    public private(set) var state = LauncherState()
    /// Catalog positions shown in list mode.
    public private(set) var rows: [Int] = []
    /// Positions in `rows` that are favorites shown on home (drawn with a star).
    public private(set) var favoriteRows = Set<Int>()
    /// True when a search inside a category found nothing there and fell back to everything.
    public private(set) var isGlobalFallback = false
    /// The category a prefix (`>` `@` `!`) scoped the search to.
    public private(set) var prefixScope: String?
    /// Extra actions computed at the moment Tab is pressed (running-app actions, ...).
    public var dynamicActions: ((Item) -> [SecondaryAction])?

    public init(catalog: Catalog = .empty, usage: Usage = Usage(), config: AppConfig = AppConfig()) {
        self.catalog = catalog
        self.usage = usage
        self.config = config
        refresh()
    }

    // MARK: Inputs from the app

    /// Swaps in a new catalog, keeping the open category and selected item when they still exist.
    public func setCatalog(_ catalog: Catalog) {
        let selectedID = selectedItem?.id
        self.catalog = catalog
        state.path = state.path.filter { catalog.item($0) != nil }
        state.parentSelections = Array(state.parentSelections.prefix(state.path.count))
        refresh()
        if let selectedID, let i = rows.firstIndex(where: { catalog.items[$0].id == selectedID }) { state.selection = i }
    }

    /// Back to home with an empty query. Called on every open.
    public func reset() {
        state = LauncherState()
        refresh()
    }

    /// Opens a category by id (`kadomo-menu open --path system`) with an optional query.
    public func open(category: String?, query: String = "") {
        state = LauncherState()
        if let category, catalog.item(category)?.kind == .category {
            state.path = catalog.path(to: category)
            state.parentSelections = Array(repeating: 0, count: state.path.count)
        }
        state.query = query
        refresh()
    }

    // MARK: Reading state

    public var selectedItem: Item? {
        guard rows.indices.contains(state.selection) else { return nil }
        return catalog.items[rows[state.selection]]
    }

    public var currentCategory: Item? { state.path.last.flatMap(catalog.item) }

    /// Titles from home down to the open category.
    public var breadcrumb: [String] { state.path.compactMap { catalog.item($0)?.title } }

    public var actionsItem: Item? {
        switch state.mode {
        case .actions(let id), .confirm(let id, _): catalog.item(id)
        case .list: nil
        }
    }

    /// The rows shown in actions mode for `item`: its own secondary actions, the
    /// dynamic ones from the platform layer, then favorite toggling.
    public func actions(for item: Item) -> [SecondaryAction] {
        var list = item.secondary
        list += dynamicActions?(item) ?? []
        if item.kind != .info {
            let fav = usage.isFavorite(item.id) || config.favorites.contains(item.id)
            list.append(SecondaryAction(fav ? "Remove from Favorites" : "Add to Favorites", .builtin("favorite.toggle"),
                                        icon: .symbol(fav ? "star.slash" : "star"), hint: KeyMap(config.keys).primary(.favorite)?.symbol))
        }
        return list
    }

    public var emptyMessage: String? {
        guard rows.isEmpty else { return nil }
        if state.query.isEmpty { return "Nothing here yet" }
        return "No results for “\(state.query)”"
    }

    // MARK: Events

    @discardableResult
    public func handle(_ event: LauncherEvent) -> LauncherEffect {
        switch event {
        case .query(let q):
            guard q != state.query || state.mode != .list else { return .handled }
            state.query = q
            state.mode = .list
            state.selection = 0
            refresh()
            return .handled

        case .backspaceOnEmpty:
            if case .list = state.mode, config.backspaceNavigatesBack, !state.path.isEmpty { pop(); return .handled }
            return .passThrough

        case .hover(let i):
            guard config.hoverSelects, case .list = state.mode, rows.indices.contains(i) else { return .handled }
            state.selection = i
            return .handled

        case .click(let i):
            switch state.mode {
            case .list:
                guard rows.indices.contains(i) else { return .handled }
                state.selection = i
                return activate(alternate: false)
            case .actions(let id):
                guard let item = catalog.item(id) else { return .handled }
                state.actionSelection = i
                return runSecondary(item, i)
            case .confirm:
                return .handled
            }

        case .command(let command, let caret):
            switch state.mode {
            case .list: return listCommand(command, caret)
            case .actions(let id): return actionsCommand(command, id)
            case .confirm(let id, let action): return confirmCommand(command, id, action)
            }
        }
    }

    func listCommand(_ command: KeyCommand, _ caret: CaretContext) -> LauncherEffect {
        switch command {
        case .up: move(-1); return .handled
        case .down: move(1); return .handled
        case .first: state.selection = 0; return .handled
        case .last: state.selection = max(rows.count - 1, 0); return .handled
        case .pageUp: state.selection = max(state.selection - pageSize, 0); return .handled
        case .pageDown: state.selection = min(state.selection + pageSize, max(rows.count - 1, 0)); return .handled
        case .enter: return activate(alternate: false)
        case .alternate: return activate(alternate: true)
        case .actions:
            guard let item = selectedItem, !actions(for: item).isEmpty else { return .handled }
            state.mode = .actions(itemID: item.id)
            state.actionSelection = 0
            return .handled
        case .back:
            // Left arrow edits text while there is a query.
            guard state.query.isEmpty else { return .passThrough }
            if !state.path.isEmpty { pop() }
            return .handled
        case .forward:
            guard state.query.isEmpty || (caret.atEnd && !caret.hasSelection) else { return .passThrough }
            guard let item = selectedItem, item.kind == .category else { return state.query.isEmpty ? .handled : .passThrough }
            push(item)
            return .handled
        case .close:
            if !state.query.isEmpty { state.query = ""; state.selection = 0; refresh(); return .handled }
            if config.escapeNavigatesBack, !state.path.isEmpty { pop(); return .handled }
            return .dismiss
        case .clear:
            state.query = ""
            state.selection = 0
            refresh()
            return .handled
        case .favorite:
            guard let item = selectedItem, item.kind != .info else { return .handled }
            usage.toggleFavorite(item.id)
            refresh()
            return .toggledFavorite(item.id)
        }
    }

    func actionsCommand(_ command: KeyCommand, _ id: String) -> LauncherEffect {
        guard let item = catalog.item(id) else { state.mode = .list; return .handled }
        let count = actions(for: item).count
        switch command {
        case .up: state.actionSelection = (state.actionSelection - 1 + count) % max(count, 1)
        case .down: state.actionSelection = (state.actionSelection + 1) % max(count, 1)
        case .first: state.actionSelection = 0
        case .last: state.actionSelection = max(count - 1, 0)
        case .pageUp, .pageDown: break
        case .enter, .forward: return runSecondary(item, state.actionSelection)
        case .close, .back, .actions: state.mode = .list
        case .alternate, .clear, .favorite: break
        }
        return .handled
    }

    func confirmCommand(_ command: KeyCommand, _ id: String, _ action: Int?) -> LauncherEffect {
        switch command {
        case .enter:
            guard let item = catalog.item(id) else { state.mode = .list; return .handled }
            state.mode = .list
            if let action {
                let list = actions(for: item)
                guard list.indices.contains(action) else { return .handled }
                return .run(itemID: id, action: list[action].action, secondary: action)
            }
            return .run(itemID: id, action: item.action, secondary: nil)
        case .close, .back:
            state.mode = .list
            return .handled
        default:
            return .handled
        }
    }

    func activate(alternate: Bool) -> LauncherEffect {
        guard let item = selectedItem else { return .handled }
        if item.kind == .category, !alternate { push(item); return .handled }
        if alternate {
            let list = actions(for: item)
            guard !list.isEmpty, list[0].action != .builtin("favorite.toggle") else { return activate(alternate: false) }
            return runSecondary(item, 0)
        }
        if item.kind == .info || item.action == .none { return .handled }
        if item.confirm {
            state.mode = .confirm(itemID: item.id, action: nil)
            return .handled
        }
        return .run(itemID: item.id, action: item.action, secondary: nil)
    }

    func runSecondary(_ item: Item, _ index: Int) -> LauncherEffect {
        let list = actions(for: item)
        guard list.indices.contains(index) else { return .handled }
        let action = list[index]
        if action.action == .builtin("favorite.toggle") {
            usage.toggleFavorite(item.id)
            state.mode = .list
            refresh()
            return .toggledFavorite(item.id)
        }
        if action.confirm {
            state.mode = .confirm(itemID: item.id, action: index)
            return .handled
        }
        state.mode = .list
        return .run(itemID: item.id, action: action.action, secondary: index)
    }

    var pageSize: Int { max(1, 8) }

    func move(_ delta: Int) {
        guard !rows.isEmpty else { state.selection = 0; return }
        state.selection = (state.selection + delta + rows.count) % rows.count
    }

    func push(_ item: Item) {
        let target = catalog.path(to: item.id)
        // Entering from a search result may jump several levels.
        if target.count == state.path.count + 1, Array(target.dropLast()) == state.path {
            state.parentSelections.append(state.selection)
        } else {
            state.parentSelections = Array(repeating: 0, count: target.count)
        }
        state.path = target
        state.query = ""
        state.selection = 0
        state.mode = .list
        refresh()
    }

    func pop() {
        guard !state.path.isEmpty else { return }
        state.path.removeLast()
        let restore = state.parentSelections.popLast() ?? 0
        state.query = ""
        state.mode = .list
        refresh()
        state.selection = min(restore, max(rows.count - 1, 0))
    }

    // MARK: Rows

    public func refresh() {
        isGlobalFallback = false
        prefixScope = nil
        favoriteRows = []
        var query = state.query.trimmingCharacters(in: .whitespaces)
        var scope = state.path.last ?? Catalog.rootID

        if let (prefix, category) = config.prefixes.first(where: { query.hasPrefix($0.key) && !$0.key.isEmpty }),
           catalog.item(category) != nil {
            query = String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            scope = category
            prefixScope = category
            if query.isEmpty {
                rows = catalog.children(of: category)
                clampSelection()
                return
            }
        }

        if query.isEmpty {
            rows = scope == Catalog.rootID ? homeRows() : catalog.children(of: scope)
            clampSelection()
            return
        }

        let folded = Fold.string(query)
        let usage = self.usage
        let items = catalog.items
        let favorites = Set(config.favorites)
        let boost: (Int) -> Int = { i in
            let id = items[i].id
            return usage.boost(id, query: folded) + (favorites.contains(id) && !usage.isFavorite(id) ? 20 : 0)
        }
        let searchable: (Int) -> Bool = { items[$0].searchable }
        var hits: [SearchHit]
        if scope == Catalog.rootID {
            hits = catalog.index.search(query, limit: config.maxResults, includeSubtitles: config.searchSubtitles, include: searchable, boost: boost)
        } else {
            let catalog = self.catalog
            hits = catalog.index.search(query, limit: config.maxResults, includeSubtitles: config.searchSubtitles,
                                        include: { searchable($0) && catalog.isInside($0, scope) && items[$0].id != scope }, boost: boost)
            if hits.isEmpty, prefixScope == nil {
                isGlobalFallback = true
                hits = catalog.index.search(query, limit: config.maxResults, includeSubtitles: config.searchSubtitles, include: searchable, boost: boost)
            }
        }
        rows = hits.map(\.index)
        clampSelection()
    }

    func homeRows() -> [Int] {
        var out: [Int] = []
        var seen = Set<Int>()
        if config.showFavoritesOnHome {
            for id in config.favorites + usage.favorites {
                guard let p = catalog.position(of: id), !seen.contains(p) else { continue }
                favoriteRows.insert(out.count)
                out.append(p); seen.insert(p)
            }
        }
        if config.recentOnHome > 0 {
            var added = 0
            for id in usage.recent(config.recentOnHome * 3) where added < config.recentOnHome {
                guard let p = catalog.position(of: id), !seen.contains(p), catalog.items[p].kind != .category else { continue }
                out.append(p); seen.insert(p)
                added += 1
            }
        }
        for p in catalog.children(of: Catalog.rootID) where !seen.contains(p) { out.append(p) }
        return out
    }

    func clampSelection() {
        if state.selection >= rows.count { state.selection = max(rows.count - 1, 0) }
        if state.selection < 0 { state.selection = 0 }
    }
}
