import Foundation
import Testing
import KadomoMenuCore
@testable import KadomoOmarchy

/// A throwaway folder under $TMPDIR (sandboxes allow it where the system
/// temp folder may not be writable).
final class Scratch {
    let path: String
    init() {
        let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        path = (base as NSString).appendingPathComponent("omarchy-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(atPath: path) }

    /// Writes files (relative path → contents) into a new folder and returns it.
    @discardableResult
    func folder(_ name: String, _ files: [String: String] = [:]) -> String {
        let dir = path + "/" + name
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (file, text) in files {
            let full = dir + "/" + file
            try! FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try! Data(text.utf8).write(to: URL(fileURLWithPath: full))
        }
        return dir
    }

    func write(_ data: Data, _ relative: String) {
        try! data.write(to: URL(fileURLWithPath: path + "/" + relative))
    }
}

let tokyoNight = """
mode = "dark"

accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"

background = "#1a1b26"
dark_background = "#13141c"
darker_background = "#0e0e14"
lighter_background = "#24283b"

foreground = "#a9b1d6"
dark_foreground = "#565f89"
light_foreground = "#b4bee6"
bright_foreground = "#c0caf5"

red = "#f7768e"
yellow = "#e0af68"
green = "#9ece6a"
cyan = "#449dab"
blue = "#7aa2f7"
magenta = "#ad8ee6"
"""

let latte = """
mode = "light"
accent = "#1e66f5"
selection = "#ccd0da"
background = "#eff1f5"
foreground = "#4c4f69"
dark_foreground = "#6c6f85"
red = "#d20f39"
yellow = "#df8e1d"
"""

let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])

// MARK: - Palette

@Suite struct PaletteTests {
    @Test func readsTheModernPalette() throws {
        let p = try OmarchyPalette.parse(tokyoNight)
        #expect(p.mode == "dark")
        #expect(p["background"] == RGBA(hex: "#1a1b26"))
        #expect(p["bright_foreground"] == RGBA(hex: "#c0caf5"))
        #expect(p.warnings.isEmpty)
    }

    @Test func legacyAliasesFillCanonicalNames() throws {
        let p = try OmarchyPalette.parse("""
        bg = "#101010"
        fg = "#eeeeee"
        dark_bg = "#080808"
        lighter_bg = "#202020"
        dark_fg = "#999999"
        light_fg = "#dddddd"
        bright_fg = "#ffffff"
        darker_bg = "#000000"
        """)
        #expect(p["background"] == RGBA(hex: "#101010"))
        #expect(p["foreground"] == RGBA(hex: "#eeeeee"))
        #expect(p["dark_background"] == RGBA(hex: "#080808"))
        #expect(p["darker_background"] == RGBA(hex: "#000000"))
        #expect(p["lighter_background"] == RGBA(hex: "#202020"))
        #expect(p["dark_foreground"] == RGBA(hex: "#999999"))
        #expect(p["light_foreground"] == RGBA(hex: "#dddddd"))
        #expect(p["bright_foreground"] == RGBA(hex: "#ffffff"))
        #expect(p["bg"] == nil, "aliases resolve to canonical names")
    }

    @Test func modernKeysWinOverLegacyAliases() throws {
        let p = try OmarchyPalette.parse("bg = \"#111111\"\nbackground = \"#222222\"\nforeground = \"#eeeeee\"\nfg = \"#000000\"\n")
        #expect(p["background"] == RGBA(hex: "#222222"))
        #expect(p["foreground"] == RGBA(hex: "#eeeeee"))
    }

    @Test func colorFormats() {
        #expect(OmarchyColor.parse("#abc") == RGBA(hex: "#aabbcc"))
        #expect(OmarchyColor.parse("#11223380") == RGBA(hex: "#11223380"))
        #expect(OmarchyColor.parse("rgba(33ccffee)") == RGBA(hex: "#33ccffee"))
        #expect(OmarchyColor.parse("rgb(33ccff)") == RGBA(hex: "#33ccff"))
        #expect(OmarchyColor.parse("rgba(255, 0, 0, 0.5)") == RGBA(1, 0, 0, 0.5))
        #expect(OmarchyColor.parse("rgba(300, 0, 0, 1)") == nil)
        #expect(OmarchyColor.parse("hyprland.active-border") == nil)
        #expect(OmarchyColor.parseList("rgba(33ccffee) rgba(00ff99ee) 45deg")?.count == 2)
    }

    @Test func gradientsAndOddValuesNeverFail() throws {
        let p = try OmarchyPalette.parse("""
        background = "#000000"
        foreground = "#ffffff"
        hyprland_active_border = "rgba(bb9af7ff) rgba(7aa2f7ff) 45deg"
        accent = "{{ blue }}"
        size = 12
        mode = "sepia"
        [extra]
        x = "#ffffff"
        """)
        #expect(p.gradients["hyprland_active_border"]?.count == 2)
        #expect(p["accent"] == nil)
        #expect(p.mode == nil)
        #expect(p.warnings.count >= 4, "\(p.warnings)")
    }

