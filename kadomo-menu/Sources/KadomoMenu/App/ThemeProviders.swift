import AppKit
import KadomoMenuCore
#if canImport(KadomoOmarchy)
import KadomoOmarchy
#endif

/// A theme provider other than Kadomo's own. The launcher talks to it only
/// through this protocol: it supplies menu rows, turns its theme ids into a
/// renderable `Theme` (through the appearance contract), and runs its own
/// commands. Kadomo's native themes never go through here.
protocol ExternalThemeProvider: AnyObject {
    var id: ThemeProviderID { get }
    /// Rows changed (an install finished, a catalog loaded).
    var onChange: (() -> Void)? { get set }
    /// A result to show: message, and whether it is an error.
    var notify: ((String, Bool) -> Void)? { get set }
    /// Make one of this provider's themes the active one. Returns an error message.
    var activate: ((String) -> String?)? { get set }
    /// Bumped by the launcher on every theme change, so a slow install does not
    /// override a choice made while it ran.
    var themeGeneration: (() -> Int)? { get set }

    /// Called once the launcher is up; never on the startup path.
    func start()
    /// Rows for the menu. `activeThemeID` is this provider's active theme, if it is the active provider.
    func items(activeThemeID: String?) -> [Item]
    /// The theme to draw for one of this provider's ids, from cached data only.
    func theme(for themeID: String, base: Theme) -> Result<Theme, ExternalThemeError>
    /// The folder of an installed theme, a theme-manager name for it, and its
    /// label, for showing it on every app (`theme-set --external`).
    func desktopTheme(for themeID: String) -> (folder: String, name: String, label: String)?
    /// Fetches an installed theme again, in the background, when it was
    /// installed without everything the desktop uses (its wallpapers, say).
    /// It is applied again when that finishes, if it is still the active theme.
    func completeForDesktop(_ themeID: String)
    /// A theme to show while `itemID` is selected, or nil. Never touches disk or network.
    func previewTheme(forItem itemID: String, base: Theme) -> Theme?
    /// Runs one of its launcher commands (`<provider>.<verb>:<arg>`). Returns true to keep the launcher open.
    func perform(_ verb: String, _ arg: String, input: String?) -> Bool
    /// `kadomo-menu <provider> ...`
    func handleCLI(_ args: [String]) async -> IPCResponse
    func statusLines(activeThemeID: String?) -> [String]
}

enum ThemeProviders {
    /// The optional providers built into this binary and turned on in config.
    static func make(config: AppConfig) -> ExternalThemeProvider? {
        #if canImport(KadomoOmarchy)
        return config.omarchyEnabled ? OmarchyIntegration() : nil
        #else
        return nil
        #endif
    }

    static var builtIn: Bool {
        #if canImport(KadomoOmarchy)
        return true
        #else
        return false
        #endif
    }
}

/// Omarchy's category ids, known to the launcher only for tests and the CLI.
enum OmarchyCategory {
    static let root = "appearance/omarchy"
    static let installed = root + "/installed"
    static let git = root + "/git"
}
