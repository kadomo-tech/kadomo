import Foundation
import Testing
@testable import KadomoMenuCore

/// The appearance contract, the active-theme selection, and the rule that
/// Kadomo's native themes never depend on another provider.
@Suite struct AppearanceTests {
    /// `$TMPDIR` first: sandboxes allow it where the system temp folder may not be writable.
    static var tmp: String { ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory() }

    static let base = ThemeLoader.resolve(BuiltinThemes.defaultID, sources: BuiltinThemes.sources).0!

    static func appearance(name: String = "Sample", bg: String = "#1a1b26", fg: String = "#c0caf5") -> ThemeAppearance {
        let c = { (s: String) in RGBA(hex: s)! }
        return ThemeAppearance(name: name, appearance: "dark", background: c(bg), foreground: c(fg), muted: c("#9aa5ce"),
                               accent: c("#7aa2f7"), selectionBackground: c("#292e42"), selectionForeground: c("#c0caf5"),
                               border: [c("#414868")], separator: c("#24283b"), placeholder: c("#9aa5ce"), caret: c("#7aa2f7"),
                               breadcrumb: c("#7aa2f7"), hint: c("#9aa5ce"), error: c("#f7768e"), warning: c("#e0af68"))
    }

    @Test func appearanceChangesOnlyColorsNameAndMode() {
        let t = Self.appearance().theme(id: "omarchy:x", base: Self.base)
        #expect(t.id == "omarchy:x")
        #expect(t.name == "Sample")
        #expect(t.colors.background == RGBA(hex: "#1a1b26"))
        #expect(t.colors.border == .solid(RGBA(hex: "#414868")!))
        #expect(t.font == Self.base.font)
        #expect(t.geometry == Self.base.geometry)
        #expect(t.effects == Self.base.effects)
        #expect(t.layout == Self.base.layout)
    }

    @Test func gradientBorderNeedsTwoColors() {
        var a = Self.appearance()
        a.border = [RGBA(1, 0, 0), RGBA(0, 0, 1)]
        if case .gradient(let cs, _) = a.theme(id: "x", base: Self.base).colors.border { #expect(cs.count == 2) } else { Issue.record("expected gradient") }
    }

    @Test func validationRejectsUnreadableColors() {
        #expect(Self.appearance().validate().isEmpty)
        #expect(!Self.appearance(bg: "#202020", fg: "#222222").validate().isEmpty)
        var a = Self.appearance()
        a.appearance = "sepia"
        #expect(!a.validate().isEmpty)
    }

    @Test func appearanceRoundTripsThroughJSON() throws {
        var a = Self.appearance()
        a.selectionBackground = RGBA(hex: "#ffffff20")!
        let data = try JSONEncoder().encode(a)
        let back = try JSONDecoder().decode(ThemeAppearance.self, from: data)
        #expect(back.background.hexString == a.background.hexString)
        #expect(back.selectionBackground.hexString == "#ffffff20")
    }

    @Test func readableMovesTextUntilItContrasts() {
        let bg = RGBA(hex: "#1a1b26")!
        let dim = RGBA(hex: "#30324a")!
        #expect(RGBA.contrast(dim, bg) < 4.5)
        #expect(RGBA.contrast(dim.readable(on: bg, ratio: 4.5), bg) >= 4.5)
        let light = RGBA(hex: "#faf4ed")!
        #expect(RGBA.contrast(RGBA(hex: "#e0dad3")!.readable(on: light, ratio: 4.5), light) >= 4.5)
    }

    // MARK: Active theme

    @Test func missingStateFileMeansKadomo() {
        let state = ActiveThemeState.load(from: Self.tmp + "/no-such-\(UUID().uuidString).json")
        #expect(state.activeTheme.provider == .kadomo)
    }

    @Test func corruptStateFileMeansKadomo() throws {
        let path = Self.tmp + "/active-\(UUID().uuidString).json"
        try AtomicFile.write(Data("{ not json".utf8), to: path)
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(ActiveThemeState.load(from: path).activeTheme.provider == .kadomo)
    }

    @Test func stateRemembersEachProvidersLastPick() throws {
        var state = ActiveThemeState()
        state.select(ThemeSelection(provider: .kadomo, themeId: "kadomo"))
        state.select(ThemeSelection(provider: .omarchy, themeId: "official:nord"))
        #expect(state.activeTheme == ThemeSelection(provider: .omarchy, themeId: "official:nord"))
        #expect(state.lastSelected == ["kadomo": "kadomo", "omarchy": "official:nord"])
        let path = Self.tmp + "/state-\(UUID().uuidString)/settings/active-theme.json"
        try state.save(to: path)
        #expect(ActiveThemeState.load(from: path) == state)
        let json = try String(contentsOfFile: path, encoding: .utf8)
        #expect(json.contains("\"provider\" : \"omarchy\""))
        #expect(json.contains("\"themeId\" : \"official:nord\""))
    }

    // MARK: Native isolation

    @Test func nativeThemeNeverConsultsTheExternalProvider() {
        var calls = 0
        let state = ActiveThemeState(activeTheme: ThemeSelection(provider: .kadomo, themeId: "kadomo-dark"))
        let r = ActiveThemeResolver.resolve(state, native: { (Self.base, []) }, external: { _ in calls += 1; return .failure(ExternalThemeError("boom")) })
        #expect(calls == 0)
        #expect(r.theme == Self.base)
        #expect(r.provider == .kadomo)
        #expect(!r.fellBack)
    }

    @Test func externalFailureFallsBackToTheNativeTheme() {
        let state = ActiveThemeState(activeTheme: ThemeSelection(provider: .omarchy, themeId: "official:gone"))
        let r = ActiveThemeResolver.resolve(state, native: { (Self.base, []) }, external: { _ in .failure(ExternalThemeError("not installed")) })
        #expect(r.theme == Self.base)
        #expect(r.provider == .kadomo)
        #expect(r.fellBack)
        #expect(r.diagnostics.first?.message.contains("not installed") == true)
    }

    @Test func disabledIntegrationFallsBackWithoutCallingAnything() {
        let state = ActiveThemeState(activeTheme: ThemeSelection(provider: .omarchy, themeId: "official:nord"))
        let r = ActiveThemeResolver.resolve(state, native: { (Self.base, []) }, external: nil)
        #expect(r.theme == Self.base)
        #expect(r.fellBack)
        #expect(r.diagnostics.first?.message.contains("turned off") == true)
    }

    @Test func externalThemeIsUsedWhenAvailable() {
        let state = ActiveThemeState(activeTheme: ThemeSelection(provider: .omarchy, themeId: "official:nord"))
        let wanted = Self.appearance().theme(id: "omarchy:official:nord", base: Self.base)
        var nativeCalls = 0
        let r = ActiveThemeResolver.resolve(state, native: { nativeCalls += 1; return (Self.base, []) }, external: { _ in .success(wanted) })
        #expect(r.theme == wanted)
        #expect(r.provider == .omarchy)
        #expect(nativeCalls == 0)
    }

    @Test func omarchyConfigFlagDefaultsOnAndCanBeTurnedOff() {
        #expect(ConfigLoader.parse("", file: "c").0.omarchyEnabled)
        let (c, diags) = ConfigLoader.parse("[omarchy]\nenabled = false\n", file: "c")
        #expect(diags.isEmpty)
        #expect(!c.omarchyEnabled)
    }
}