    @Test func malformedTOMLIsAFormatError() {
        #expect(throws: OmarchyFormatError.self) { try OmarchyPalette.parse("background = \"#000\n[[[") }
        #expect(throws: OmarchyFormatError.self) { try OmarchyPalette.parse(String(repeating: "#", count: 70_000)) }
    }

    @Test func shellLauncherSectionWithReferences() throws {
        let palette = try OmarchyPalette.parse(tokyoNight)
        let s = OmarchyShellStyle.parse("""
        [menu]
        background = "#000000"
        [launcher]
        background = "#101018"
        background-alpha = 0.5
        text = "#ffffff"
        border = "hyprland.active-border-foreground"
        selected-background = "accent"
        selected-background-alpha = 0.25
        selected-text = "{{ accent }}"
        """, palette: palette)
        #expect(s.section == "launcher")
        #expect(s.background == RGBA(hex: "#101018")!.with(alpha: 0.5))
        #expect(s.text == RGBA(hex: "#ffffff"))
        #expect(s.border == nil)
        #expect(s.selectedBackground == RGBA(hex: "#7aa2f7")!.with(alpha: 0.25))
        #expect(s.selectedText == nil)
        #expect(s.warnings.count == 2)
    }

    @Test func brokenShellTomlIsOnlyAWarning() throws {
        let s = OmarchyShellStyle.parse("[launcher\nbackground = ", palette: try OmarchyPalette.parse(tokyoNight))
        #expect(s.section == nil)
        #expect(s.warnings.count == 1)
    }
}

// MARK: - Adapter

@Suite struct AdapterTests {
    @Test func mapsTheDocumentedRoles() throws {
        let a = try OmarchyAdapter.normalize(name: "Tokyo Night", palette: try OmarchyPalette.parse(tokyoNight))
        #expect(a.appearance == "dark")
        #expect(a.background == RGBA(hex: "#1a1b26"))
        #expect(a.foreground == RGBA(hex: "#a9b1d6"))
        #expect(a.accent == RGBA(hex: "#7aa2f7"))
        #expect(a.selectionBackground == RGBA(hex: "#292e42"))
        #expect(a.border == [RGBA(hex: "#414868")!])
        #expect(a.separator == RGBA(hex: "#24283b"))
        #expect(a.error == RGBA(hex: "#f7768e"))
        #expect(a.validate().isEmpty)
    }

    @Test func textAlwaysReadsOnItsBackground() throws {
        for text in [tokyoNight, latte] {
            let a = try OmarchyAdapter.normalize(name: "x", palette: try OmarchyPalette.parse(text))
            #expect(RGBA.contrast(a.foreground, a.background) >= 4.5)
            #expect(RGBA.contrast(a.muted, a.background) >= 3)
            let sel = a.background.mixed(with: a.selectionBackground.with(alpha: 1), a.selectionBackground.a)
            #expect(RGBA.contrast(a.selectionForeground, sel) >= 4.5)
        }
    }

    @Test func lightThemes() throws {
        #expect(try OmarchyAdapter.normalize(name: "Latte", palette: try OmarchyPalette.parse(latte)).appearance == "light")
        // No mode key: the light.mode marker, else the background decides.
        let noMode = try OmarchyPalette.parse("background = \"#202020\"\nforeground = \"#eeeeee\"\n")
        #expect(try OmarchyAdapter.normalize(name: "x", palette: noMode, lightMarker: true).appearance == "light")
        let bright = try OmarchyPalette.parse("background = \"#fafafa\"\nforeground = \"#222222\"\n")
        #expect(try OmarchyAdapter.normalize(name: "x", palette: bright).appearance == "light")
    }

    @Test func dimTextIsMadeReadableRatherThanRejected() throws {
        let a = try OmarchyAdapter.normalize(name: "x", palette: try OmarchyPalette.parse("background = \"#000000\"\nforeground = \"#050505\"\n"))
        #expect(RGBA.contrast(a.foreground, a.background) >= 4.5)
    }

    @Test func missingOptionalColorsAreDerivedTheSameWayEveryTime() throws {
        let minimal = try OmarchyPalette.parse("background = \"#1e1e2e\"\nforeground = \"#cdd6f4\"\n")
        let a = try OmarchyAdapter.normalize(name: "Minimal", palette: minimal)
        let b = try OmarchyAdapter.normalize(name: "Minimal", palette: minimal)
        #expect(a == b)
        #expect(a.validate().isEmpty)
    }

    @Test func ansiSlotsStandInForNamedColors() throws {
        let p = try OmarchyPalette.parse("color0 = \"#000000\"\ncolor7 = \"#dddddd\"\ncolor4 = \"#3388ff\"\n")
        let a = try OmarchyAdapter.normalize(name: "x", palette: p)
        #expect(a.background == RGBA(hex: "#000000"))
        #expect(a.accent == RGBA(hex: "#3388ff"))
    }

    @Test func noBackgroundOrForegroundIsIncompatible() throws {
        #expect(throws: OmarchyFormatError.self) { try OmarchyAdapter.normalize(name: "x", palette: try OmarchyPalette.parse("accent = \"#ff0000\"")) }
        #expect(throws: OmarchyFormatError.self) { try OmarchyAdapter.normalize(name: "x", palette: try OmarchyPalette.parse("background = \"#000000\"")) }
    }

