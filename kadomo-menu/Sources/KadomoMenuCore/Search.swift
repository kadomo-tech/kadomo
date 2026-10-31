import Foundation

/// Case-, diacritic-, and width-insensitive lowercase text as UTF-8 bytes.
public enum Fold {
    public static func string(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
    }

    public static func bytes(_ s: String) -> [UInt8] { Array(string(s).utf8) }

    /// Folded bytes plus the byte offsets where words start. A word starts at the
    /// beginning, after a separator, at a lower→upper case change, or at a letter↔digit change.
    static func words(_ s: String) -> (bytes: [UInt8], starts: [Int]) {
        let folded = string(s)
        let original = Array(s)
        let foldedChars = Array(folded)
        // Folding nearly always keeps one character per character. When it does
        // not (ß → ss), fall back to word starts at separators only.
        let aligned = original.count == foldedChars.count
        var bytes: [UInt8] = []
        bytes.reserveCapacity(folded.utf8.count)
        var starts: [Int] = []
        var previous: Character? = nil
        for (index, ch) in foldedChars.enumerated() {
            let source = aligned ? original[index] : ch
            let isSeparator = ch == " " || ch == "-" || ch == "_" || ch == "." || ch == "/" || ch == "(" || ch == "[" || ch == ":"
            if !isSeparator {
                var boundary = false
                if let p = previous {
                    let pSep = p == " " || p == "-" || p == "_" || p == "." || p == "/" || p == "(" || p == "[" || p == ":"
                    let next: Character? = aligned && index + 1 < original.count ? original[index + 1] : nil
                    boundary = pSep
                        || (p.isLowercase && source.isUppercase)
                        // "VSCode": the C starts "Code".
                        || (p.isUppercase && source.isUppercase && next?.isLowercase == true)
                        || (p.isLetter && source.isNumber) || (p.isNumber && source.isLetter)
                } else {
                    boundary = true
                }
                if boundary { starts.append(bytes.count) }
            }
            bytes.append(contentsOf: ch.utf8)
            previous = source
        }
        return (bytes, starts)
    }
}

public enum MatchTier: Int, Sendable, Comparable {
    case fuzzy, subtitle, eachWord, substring, keywordPrefix, keyword, allWords, acronym, wordPrefix, aliasPrefix, prefix, alias, exact
    public static func < (a: MatchTier, b: MatchTier) -> Bool { a.rawValue < b.rawValue }
}

public struct SearchHit: Sendable, Equatable {
    public var index: Int
    public var score: Int
    public var tier: MatchTier
}

/// One searchable record, precomputed once per catalog snapshot.
struct SearchEntry: Sendable {
    var title: [UInt8]
    var wordStarts: [Int]
    var acronym: [UInt8]
    var aliases: [[UInt8]]
    var keywords: [[UInt8]]
    var subtitle: [UInt8]
    var subtitleStarts: [Int]
    /// Bit (b & 63) set for every byte in any field: a cheap "cannot match" check.
    var mask: UInt64
    var titleLength: Int
    var kindBias: Int
}

/// An immutable index. Build it off the main thread, search it anywhere.
public struct SearchIndex: Sendable {
    let entries: [SearchEntry]

    public var count: Int { entries.count }

    public init(items: [Item]) {
        entries = items.map(SearchIndex.entry)
    }

    static func entry(_ item: Item) -> SearchEntry {
        let (title, starts) = Fold.words(item.title)
        var acronym: [UInt8] = []
        for s in starts { acronym.append(title[s]) }
        let aliases = item.aliases.map(Fold.bytes)
        let keywords = item.keywords.map(Fold.bytes)
        let (subtitle, subtitleStarts) = Fold.words(item.subtitle)
        var mask: UInt64 = 0
        func add(_ bytes: [UInt8]) { for b in bytes { mask |= 1 << UInt64(b & 63) } }
        add(title); add(subtitle)
        aliases.forEach(add); keywords.forEach(add)
        let bias: Int = switch item.kind {
        case .app: 4
        case .category: 2
        case .action: 0
        case .info: -10
        }
        return SearchEntry(title: title, wordStarts: starts, acronym: acronym, aliases: aliases, keywords: keywords,
                           subtitle: subtitle, subtitleStarts: subtitleStarts, mask: mask, titleLength: item.title.count, kindBias: bias)
    }

