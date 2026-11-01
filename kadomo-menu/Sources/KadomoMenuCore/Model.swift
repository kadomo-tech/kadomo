import Foundation

/// Everything the launcher shows is an `Item`: categories, applications,
/// system actions, settings panes, themes, and user commands all flow
/// through the same search and navigation.
public enum ItemKind: String, Sendable, Codable {
    case category
    case app
    case action
    /// Read-only rows, such as the keyboard reference.
    case info
}

public enum IconRef: Sendable, Hashable {
    case none
    /// An SF Symbol name.
    case symbol(String)
    /// The Finder icon of a file or bundle path.
    case file(String)
    /// A literal glyph (an emoji or a Nerd Font character).
    case glyph(String)
}

public enum Action: Sendable, Hashable {
    case none
    /// Enter a category.
    case navigate
    case openApp(path: String, newInstance: Bool)
    /// Run an executable with an argument array. No shell is involved.
    case exec(path: String, args: [String])
    /// Run a script through an explicit shell. Only from user configuration.
    case shell(script: String, shell: String)
    case openURL(String)
    case openPath(String)
    case revealInFinder(String)
    case copy(String)
    /// Handled by the launcher itself (reload, quit, theme.set:<id>, ...).
    case builtin(String)
}

public struct SecondaryAction: Sendable, Hashable {
    public var title: String
    public var action: Action
    public var icon: IconRef
    public var hint: String?
    public var confirm: Bool

    public init(_ title: String, _ action: Action, icon: IconRef = .none, hint: String? = nil, confirm: Bool = false) {
        self.title = title
        self.action = action
        self.icon = icon
        self.hint = hint
        self.confirm = confirm
    }
}

public struct Item: Sendable, Identifiable, Hashable {
    /// Stable identifier, unique across sources: `app:<bundle id>`, `sys:lock`, `cmd:<id>`, a category id.
    public var id: String
    public var title: String
    public var subtitle: String
    public var kind: ItemKind
    /// The category this item lives in. `Catalog.rootID` for the home menu.
    public var parent: String
    /// More categories that also list this item (an app under Commands).
    public var alsoIn: [String]
    public var icon: IconRef
    public var keywords: [String]
    public var aliases: [String]
    public var action: Action
    public var secondary: [SecondaryAction]
    /// Text shown at the right edge, like a key chord.
    public var hint: String?
    /// Ask before running the primary action.
    public var confirm: Bool
    /// Keep the launcher open after running (volume up, theme switch).
    public var keepOpen: Bool
    /// Position within its category. Ties sort by title.
    public var order: Int
    /// Where the item came from: apps, system, user, kadomo, ...
    public var source: String
    /// Whether global search finds it. Categories of generated rows set this false.
    public var searchable: Bool
    /// A category whose search field is an input box: typing inside it does not
    /// filter its rows, and its actions read the text (a Git URL, say).
    public var takesInput: Bool
    /// A bundle id: while that app runs, the row is marked running (OmniWM under Services).
    public var runningApp: String?
    /// A section label in a read-only list (the Keybinds reference): drawn small, never selected or searched.
    public var isHeading = false

    public init(
        id: String, title: String, subtitle: String = "", kind: ItemKind = .action,
        parent: String = Catalog.rootID, alsoIn: [String] = [], icon: IconRef = .none,
        keywords: [String] = [], aliases: [String] = [], action: Action = .none,
        secondary: [SecondaryAction] = [], hint: String? = nil, confirm: Bool = false,
        keepOpen: Bool = false, order: Int = 0, source: String = "builtin", searchable: Bool = true, takesInput: Bool = false,
        runningApp: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.parent = parent
        self.alsoIn = alsoIn
        self.icon = icon
        self.keywords = keywords
        self.aliases = aliases
        self.action = kind == .category && action == .none ? .navigate : action
        self.secondary = secondary
        self.hint = hint
        self.confirm = confirm
        self.keepOpen = keepOpen
        self.order = order
        self.source = source
        self.searchable = searchable
        self.takesInput = takesInput
        self.runningApp = runningApp
    }

    public static func category(_ id: String, _ title: String, subtitle: String = "", icon: String, parent: String = Catalog.rootID, order: Int = 0, keywords: [String] = []) -> Item {
        Item(id: id, title: title, subtitle: subtitle, kind: .category, parent: parent, icon: .symbol(icon), keywords: keywords, order: order, source: "builtin")
    }
}

/// The built-in top-level structure. Providers attach items under these ids.
public enum Categories {
    public static let apps = "apps"
    public static let appearance = "appearance"
    public static let themes = "appearance/themes"
    public static let keybinds = "keybinds"
    public static let services = "services"
    public static let about = "about"
    public static let system = "system"
    public static let settings = "settings"

    public static let home: [Item] = [
        .category(apps, "Apps", subtitle: "Launch and manage applications", icon: "square.grid.2x2", order: 0, keywords: ["apps", "programs"]),
        .category(appearance, "Appearance", subtitle: "Themes and dark mode", icon: "paintpalette", order: 1, keywords: ["theme", "look"]),
        .category(themes, "Kadomo Themes", subtitle: "Kadomo's own themes", icon: "swatchpalette", parent: appearance, order: 0, keywords: ["theme"]),
        .category(keybinds, "Keybinds", subtitle: "Keyboard reference", icon: "keyboard", order: 2, keywords: ["shortcuts", "keys", "help"]),
        .category(services, "Services", subtitle: "Background services and daemons", icon: "server.rack", order: 3, keywords: ["daemons", "background"]),
        .category(about, "About", subtitle: "Kadomo Menu settings and info", icon: "info.circle", order: 5, keywords: ["kadomo", "launcher", "preferences", "reload", "quit"]),
        .category(system, "System", subtitle: "Lock, sleep, sound, power, settings", icon: "power", order: 6, keywords: ["power", "shutdown", "sound"]),
        .category(settings, "Settings", subtitle: "macOS settings panes", icon: "gearshape", parent: system, order: 100, keywords: ["preferences", "system settings"]),
    ]
}