    @Test func shellOverridesWinOverThePalette() throws {
        let palette = try OmarchyPalette.parse(tokyoNight)
        let shell = OmarchyShellStyle.parse("[launcher]\nborder = \"rgba(33ccffee) rgba(00ff99ee) 45deg\"\nselected-text = \"#ffffff\"\n", palette: palette)
        let a = try OmarchyAdapter.normalize(name: "x", palette: palette, shell: shell)
        #expect(a.border.count == 2)
        #expect(a.selectionForeground == RGBA(hex: "#ffffff"))
    }

    @Test func catalogColorsGiveAPreview() throws {
        let p = OmarchyAdapter.palette(fromCatalogColors: ["background": "#1e1e2e", "foreground": "#cdd6f4", "accent": "#89b4fa",
                                                           "selection_background": "#45475a", "color1": "#f38ba8"])
        let a = try OmarchyAdapter.normalize(name: "Catppuccin", palette: p)
        #expect(a.selectionBackground == RGBA(hex: "#45475a"))
        #expect(a.error == RGBA(hex: "#f38ba8"))
    }
}

// MARK: - Library

@Suite struct LibraryTests {
    @Test func localImportCopiesOnlyTheAllowlist() throws {
        let s = Scratch()
        let src = s.folder("my-theme", [
            "colors.toml": tokyoNight, "shell.toml": "[launcher]\ntext = \"#ffffff\"\n", "hyprland.lua": "os.execute('rm -rf ~')",
            "install.sh": "#!/bin/sh\necho hi", "neovim.lua": "return {}", "backgrounds/1-sea.png": "not really a png",
        ])
        s.write(png, "my-theme/preview.png")
        let library = OmarchyLibrary(root: s.path + "/omarchy")
        let service = OmarchyThemeService(library: library)
        let rec = try service.importLocalTheme(src)
        #expect(rec.id == "local:my-theme")
        #expect(rec.name == "My")
        #expect(rec.adapterVersion == OmarchyAdapter.version)
        #expect(rec.compatibilityStatus == .compatible)
        #expect(rec.preview == "preview.png")
        let files = try FileManager.default.contentsOfDirectory(atPath: library.themeDirectory(rec.slug)).sorted()
        #expect(files == ["colors.toml", "preview.png", "shell.toml"])
        // Applying reads the cached appearance only.
        #expect(try service.appearance(id: rec.id).get() == rec.appearance)
        #expect(library.records().records.map(\.id) == ["local:my-theme"])
    }

    @Test func symlinksAreRefused() throws {
        let s = Scratch()
        let real = s.folder("real", ["colors.toml": tokyoNight])
        let src = s.folder("linked")
        try FileManager.default.createSymbolicLink(atPath: src + "/colors.toml", withDestinationPath: real + "/colors.toml")
        let library = OmarchyLibrary(root: s.path + "/omarchy")
        #expect(throws: OmarchyInstallError.self) { try library.install(from: src, source: OmarchySource(kind: .local, location: src), name: "Linked") }
        // A symlinked theme folder too.
        try FileManager.default.createSymbolicLink(atPath: s.path + "/folder-link", withDestinationPath: real)
        #expect(throws: OmarchyInstallError.self) { try library.install(from: s.path + "/folder-link", source: OmarchySource(kind: .local, location: "x"), name: "x") }
        // A symlinked optional file is skipped, the theme still installs.
        let partial = s.folder("partial", ["colors.toml": tokyoNight])
        try FileManager.default.createSymbolicLink(atPath: partial + "/shell.toml", withDestinationPath: "/etc/passwd")
        let rec = try library.install(from: partial, source: OmarchySource(kind: .local, location: partial), name: "Partial")
        #expect(rec.warnings.contains { $0.contains("shell.toml") })
        #expect(!FileManager.default.fileExists(atPath: library.themeDirectory(rec.slug) + "/shell.toml"))
        #expect(library.records().records.count == 1)
    }

    @Test func invalidImagesAreDropped() throws {
        let s = Scratch()
        let src = s.folder("t", ["colors.toml": tokyoNight, "preview.png": "<svg>not an image</svg>"])
        let rec = try OmarchyLibrary(root: s.path + "/o").install(from: src, source: OmarchySource(kind: .local, location: src), name: "T")
        #expect(rec.preview == nil)
        #expect(rec.warnings.contains { $0.contains("preview.png") })
    }

    @Test func notAThemeAndMalformedThemesInstallNothing() throws {
        let s = Scratch()
        let library = OmarchyLibrary(root: s.path + "/o")
        let empty = s.folder("empty", ["README.md": "hi"])
        let bad = s.folder("bad", ["colors.toml": "background = [[["])
        let noBackground = s.folder("no-background", ["colors.toml": "background = 12\nforeground = \"#ffffff\"\n"])
        for dir in [empty, bad, noBackground] {
            #expect(throws: OmarchyInstallError.self) { try library.install(from: dir, source: OmarchySource(kind: .local, location: dir), name: "x") }
        }
        #expect(library.records().records.isEmpty)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: library.themesDirectory)) ?? []).isEmpty)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: library.stagingDirectory)) ?? []).isEmpty, "staging is cleaned up")
    }