    /// Scores every entry that `include` accepts. `boost` adds bounded usage weight.
    /// Results are sorted best first; ties break on shorter title, then index order.
    public func search(_ query: String, limit: Int, includeSubtitles: Bool = true,
                       include: (Int) -> Bool = { _ in true }, boost: (Int) -> Int = { _ in 0 }) -> [SearchHit] {
        let q = Query(query)
        guard !q.bytes.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for i in entries.indices {
            let e = entries[i]
            if e.mask & q.mask != q.mask { continue }
            guard include(i), let (score, tier) = SearchIndex.score(q, e, includeSubtitles: includeSubtitles) else { continue }
            hits.append(SearchHit(index: i, score: score + e.kindBias + min(max(boost(i), 0), 99), tier: tier))
        }
        hits.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            let la = entries[a.index].titleLength, lb = entries[b.index].titleLength
            if la != lb { return la < lb }
            return a.index < b.index
        }
        if hits.count > limit { hits.removeSubrange(limit...) }
        return hits
    }

    struct Query {
        var bytes: [UInt8]
        var tokens: [[UInt8]]
        var compact: [UInt8]
        var mask: UInt64

        init(_ text: String) {
            let folded = Fold.string(text.trimmingCharacters(in: .whitespaces))
            bytes = Array(folded.utf8)
            tokens = folded.split(separator: " ", omittingEmptySubsequences: true).map { Array($0.utf8) }
            compact = bytes.filter { $0 != UInt8(ascii: " ") }
            var m: UInt64 = 0
            for b in compact { m |= 1 << UInt64(b & 63) }
            mask = m
        }
    }

    static func score(_ q: Query, _ e: SearchEntry, includeSubtitles: Bool) -> (Int, MatchTier)? {
        let t = e.title
        let qb = q.bytes
        if t == qb { return (1000, .exact) }
        for a in e.aliases where a == qb { return (980, .alias) }
        if t.starts(with: qb) { return (890 - min(t.count - qb.count, 30), .prefix) }
        for a in e.aliases where a.starts(with: qb) { return (850, .aliasPrefix) }
        if q.tokens.count == 1 {
            for (n, s) in e.wordStarts.enumerated() where n > 0 && t[s...].starts(with: qb) {
                return (800 - min(n, 10), .wordPrefix)
            }
        }
        if qb.count >= 2, e.acronym.starts(with: q.compact) { return (780, .acronym) }
        if q.tokens.count > 1, allTokensPrefixWords(q.tokens, t, e.wordStarts) { return (760, .allWords) }
        for k in e.keywords where k == qb { return (720, .keyword) }
        for k in e.keywords where k.starts(with: qb) { return (680, .keywordPrefix) }
        if let at = find(qb, in: t) { return (600 - min(at, 40), .substring) }
        if q.tokens.count > 1, q.tokens.allSatisfy({ tok in find(tok, in: t) != nil || e.keywords.contains { find(tok, in: $0) != nil } || e.aliases.contains { find(tok, in: $0) != nil } }) {
            return (550, .eachWord)
        }
        if includeSubtitles, !e.subtitle.isEmpty {
            if q.tokens.count == 1, e.subtitleStarts.contains(where: { e.subtitle[$0...].starts(with: qb) }) { return (450, .subtitle) }
            if qb.count >= 3, find(qb, in: e.subtitle) != nil { return (350, .subtitle) }
        }
        if let f = fuzzy(q.compact, t, e.wordStarts) { return (f, .fuzzy) }
        return nil
    }

    static func allTokensPrefixWords(_ tokens: [[UInt8]], _ t: [UInt8], _ starts: [Int]) -> Bool {
        tokens.allSatisfy { tok in starts.contains { t[$0...].starts(with: tok) } }
    }

    static func find(_ needle: [UInt8], in hay: [UInt8]) -> Int? {
        let n = needle.count, h = hay.count
        guard n > 0, n <= h else { return nil }
        let first = needle[0]
        var i = 0
        while i <= h - n {
            if hay[i] == first {
                var j = 1
                while j < n && hay[i + j] == needle[j] { j += 1 }
                if j == n { return i }
            }
            i += 1
        }
        return nil
    }

    /// Subsequence match. Rewards word-start and consecutive hits, penalizes gaps.
    /// The first query character must land on a word start, which keeps results sane.
    static func fuzzy(_ q: [UInt8], _ t: [UInt8], _ starts: [Int]) -> Int? {
        guard q.count >= 2, q.count <= t.count else { return nil }
        var startSet: UInt64 = 0
        var farStarts: [Int] = []
        for s in starts { if s < 64 { startSet |= 1 << UInt64(s) } else { farStarts.append(s) } }
        func isStart(_ i: Int) -> Bool { i < 64 ? (startSet >> UInt64(i)) & 1 == 1 : farStarts.contains(i) }

        var best: Int? = nil
        for s in starts where t[s] == q[0] {
            var ti = s + 1, qi = 1
            var score = 300 + 12 - min(s, 12)
            var previous = s
            var gaps = 0
            while qi < q.count && ti < t.count {
                if t[ti] == q[qi] {
                    if ti == previous + 1 { score += 8 } else if isStart(ti) { score += 10 } else { score += 1 }
                    gaps += ti - previous - 1
                    previous = ti
                    qi += 1
                }
                ti += 1
            }
            guard qi == q.count, gaps <= q.count * 4 + 4 else { continue }
            score -= gaps * 3
            best = max(best ?? 0, min(max(score, 100), 450))
        }
        return best
    }
}
