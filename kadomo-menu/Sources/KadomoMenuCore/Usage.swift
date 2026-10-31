import Foundation

/// Local-only usage history: how often and how recently each item ran, which
/// item was picked for a typed query, and favorites. Never leaves the Mac.
public struct Usage: Codable, Sendable, Equatable {
    public struct Record: Codable, Sendable, Equatable {
        public var count: Int
        public var last: Double
    }

    public var records: [String: Record] = [:]
    /// Folded query → the id picked last time for it.
    public var picks: [String: String] = [:]
    public var favorites: [String] = []

    public init() {}

    public static let maxRecords = 2000
    public static let maxPicks = 500

    public mutating func recordRun(_ id: String, query: String, now: Double = Date().timeIntervalSince1970) {
        var r = records[id] ?? Record(count: 0, last: now)
        r.count += 1
        r.last = now
        records[id] = r
        let q = Fold.string(query.trimmingCharacters(in: .whitespaces))
        if !q.isEmpty { picks[q] = id }
        trim()
    }

    public mutating func toggleFavorite(_ id: String) {
        if let i = favorites.firstIndex(of: id) { favorites.remove(at: i) } else { favorites.append(id) }
    }

    public func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    /// 0...50. Logarithmic in count, halves after about two weeks without use.
    public func frecency(_ id: String, now: Double = Date().timeIntervalSince1970) -> Int {
        guard let r = records[id] else { return 0 }
        let ageDays = max(0, now - r.last) / 86_400
        let decay = 1 / (1 + ageDays / 14)
        return min(50, Int((log2(Double(r.count) + 1) * 12 * decay).rounded()))
    }

    /// The total bounded boost used by ranking: frecency + learned pick + favorite, at most 99.
    public func boost(_ id: String, query: String, now: Double = Date().timeIntervalSince1970) -> Int {
        var b = frecency(id, now: now)
        if !query.isEmpty, picks[query] == id { b += 30 }
        if favorites.contains(id) { b += 20 }
        return min(b, 99)
    }

    /// Most recently run ids, newest first.
    public func recent(_ n: Int) -> [String] {
        records.sorted { $0.value.last > $1.value.last }.prefix(n).map(\.key)
    }

    mutating func trim() {
        if records.count > Usage.maxRecords {
            let keep = records.sorted { $0.value.last > $1.value.last }.prefix(Usage.maxRecords)
            records = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if picks.count > Usage.maxPicks {
            picks = Dictionary(uniqueKeysWithValues: picks.prefix(Usage.maxPicks).map { ($0.key, $0.value) })
        }
    }
}
