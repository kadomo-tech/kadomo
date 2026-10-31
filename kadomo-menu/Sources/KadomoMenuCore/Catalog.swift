import Foundation

/// An immutable snapshot of every item, the category tree, and the search
/// index. The app builds a new one off the main thread whenever a source
/// changes, then swaps it in. Searches never wait for indexing.
public struct Catalog: Sendable {
    public static let rootID = "root"

    public let items: [Item]
    public let index: SearchIndex
    private let positions: [String: Int]
    private let childIndices: [String: [Int]]
    /// Ids dropped because an earlier source already used them.
    public let duplicates: [String]

    public static let empty = Catalog(items: [])

    /// Items earlier in `items` win when two share an id. Categories with
    /// nothing inside them are left out of the tree.
    public init(items input: [Item], hidden: Set<String> = []) {
        var seen: [String: Int] = [:]
        var unique: [Item] = []
        var dupes: [String] = []
        unique.reserveCapacity(input.count)
        for item in input where !hidden.contains(item.id) {
            if seen[item.id] != nil { dupes.append(item.id); continue }
            seen[item.id] = unique.count
            unique.append(item)
        }

        var children: [String: [Int]] = [:]
        for (i, item) in unique.enumerated() {
            children[item.parent, default: []].append(i)
            for extra in item.alsoIn where extra != item.parent { children[extra, default: []].append(i) }
        }

        // Drop empty categories, deepest first, so a parent holding only empty children disappears too.
        var removed = Set<Int>()
        var changed = true
        while changed {
            changed = false
            for (i, item) in unique.enumerated() where item.kind == .category && !removed.contains(i) {
                let live = children[item.id, default: []].filter { !removed.contains($0) }
                if live.isEmpty { removed.insert(i); changed = true }
            }
        }
        if !removed.isEmpty {
            var remap: [Int: Int] = [:]
            var kept: [Item] = []
            for (i, item) in unique.enumerated() where !removed.contains(i) {
                remap[i] = kept.count
                kept.append(item)
            }
            unique = kept
            seen = [:]
            for (i, item) in unique.enumerated() { seen[item.id] = i }
            children = children.mapValues { $0.compactMap { remap[$0] } }
        }

        for key in children.keys {
            children[key]!.sort { a, b in
                let x = unique[a], y = unique[b]
                if x.order != y.order { return x.order < y.order }
                let c = x.title.localizedStandardCompare(y.title)
                if c != .orderedSame { return c == .orderedAscending }
                return x.id < y.id
            }
        }

        items = unique
        positions = seen
        childIndices = children
        duplicates = dupes
        index = SearchIndex(items: unique)
    }

    public func position(of id: String) -> Int? { positions[id] }
    public func item(_ id: String) -> Item? { positions[id].map { items[$0] } }

    public func children(of id: String) -> [Int] { childIndices[id] ?? [] }

    /// The category ids from home down to (and including) `id`.
    public func path(to id: String) -> [String] {
        var path: [String] = []
        var current = id
        var guardCount = 0
        while current != Catalog.rootID, let item = item(current), guardCount < 16 {
            path.insert(current, at: 0)
            current = item.parent
            guardCount += 1
        }
        return path
    }

    /// True when the item at `position` sits anywhere below category `ancestor`.
    public func isInside(_ position: Int, _ ancestor: String) -> Bool {
        if ancestor == Catalog.rootID { return true }
        let item = items[position]
        if item.alsoIn.contains(ancestor) { return true }
        var current = item.parent
        var depth = 0
        while depth < 16 {
            if current == ancestor { return true }
            if current == Catalog.rootID { return false }
            guard let parent = self.item(current) else { return false }
            if parent.alsoIn.contains(ancestor) { return true }
            current = parent.parent
            depth += 1
        }
        return false
    }
}
