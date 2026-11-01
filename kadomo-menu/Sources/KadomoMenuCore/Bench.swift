import Foundation

/// Latency statistics and a synthetic registry for reproducible benchmarks.
public struct LatencyStats: Sendable, CustomStringConvertible {
    public var samples: [Double]  // milliseconds

    public init(_ samples: [Double]) { self.samples = samples.sorted() }

    public func percentile(_ p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let rank = Int((p / 100 * Double(samples.count - 1)).rounded())
        return samples[Swift.min(Swift.max(rank, 0), samples.count - 1)]
    }

    public var p50: Double { percentile(50) }
    public var p95: Double { percentile(95) }
    public var p99: Double { percentile(99) }
    public var max: Double { samples.last ?? 0 }

    public var description: String {
        String(format: "n=%d  p50 %.3f ms  p95 %.3f ms  p99 %.3f ms  max %.3f ms", samples.count, p50, p95, p99, max)
    }
}

public enum Clock {
    /// Monotonic milliseconds.
    public static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }

    public static func measure(_ body: () -> Void) -> Double {
        let t = now()
        body()
        return now() - t
    }
}

public enum SyntheticRegistry {
    static let words = ["alpha", "beta", "studio", "code", "terminal", "fire", "fox", "note", "mail", "photo", "music", "video",
                        "chat", "cloud", "sync", "task", "time", "track", "draw", "paint", "shell", "deploy", "server", "data",
                        "graph", "metric", "window", "space", "focus", "light", "dark", "theme", "build", "test", "debug", "pixel",
                        "über", "café", "naïve", "résumé", "日本", "東京", "Москва", "Ελλάδα"]

    /// `count` deterministic items spread over 40 categories, with keywords and subtitles.
    public static func items(_ count: Int, seed: UInt64 = 42) -> [Item] {
        var rng = SplitMix(seed: seed)
        var items: [Item] = []
        items.reserveCapacity(count + 40)
        for c in 0..<40 {
            items.append(.category("bench/\(c)", "Category \(c) \(words[c % words.count])", icon: "folder", order: c))
        }
        for i in 0..<count {
            let n = 1 + Int(rng.next() % 3)
            var parts: [String] = []
            for _ in 0..<n { parts.append(words[Int(rng.next() % UInt64(words.count))].capitalized) }
            let title = parts.joined(separator: " ") + " \(i)"
            let keyword = words[Int(rng.next() % UInt64(words.count))]
            items.append(Item(id: "bench:\(i)", title: title, subtitle: "Synthetic item \(i) for \(keyword)",
                              kind: i % 4 == 0 ? .app : .action, parent: "bench/\(i % 40)", keywords: [keyword], source: "bench"))
        }
        return items
    }

    public static let queries = ["f", "fi", "fir", "fire", "firef", "term", "tm", "vsc", "studio code", "dark th", "xyzzy",
                                 "cafe", "uber", "東京", "deploy server", "pxl", "graph metric 12", "a", "co", "s"]

    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}

public enum SearchBenchmark {
    public struct Result: Sendable {
        public var items: Int
        public var buildMilliseconds: Double
        public var search: LatencyStats
        public var model: LatencyStats
    }

    /// Builds a catalog of `count` items and times every query `rounds` times:
    /// raw index search, and the full model path (scoping, boosting, rows).
    public static func run(count: Int = 10_000, rounds: Int = 50) -> Result {
        let items = SyntheticRegistry.items(count)
        var catalog = Catalog.empty
        let build = Clock.measure { catalog = Catalog(items: items) }
        var usage = Usage()
        for i in stride(from: 0, to: count, by: 37) { usage.recordRun("bench:\(i)", query: "f") }
        let model = LauncherModel(catalog: catalog, usage: usage)

        var raw: [Double] = []
        var full: [Double] = []
        // Warm up allocators and caches once.
        for q in SyntheticRegistry.queries { _ = catalog.index.search(q, limit: 40) }
        for _ in 0..<rounds {
            for q in SyntheticRegistry.queries {
                raw.append(Clock.measure { _ = catalog.index.search(q, limit: 40) })
                full.append(Clock.measure { model.handle(.query(q)) })
            }
            model.handle(.query(""))
        }
        return Result(items: catalog.items.count, buildMilliseconds: build, search: LatencyStats(raw), model: LatencyStats(full))
    }
}