    @Test func failedUpdateKeepsTheInstalledVersion() throws {
        let s = Scratch()
        let library = OmarchyLibrary(root: s.path + "/o")
        let src = s.folder("theme", ["colors.toml": tokyoNight])
        let source = OmarchySource(kind: .local, location: src)
        let first = try library.install(from: src, source: source, name: "Theme")
        // Upstream changes its format: the new version no longer validates.
        try Data("palette = { background = 1 }\n".utf8).write(to: URL(fileURLWithPath: src + "/colors.toml"))
        #expect(throws: OmarchyInstallError.self) { try library.install(from: src, source: source, name: "Theme") }
        let after = library.record(id: first.id)
        #expect(after?.appearance == first.appearance)
        #expect(try String(contentsOfFile: library.themeDirectory(first.slug) + "/colors.toml", encoding: .utf8) == tokyoNight)
        // A good update replaces it.
        try Data(latte.utf8).write(to: URL(fileURLWithPath: src + "/colors.toml"))
        let updated = try library.install(from: src, source: source, name: "Theme")
        #expect(updated.appearance.appearance == "light")
        #expect(updated.installedAt == first.installedAt)
    }

    @Test func duplicateNamesFromDifferentSourcesCoexist() throws {
        let s = Scratch()
        let library = OmarchyLibrary(root: s.path + "/o")
        let a = s.folder("a/nord", ["colors.toml": tokyoNight])
        let b = s.folder("b/nord", ["colors.toml": latte])
        let one = try library.install(from: a, source: OmarchySource(kind: .official, location: "nord"), name: "Nord")
        let two = try library.install(from: b, source: OmarchySource(kind: .git, location: "https://github.com/x/omarchy-nord-theme"), name: "Nord")
        #expect(one.id != two.id && one.slug != two.slug)
        #expect(library.records().records.count == 2)
        #expect(library.record(id: one.id)?.appearance.appearance == "dark")
        #expect(library.record(id: two.id)?.appearance.appearance == "light")
    }

    @Test func corruptMetadataIsReportedNotFatal() throws {
        let s = Scratch()
        let library = OmarchyLibrary(root: s.path + "/o")
        let src = s.folder("t", ["colors.toml": tokyoNight])
        let rec = try library.install(from: src, source: OmarchySource(kind: .local, location: src), name: "T")
        try FileManager.default.createDirectory(atPath: library.metadataDirectory, withIntermediateDirectories: true)
        try Data("{ nope".utf8).write(to: URL(fileURLWithPath: library.metadataDirectory + "/broken.json"))
        let (records, problems) = library.records()
        #expect(records.map(\.id) == [rec.id])
        #expect(problems.count == 1)
        // The active theme's own metadata corrupted: applying fails cleanly.
        try Data("garbage".utf8).write(to: URL(fileURLWithPath: library.metadataDirectory + "/\(rec.slug).json"))
        let service = OmarchyThemeService(library: library)
        guard case .failure = service.appearance(id: rec.id) else { Issue.record("expected failure"); return }
    }

    @Test func corruptCatalogCacheIsIgnored() throws {
        let s = Scratch()
        let library = OmarchyLibrary(root: s.path + "/o")
        try FileManager.default.createDirectory(atPath: library.root, withIntermediateDirectories: true)
        try Data("[1,2".utf8).write(to: URL(fileURLWithPath: library.catalogCacheFile))
        #expect(OmarchyCatalogCache.load(library.catalogCacheFile) == OmarchyCatalogCache())
        let cache = OmarchyCatalogCache(official: OmarchyOfficialListing(branch: "quattro", revision: String(repeating: "a", count: 40), themes: ["nord"], fetchedAt: Date(timeIntervalSince1970: 0)))
        try cache.save(library.catalogCacheFile)
        #expect(OmarchyCatalogCache.load(library.catalogCacheFile) == cache)
    }

    @Test func adapterUpgradeKeepsTheLastGoodAppearance() throws {
        let s = Scratch()
        let library = OmarchyLibrary(root: s.path + "/o")
        let src = s.folder("t", ["colors.toml": tokyoNight])
        var rec = try library.install(from: src, source: OmarchySource(kind: .local, location: src), name: "T")
        // Pretend an older adapter wrote it, and its stored files went bad since.
        rec.adapterVersion = 0
        try library.save(rec)
        try Data("not = [toml".utf8).write(to: URL(fileURLWithPath: library.themeDirectory(rec.slug) + "/colors.toml"))
        let changed = library.revalidateOutdated()
        #expect(changed.count == 1)
        let after = try #require(library.record(id: rec.id))
        #expect(after.compatibilityStatus == .stale)
        #expect(after.appearance == rec.appearance)
        #expect(after.adapterVersion == OmarchyAdapter.version)
        #expect(library.revalidateOutdated().isEmpty, "not revalidated twice")
    }

