import Testing
@testable import KadomoMenuCore

@Suite struct SearchTests {
    let items: [Item] = [
        Item(id: "app:firefox", title: "Firefox", kind: .app, parent: "apps", keywords: ["browser", "mozilla"]),
        Item(id: "app:fireworks", title: "Fireworks Studio", kind: .app, parent: "apps"),
        Item(id: "app:terminal", title: "Terminal", kind: .app, parent: "apps", keywords: ["shell"]),
        Item(id: "app:vscode", title: "Visual Studio Code", kind: .app, parent: "apps", keywords: ["vscode", "code"]),
        Item(id: "app:xcode", title: "Xcode", kind: .app, parent: "apps"),
        Item(id: "set:bluetooth", title: "Bluetooth", subtitle: "System Settings", parent: "settings", keywords: ["wireless"]),
        Item(id: "set:wifi", title: "Wi-Fi", subtitle: "Network connection", parent: "settings", keywords: ["wifi", "wireless", "network"]),
        Item(id: "sys:restart", title: "Restart…", subtitle: "Restart this Mac", parent: "system", keywords: ["reboot"]),
        Item(id: "theme:dark", title: "Kadomo Dark", subtitle: "Launcher theme", parent: "appearance", keywords: ["theme"]),
        Item(id: "app:cafe", title: "Café Menu", kind: .app, parent: "apps"),
        Item(id: "app:tokyo", title: "東京 Metro", kind: .app, parent: "apps"),
        Item(id: "app:pdf", title: "PDF Expert", kind: .app, parent: "apps"),
        Item(id: "app:ghostty", title: "Ghostty", kind: .app, parent: "apps", aliases: ["term2"]),
    ]

    func top(_ q: String, boost: [String: Int] = [:]) -> String? {
        let index = SearchIndex(items: items)
        let hits = index.search(q, limit: 10, boost: { boost[items[$0].id] ?? 0 })
        return hits.first.map { items[$0.index].id }
    }

    func ids(_ q: String) -> [String] {
        let index = SearchIndex(items: items)
        return index.search(q, limit: 10).map { items[$0.index].id }
    }

    @Test(arguments: [
        ("fire", "app:firefox"),
        ("Firefox", "app:firefox"),
        ("FIREFOX", "app:firefox"),
        ("term", "app:terminal"),
        ("vscode", "app:vscode"),
        ("vsc", "app:vscode"),
        ("studio code", "app:vscode"),
        ("code", "app:vscode"),
        ("bluetooth", "set:bluetooth"),
        ("wifi", "set:wifi"),
        ("restart", "sys:restart"),
        ("reboot", "sys:restart"),
        ("dark", "theme:dark"),
        ("cafe", "app:cafe"),
        ("CAFÉ", "app:cafe"),
        ("東京", "app:tokyo"),
        ("pdfe", "app:pdf"),
        ("term2", "app:ghostty"),
        ("frfx", "app:firefox"),
    ])
    func findsExpectedTopHit(_ query: String, expected: String) {
        #expect(top(query) == expected, "query '\(query)' → \(ids(query))")
    }

    @Test func exactMatchBeatsHeavyUsage() {
        // Fireworks used a lot; "firefox" typed exactly must still win.
        #expect(top("firefox", boost: ["app:fireworks": 99]) == "app:firefox")
    }

    @Test func usageReordersWithinSimilarTiers() {
        #expect(top("fire") == "app:firefox")
        #expect(top("fire", boost: ["app:fireworks": 60]) == "app:fireworks")
    }

    @Test func noJunkMatches() {
        #expect(ids("zzqq").isEmpty)
        #expect(!ids("xc").contains("app:vscode") || ids("xc").first == "app:xcode")
    }

    @Test func wordStartsSplitCamelCaseAndDigits() {
        let (bytes, starts) = Fold.words("VSCode Insiders 2")
        #expect(String(decoding: bytes, as: UTF8.self) == "vscode insiders 2")
        #expect(starts == [0, 2, 7, 16])
    }

    @Test func deterministicOrderingForTies() {
        let a = ids("s")
        let b = ids("s")
        #expect(a == b)
    }

    @Test func emptyQueryReturnsNothing() {
        #expect(ids("   ").isEmpty)
    }
}