    @Test func removeDeletesOnlyThatTheme() throws {
        let s = Scratch()
        let library = OmarchyLibrary(root: s.path + "/o")
        let a = try library.install(from: s.folder("a", ["colors.toml": tokyoNight]), source: OmarchySource(kind: .local, location: s.path + "/a"), name: "A")
        let b = try library.install(from: s.folder("b", ["colors.toml": latte]), source: OmarchySource(kind: .local, location: s.path + "/b"), name: "B")
        try library.remove(id: a.id)
        #expect(library.records().records.map(\.id) == [b.id])
        #expect(!FileManager.default.fileExists(atPath: library.themeDirectory(a.slug)))
        #expect(throws: OmarchyInstallError.self) { try library.remove(id: a.id) }
    }

    @Test func slugsAreSafeAndDistinct() {
        let a = OmarchyLibrary.slug(for: "git:github.com/a/../../etc:root")
        #expect(!a.contains("/") && !a.contains(".."))
        #expect(OmarchyLibrary.slug(for: "official:nord") != OmarchyLibrary.slug(for: "local:nord"))
        #expect(OmarchyLibrary.slug(for: "official:nord").hasPrefix("nord-"))
    }
}

// MARK: - Native isolation

@Suite struct NativeIsolationTests {
    /// Omarchy installs, updates, removals, and cleanup never touch Kadomo's
    /// own theme files, even when they sit next to Omarchy's storage.
    @Test func omarchyOperationsNeverAlterNativeThemes() throws {
        let s = Scratch()
        let native = s.folder("kadomo-menu/themes", ["rose.toml": "name = \"Rosé\"\nextends = \"kadomo-dark\"\n"])
        let nativeConfig = s.folder("kadomo-menu", ["config.toml": "theme = \"rose\"\n"])
        func snapshot() throws -> [String: Data] {
            var out: [String: Data] = [:]
            for dir in [native, nativeConfig] {
                for name in try FileManager.default.contentsOfDirectory(atPath: dir) {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: dir + "/" + name, isDirectory: &isDir)
                    if !isDir.boolValue { out[dir + "/" + name] = FileManager.default.contents(atPath: dir + "/" + name) }
                }
            }
            return out
        }
        let before = try snapshot()

        let library = OmarchyLibrary(root: s.path + "/kadomo-menu/integrations/omarchy")
        let src = s.folder("downloads/rose", ["colors.toml": tokyoNight])
        let rec = try library.install(from: src, source: OmarchySource(kind: .local, location: src), name: "Rose")
        try Data(latte.utf8).write(to: URL(fileURLWithPath: src + "/colors.toml"))
        try library.install(from: src, source: OmarchySource(kind: .local, location: src), name: "Rose")
        try Data("broken = [".utf8).write(to: URL(fileURLWithPath: src + "/colors.toml"))
        _ = try? library.install(from: src, source: OmarchySource(kind: .local, location: src), name: "Rose")
        library.revalidateOutdated()
        try library.remove(id: rec.id)
        library.clearStaging()
        try FileManager.default.removeItem(atPath: library.root)

        #expect(try snapshot() == before)
    }

    @Test func nativeThemeStillResolvesWhenOmarchyStorageIsMissingOrCorrupt() throws {
        let s = Scratch()
        let service = OmarchyThemeService(library: OmarchyLibrary(root: s.path + "/missing"))
        let state = ActiveThemeState(activeTheme: ThemeSelection(provider: .omarchy, themeId: "official:nord"))
        let base = ThemeLoader.resolve(BuiltinThemes.defaultID, sources: BuiltinThemes.sources).0!
        let r = ActiveThemeResolver.resolve(state, native: { (base, []) }, external: { sel in
            service.appearance(id: sel.themeId).map { $0.theme(id: sel.themeId, base: base) }
        })
        #expect(r.theme == base)
        #expect(r.fellBack)
    }
}

// MARK: - Git and catalogs

@Suite struct SourceTests {
    @Test func gitURLs() throws {
        let plain = try OmarchyGitLocation.parse("https://github.com/OldJobobo/omarchy-lumon-theme.git")
        #expect(plain.repository == "https://github.com/OldJobobo/omarchy-lumon-theme")
        #expect(plain.ref == nil && plain.subpath == nil)
        #expect(plain.themeName == "Lumon")
        let tree = try OmarchyGitLocation.parse("https://github.com/omacom/omarchy/tree/v4.0.6/themes/catppuccin.git")
        #expect(tree.repository == "https://github.com/omacom/omarchy")
        #expect(tree.ref == "v4.0.6")
        #expect(tree.subpath == "themes/catppuccin")
        #expect(tree.themeName == "Catppuccin")
        let other = try OmarchyGitLocation.parse("https://codeberg.org/me/omarchy-blue-theme")
        #expect(other.themeName == "Blue")
    }

    @Test func unsafeGitURLsAreRefused() {
        for url in ["git@github.com:a/b.git", "ext::sh -c touch% /tmp/x", "file:///etc", "http://github.com/a/b",
                    "https://user:pw@github.com/a/b", "https://github.com/a", "https://github.com/a/b?x=1",
                    "https://github.com/-u/b", "https://github.com/a/b c", "", "https://github.com/a/../b"] {
            #expect(throws: OmarchyInstallError.self, "\(url)") { try OmarchyGitLocation.parse(url) }
        }
    }

    @Test func sourceIDsIncludeTheProvidersIdentity() {
        #expect(OmarchySource(kind: .official, location: "nord").themeID == "official:nord")
        #expect(OmarchySource(kind: .git, location: "https://github.com/A/Omarchy-Nord-Theme.git").themeID == "git:github.com/a/omarchy-nord-theme:root")
        #expect(OmarchySource(kind: .git, location: "https://github.com/a/b", subpath: "themes/x").themeID == "git:github.com/a/b:themes/x")
        #expect(OmarchySource(kind: .local, location: "/Users/me/Themes/Nord").themeID == "local:nord")
    }

    @Test func officialListingParses() throws {
        #expect(try OmarchyCatalogFormat.defaultBranch(Data(#"{"default_branch":"quattro","x":1}"#.utf8)) == "quattro")
        let sha = String(repeating: "ab", count: 20)
        #expect(try OmarchyCatalogFormat.commit(Data("{\"sha\":\"\(sha)\"}".utf8)) == sha)
        let folders = try OmarchyCatalogFormat.themeFolders(Data(#"[{"name":"nord","type":"dir"},{"name":"README.md","type":"file"},{"name":"../x","type":"dir"},{"name":"tokyo-night","type":"dir"}]"#.utf8))
        #expect(folders == ["nord", "tokyo-night"])
    }

    @Test func upstreamFormatChangesAreCleanErrors() {
        #expect(throws: OmarchyInstallError.self) { try OmarchyCatalogFormat.defaultBranch(Data(#"{"branch":"main"}"#.utf8)) }
        #expect(throws: OmarchyInstallError.self) { try OmarchyCatalogFormat.defaultBranch(Data(#"{"default_branch":"--upload-pack=x"}"#.utf8)) }
        #expect(throws: OmarchyInstallError.self) { try OmarchyCatalogFormat.themeFolders(Data(#"{"message":"Not Found"}"#.utf8)) }
        #expect(throws: OmarchyInstallError.self) { try OmarchyCatalogFormat.themeFolders(Data("[]".utf8)) }
        #expect(throws: OmarchyInstallError.self) { try OmarchyCatalogFormat.community(Data(#"{"items":[]}"#.utf8)) }
        #expect(throws: OmarchyInstallError.self) { try OmarchyCatalogFormat.community(Data(#"{"themes":[{"title":"x"}]}"#.utf8)) }
        #expect(throws: OmarchyInstallError.self) { try OmarchyCatalogFormat.community(Data("<html>".utf8)) }
    }

    @Test func communityCatalogParses() throws {
        let json = #"""
        {"count":2,"themes":[
          {"slug":"catppuccin","name":"Catppuccin","author":"omacom","repository":"https://github.com/omacom/omarchy/tree/v4.0.6/themes/catppuccin",
           "builtin":true,"colors":{"background":"#1e1e2e","foreground":"#cdd6f4"},"new_field":{"a":1}},
          {"slug":"lumon","name":"Lumon","description":"Cold","author":"OldJobobo","repository":"https://github.com/OldJobobo/omarchy-lumon-theme",
           "builtin":false,"security_warnings":["suspicious file: install.sh"]},
          {"slug":"evil","name":"Evil","repository":"ext::sh -c x"}
        ]}
        """#
        let themes = try OmarchyCatalogFormat.community(Data(json.utf8))
        #expect(themes.map(\.slug) == ["catppuccin", "lumon"])
        #expect(themes[0].builtin && themes[0].colors["background"] == "#1e1e2e")
        #expect(themes[1].securityWarnings.count == 1)
    }

    @Test func bundledCommunityThemesJoinTheCatalogOnce() throws {
        let catalog = try OmarchyCatalogFormat.community(Data(#"{"themes":[{"slug":"lumon","name":"Lumon","repository":"https://github.com/OldJobobo/omarchy-lumon-theme"}]}"#.utf8))
        let merged = OmarchyCatalogFormat.withBundled(catalog)
        #expect(merged.map(\.slug) == ["lumon", "robzee84"])
        #expect(merged.allSatisfy { OmarchyNames.isValid($0.slug) && $0.repository.hasPrefix("https://") })
        let listed = OmarchyCommunityTheme(slug: "robzee84", name: "Robzee 84", author: nil, description: nil,
                                           repository: "https://github.com/robzolkos/omarchy-robzee84-theme", builtin: false,
                                           previewURL: nil, colors: [:], securityWarnings: [])
        #expect(OmarchyCatalogFormat.withBundled([listed]).map(\.name) == ["Robzee 84"])
    }

    @Test func officialRepositoryLinksAreSentToTheOfficialInstaller() {
        let service = OmarchyThemeService(library: OmarchyLibrary(root: Scratch().path))
        #expect(throws: OmarchyInstallError.self) { try service.installFromGit("https://github.com/omacom/omarchy/tree/quattro/themes/nord") }
    }

    @Test func imageSniffing() {
        #expect(SafeThemeCopy.isImage(png))
        #expect(SafeThemeCopy.isImage(Data([0xFF, 0xD8, 0xFF, 0xE0])))
        #expect(SafeThemeCopy.isImage(Data("RIFF\0\0\0\0WEBPVP8 ".utf8)))
        #expect(!SafeThemeCopy.isImage(Data("<svg/>".utf8)))
    }
}

// MARK: - Upstream (tools/omarchy-compat.sh)

/// Runs only with OMARCHY_FIXTURES set to a folder tools/omarchy-compat.sh filled.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["OMARCHY_FIXTURES"] != nil))
struct LiveUpstreamTests {
    let dir = ProcessInfo.processInfo.environment["OMARCHY_FIXTURES"] ?? ""

    @Test func everyOfficialThemeInstalls() throws {
        let s = Scratch()
        let library = OmarchyLibrary(root: s.path + "/o")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir + "/official").sorted()
        #expect(names.count > 10)
        var failed: [String] = []
        for name in names {
            do {
                let rec = try library.install(from: dir + "/official/" + name, source: OmarchySource(kind: .official, location: name),
                                              name: OmarchyNames.display(name))
                let a = rec.appearance
                print("  \(name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(a.appearance)  bg \(a.background.hexString)  fg \(a.foreground.hexString)  accent \(a.accent.hexString)  \(rec.warnings.count) notes")
            } catch { failed.append("\(name): \(error)") }
        }
        #expect(failed.isEmpty, "\(failed)")
    }

    @Test func communityCatalogParsesAndPreviews() throws {
        guard let data = FileManager.default.contents(atPath: dir + "/community.json") else { return }
        let themes = try OmarchyCatalogFormat.community(data)
        let previewable = themes.filter { (try? OmarchyAdapter.normalize(name: $0.name, palette: OmarchyAdapter.palette(fromCatalogColors: $0.colors))) != nil }
        print("  community: \(themes.count) themes, \(previewable.count) with a usable preview palette")
        #expect(themes.count > 50)
        #expect(previewable.count * 10 >= themes.count * 9)
    }
}

// MARK: - Desktop files

@Suite struct DesktopFilesTests {
    @Test func wallpapersBtopAndVSCodeAreKeptForTheDesktop() throws {
        let s = Scratch()
        let src = s.folder("t", ["colors.toml": tokyoNight, "btop.theme": "theme[main_bg]=\"#1a1b26\"\n",
                                 "vscode.json": "{\"name\": \"Tokyo Night\", \"extension\": \"enkia.tokyo-night\"}\n",
                                 "backgrounds/2-notes.txt": "hi", "backgrounds/intros/0-a.mp4": "video"])
        s.write(png, "t/backgrounds/0-road.png")
        s.write(Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2]), "t/backgrounds/1-sea.jpg")
        s.write(Data("not an image".utf8), "t/backgrounds/3-fake.png")
        s.write(Data([0, 0, 0, 0x18]) + Data("ftypmp42".utf8), "t/backgrounds/4-clip.mp4")
        try FileManager.default.createSymbolicLink(atPath: src + "/backgrounds/5-link.png", withDestinationPath: "/etc/passwd")
        let library = OmarchyLibrary(root: s.path + "/o")
        let rec = try library.install(from: src, source: OmarchySource(kind: .local, location: src), name: "T")
        let dir = library.themeDirectory(rec.slug)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir + "/backgrounds").sorted() == ["0-road.png", "1-sea.jpg"])
        #expect(FileManager.default.fileExists(atPath: dir + "/btop.theme"))
        #expect(FileManager.default.fileExists(atPath: dir + "/vscode.json"))
        #expect(rec.preview == "backgrounds/0-road.png")
        #expect(rec.files == OmarchyLibrary.filesVersion)
        #expect(rec.warnings.contains { $0.contains("3-fake.png") && $0.contains("5-link.png") })
    }

    @Test func officialBackgroundListing() {
        let json = #"[{"name":"0-a.png","type":"file","size":10},{"name":"intros","type":"dir"},{"name":"b.mp4","type":"file","size":1},{"name":".x.png","type":"file","size":1},{"name":"big.jpg","type":"file","size":999999999}]"#
        #expect(OmarchyCatalogFormat.backgroundFiles(Data(json.utf8)) == ["0-a.png"])
        #expect(OmarchyCatalogFormat.backgroundFiles(Data("{}".utf8)).isEmpty)
    }

    @Test func realThemeFolder() throws {
        guard let path = ProcessInfo.processInfo.environment["OMARCHY_THEME_DIR"] else { return }
        let s = Scratch()
        let rec = try OmarchyLibrary(root: s.path + "/o").install(from: path, source: OmarchySource(kind: .local, location: path), name: "Real")
        print("files:", try FileManager.default.contentsOfDirectory(atPath: s.path + "/o/themes/" + rec.slug + "/backgrounds"), rec.warnings)
    }
}

@Suite struct IncompleteInstallTests {
    @Test func aFailedWallpaperFetchIsRecordedForRetry() throws {
        let s = Scratch()
        let src = s.folder("t", ["colors.toml": tokyoNight])
        let rec = try OmarchyLibrary(root: s.path + "/o").install(from: src, source: OmarchySource(kind: .official, location: "t"), name: "T",
                                                                complete: false, notes: ["wallpapers not fetched (rate limit)"])
        #expect(rec.files == 1, "an older files version, so Update and applying fetch it again")
        #expect(rec.warnings.first == "wallpapers not fetched (rate limit)")
    }

    @Test func gitLFSPlaceholdersAreNamed() throws {
        let s = Scratch()
        let src = s.folder("t", ["colors.toml": tokyoNight,
                                 "backgrounds/0-big.jpg": "version https://git-lfs.github.com/spec/v1\noid sha256:abc\nsize 9999999\n"])
        let rec = try OmarchyLibrary(root: s.path + "/o").install(from: src, source: OmarchySource(kind: .local, location: src), name: "T")
        #expect(rec.warnings.contains { $0.contains("Git LFS") })
    }
}

@Suite struct OlderThemeTests {
    static let osakaJade = """
    [colors]
    [colors.primary]
    background = '#111c18'
    foreground = '#C1C497'

    [colors.normal]
    black   = "#23372B"
    red     = "#FF5345"
    green   = "#549e6a"
    yellow  = "#459451"
    blue    = "#509475"
    magenta = "#D2689C"
    cyan    = "#2DD5B7"
    white   = "#F6F5DD"

    [colors.bright]
    black   = "#53685B"
    red     = "#db9f9c"
    green   = "#63b07a"
    yellow  = "#E5C736"
    blue    = "#ACD4CF"
    magenta = "#75bbb3"
    cyan    = "#8CD3CB"
    white   = "#9eebb3"

    [colors.cursor]
    text   = "#000000"
    cursor = "#D7C995"

    [terminal.shell]
    program = "/bin/sh"
    args = ["-c", "touch /tmp/kadomo-pwned"]
    """

    @Test func alacrittyPaletteBecomesColorsToml() throws {
        let toml = try OmarchyAlacritty.colorsTOML(Self.osakaJade)
        let p = try OmarchyPalette.parse(toml)
        #expect(p["background"] == RGBA(hex: "#111c18"))
        #expect(p["foreground"] == RGBA(hex: "#c1c497"))
        #expect(p["accent"] == RGBA(hex: "#509475"))
        #expect(p["muted"] == RGBA(hex: "#53685b"))
        #expect(p["color15"] == RGBA(hex: "#9eebb3"))
        #expect(p["cursor"] == RGBA(hex: "#d7c995"))
        #expect(!toml.contains("program") && !toml.contains("pwned"))
    }

    @Test func anAlacrittyOnlyThemeInstallsWithoutKeepingIt() throws {
        let s = Scratch()
        let src = s.folder("osaka", ["alacritty.toml": Self.osakaJade, "btop.theme": "theme[main_bg]=\"#111c18\"\n"])
        s.write(png, "osaka/preview.png")
        let library = OmarchyLibrary(root: s.path + "/o")
        let rec = try library.install(from: src, source: OmarchySource(kind: .git, location: "https://github.com/Justikun/omarchy-osaka-jade-theme"), name: "Osaka Jade")
        let files = try FileManager.default.contentsOfDirectory(atPath: library.themeDirectory(rec.slug)).sorted()
        #expect(files == ["btop.theme", "colors.toml", "preview.png"])
        #expect(rec.appearance.background == RGBA(hex: "#111c18"))
        #expect(rec.warnings.contains { $0.contains("alacritty.toml") })
    }

    @Test func aBrokenAlacrittyTomlIsRefused() {
        let s = Scratch()
        let src = s.folder("x", ["alacritty.toml": "[font]\nsize = 12\n"])
        #expect(throws: OmarchyInstallError.self) {
            try OmarchyLibrary(root: s.path + "/o").install(from: src, source: OmarchySource(kind: .local, location: src), name: "X")
        }
    }

    @Test func retiredOfficialThemesComeFromTheReleaseTheCatalogNames() {
        let service = OmarchyThemeService(library: OmarchyLibrary(root: Scratch().path))
        func entry(_ slug: String, _ repo: String, builtin: Bool = true) -> OmarchyCommunityTheme {
            OmarchyCommunityTheme(slug: slug, name: slug, author: nil, description: nil, repository: repo, builtin: builtin,
                                  previewURL: nil, colors: [:], securityWarnings: [])
        }
        #expect(service.officialRelease(of: entry("osaka-jade", "https://github.com/omacom/omarchy/tree/v4.0.6/themes/osaka-jade")) == "v4.0.6")
        #expect(service.officialRelease(of: entry("osaka-jade", "https://github.com/omacom/omarchy/tree/v4.0.6/themes/other")) == nil)
        #expect(service.officialRelease(of: entry("x", "https://github.com/someone/omarchy/tree/v1/themes/x")) == nil)
        #expect(service.officialRelease(of: entry("x", "https://github.com/a/omarchy-x-theme", builtin: false)) == nil)
    }

    @Test func aPinnedOfficialThemeDoesNotFollowOmarchy() async throws {
        let s = Scratch()
        let library = OmarchyLibrary(root: s.path + "/o")
        let src = s.folder("osaka-jade", ["colors.toml": tokyoNight])
        _ = try library.install(from: src, source: OmarchySource(kind: .official, location: "osaka-jade", ref: "v4.0.6"), name: "Osaka Jade")
        // Complete and pinned: no network, nothing to do.
        let result = try await OmarchyThemeService(library: library).updateTheme(id: "official:osaka-jade")
        #expect(result == .upToDate)
    }
}
