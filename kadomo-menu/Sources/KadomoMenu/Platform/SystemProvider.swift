import AppKit
import KadomoMenuCore

/// Built-in commands: system power and sound, macOS settings panes,
/// appearance, the keyboard reference, and the
/// launcher's own settings. Only public APIs and stock tools.
enum SystemProvider {
    static func osascript(_ source: String) -> Action { .exec(path: "/usr/bin/osascript", args: ["-e", source]) }

    static func system() -> [Item] {
        let p = Categories.system
        return [
            Item(id: "sys:lock", title: "Lock Screen", subtitle: "Turn off the display; locks when a password is required",
                 parent: p, icon: .symbol("lock"), keywords: ["lock", "away"], action: .exec(path: "/usr/bin/pmset", args: ["displaysleepnow"]), order: 0),
            Item(id: "sys:sleep", title: "Sleep", subtitle: "Put this Mac to sleep", parent: p, icon: .symbol("moon.zzz"),
                 keywords: ["suspend"], action: .exec(path: "/usr/bin/pmset", args: ["sleepnow"]), order: 1),
            Item(id: "sys:display-off", title: "Turn Off Display", subtitle: "Sleep the display only", parent: p, icon: .symbol("display"),
                 keywords: ["screen off", "monitor"], action: .exec(path: "/usr/bin/pmset", args: ["displaysleepnow"]), order: 2),
            Item(id: "sys:screensaver", title: "Start Screen Saver", parent: p, icon: .symbol("sparkles.tv"),
                 action: .exec(path: "/usr/bin/open", args: ["-a", "ScreenSaverEngine"]), order: 3),
            Item(id: "sys:mute", title: "Mute / Unmute", subtitle: "Toggle the output volume", parent: p, icon: .symbol("speaker.slash"),
                 keywords: ["sound", "audio", "silence", "volume"],
                 action: osascript("set volume output muted not (output muted of (get volume settings))"), keepOpen: true, order: 10),
            Item(id: "sys:volume-up", title: "Volume Up", parent: p, icon: .symbol("speaker.wave.3"), keywords: ["sound", "louder", "audio"],
                 action: osascript("set volume output volume ((output volume of (get volume settings)) + 10)"), keepOpen: true, order: 11),
            Item(id: "sys:volume-down", title: "Volume Down", parent: p, icon: .symbol("speaker.wave.1"), keywords: ["sound", "quieter", "audio"],
                 action: osascript("set volume output volume ((output volume of (get volume settings)) - 10)"), keepOpen: true, order: 12),
            Item(id: "sys:restart", title: "Restart…", subtitle: "Shows the macOS restart dialog", parent: p, icon: .symbol("arrow.clockwise"),
                 keywords: ["reboot", "power"], action: osascript("tell application \"loginwindow\" to «event aevtrrst»"), order: 20),
            Item(id: "sys:shutdown", title: "Shut Down…", subtitle: "Shows the macOS shut down dialog", parent: p, icon: .symbol("power"),
                 keywords: ["power off", "turn off", "halt"], action: osascript("tell application \"loginwindow\" to «event aevtrsdn»"), order: 21),
            Item(id: "sys:logout", title: "Log Out…", subtitle: "Shows the macOS log out dialog", parent: p, icon: .symbol("rectangle.portrait.and.arrow.right"),
                 keywords: ["sign out", "logoff"], action: osascript("tell application \"loginwindow\" to «event aevtrlgo»"), order: 22),
        ]
    }

    /// macOS 13+ System Settings panes by their public URL identifiers.
    static let panes: [(String, String, String, [String])] = [
        ("Wi-Fi", "com.apple.wifi-settings-extension", "wifi", ["wifi", "wireless", "network", "internet"]),
        ("Bluetooth", "com.apple.BluetoothSettings", "dot.radiowaves.left.and.right", ["wireless", "headphones", "airpods"]),
        ("Network", "com.apple.Network-Settings.extension", "network", ["ethernet", "vpn", "internet"]),
        ("Displays", "com.apple.Displays-Settings.extension", "display", ["monitor", "screen", "resolution", "brightness"]),
        ("Sound", "com.apple.Sound-Settings.extension", "speaker.wave.2", ["audio", "volume", "output", "input", "microphone"]),
        ("Battery", "com.apple.Battery-Settings.extension", "battery.100", ["power", "energy", "charging"]),
        ("Keyboard", "com.apple.Keyboard-Settings.extension", "keyboard", ["shortcuts", "input sources", "key repeat"]),
        ("Trackpad", "com.apple.Trackpad-Settings.extension", "rectangle.and.hand.point.up.left", ["gestures", "mouse", "scroll"]),
        ("Appearance", "com.apple.Appearance-Settings.extension", "circle.lefthalf.filled", ["dark mode", "light mode", "accent"]),
        ("Wallpaper", "com.apple.Wallpaper-Settings.extension", "photo", ["background", "desktop picture"]),
        ("Desktop & Dock", "com.apple.Desktop-Settings.extension", "dock.rectangle", ["dock", "mission control", "stage manager", "hot corners"]),
        ("Notifications", "com.apple.Notifications-Settings.extension", "bell", ["alerts", "badges"]),
        ("Focus", "com.apple.Focus-Settings.extension", "moon", ["do not disturb", "dnd"]),
        ("Privacy & Security", "com.apple.settings.PrivacySecurity.extension", "hand.raised", ["permissions", "accessibility", "filevault", "gatekeeper"]),
        ("Login Items", "com.apple.LoginItems-Settings.extension", "list.bullet", ["startup", "launch at login", "background items"]),
        ("General", "com.apple.General-Settings.extension", "gearshape", ["about this mac", "storage"]),
        ("Software Update", "com.apple.Software-Update-Settings.extension", "arrow.down.circle", ["update", "upgrade", "macos"]),
        ("Accessibility", "com.apple.Accessibility-Settings.extension", "accessibility", ["voiceover", "zoom", "reduce motion", "contrast"]),
        ("Control Center", "com.apple.ControlCenter-Settings.extension", "switch.2", ["menu bar"]),
        ("Lock Screen", "com.apple.Lock-Screen-Settings.extension", "lock.display", ["screen saver", "password"]),
        ("Users & Groups", "com.apple.Users-Groups-Settings.extension", "person.2", ["accounts", "users"]),
        ("Date & Time", "com.apple.Date-Time-Settings.extension", "clock", ["clock", "timezone"]),
        ("Printers & Scanners", "com.apple.Print-Scan-Settings.extension", "printer", ["printer", "scanner"]),
    ]

    static func settings() -> [Item] {
        panes.enumerated().map { n, pane in
            Item(id: "set:\(pane.1)", title: pane.0, subtitle: "System Settings", parent: Categories.settings, icon: .symbol(pane.2),
                 keywords: pane.3 + ["settings", "preferences"], action: .openURL("x-apple.systempreferences:\(pane.1)"), order: n)
        }
    }

    /// Appearance items that only make sense for the launcher's own themes.
    static let launcherThemeItems: Set<String> = ["look:customize-theme", "look:themes-folder"]

    static func appearance() -> [Item] {
        let p = Categories.appearance
        return [
            Item(id: "look:dark-mode", title: "Toggle Dark Mode", subtitle: "Switch macOS between light and dark (asks for Automation once)",
                 parent: p, icon: .symbol("circle.lefthalf.filled"), keywords: ["dark", "light", "night", "theme"],
                 action: osascript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"),
                 keepOpen: true, order: 1),
            Item(id: "look:customize-theme", title: "Customize Current Theme…", subtitle: "Create an editable copy in themes/",
                 parent: p, icon: .symbol("paintbrush"), keywords: ["edit theme", "colors", "fonts"], action: .builtin("theme.customize"), order: 3),
            Item(id: "look:themes-folder", title: "Open Themes Folder", parent: p, icon: .symbol("folder"),
                 action: .builtin("folder.themes"), order: 4),
        ]
    }

    /// The launcher's own keys, under a Kadomo Menu heading. They sort after `[[keybind]]` rows
    /// from commands files (the window manager's keys, orders below 1000).
    static func keybinds(keys: KeyMap, hotkey: String, prefixes: [String: String], catalogTitle: (String) -> String) -> [Item] {
        let p = Categories.keybinds
        var heading = Item(id: "key:heading-kadomo-menu", title: "Kadomo Menu", kind: .info, parent: p, order: 998, searchable: false)
        heading.isHeading = true
        var items: [Item] = [
            heading,
            Item(id: "key:hotkey", title: "Open Kadomo Menu", subtitle: "Global shortcut (hotkey in config.toml)", kind: .info, parent: p,
                 icon: .symbol("command"), hint: KeyChord.parse(hotkey)?.symbol, order: 999),
        ]
        for (n, command) in KeyCommand.allCases.enumerated() {
            let chords = keys.chords[command] ?? []
            items.append(Item(id: "key:\(command.rawValue)", title: command.summary, kind: .info, parent: p, icon: .symbol("keyboard"),
                              keywords: chords.map(\.description), hint: chords.prefix(2).map(\.symbol).joined(separator: "  "), order: 1000 + n))
        }
        items.append(Item(id: "key:backspace", title: "Back (with empty search)", kind: .info, parent: p, icon: .symbol("keyboard"),
                          hint: "⌫", order: 1050))
        for (n, (prefix, category)) in prefixes.sorted(by: { $0.key < $1.key }).enumerated() {
            items.append(Item(id: "key:prefix-\(prefix)", title: "Search \(catalogTitle(category)) only", subtitle: "Start the search with \(prefix)",
                              kind: .info, parent: p, icon: .symbol("magnifyingglass"), hint: prefix, order: 1060 + n))
        }
        return items
    }

    static func about(version: String, loginEnabled: Bool?, themeName: String, itemCount: Int) -> [Item] {
        let p = Categories.about
        var items: [Item] = [
            Item(id: "about:version", title: "Kadomo Menu \(version)", subtitle: "\(itemCount) items · theme \(themeName)", kind: .info,
                 parent: p, icon: .symbol("info.circle"), order: 0),
            Item(id: "about:reload", title: "Reload Configuration", subtitle: "Re-read config, themes, commands, and apps",
                 parent: p, icon: .symbol("arrow.triangle.2.circlepath"), keywords: ["refresh", "rescan"], action: .builtin("reload"), order: 1),
            Item(id: "about:edit-config", title: "Edit config.toml", parent: p, icon: .symbol("doc.text"), keywords: ["settings", "preferences", "configure"],
                 action: .builtin("config.edit"), order: 2),
            Item(id: "about:config-folder", title: "Open Config Folder", subtitle: "~/.config/kadomo-menu", parent: p, icon: .symbol("folder"),
                 action: .builtin("folder.config"), order: 3),
        ]
        if let loginEnabled {
            items.append(Item(id: "about:login", title: loginEnabled ? "Launch at Login: On" : "Launch at Login: Off",
                              subtitle: "Toggle starting with macOS", parent: p, icon: .symbol("power.circle"), keywords: ["startup", "autostart"],
                              action: .builtin("login.toggle"), keepOpen: true, order: 4))
        }
        items.append(Item(id: "about:diagnostics", title: "Copy Diagnostics", subtitle: "Status, timings, and config problems to the clipboard",
                          parent: p, icon: .symbol("stethoscope"), keywords: ["debug", "status", "benchmark"], action: .builtin("diagnostics.copy"), order: 5))
        items.append(Item(id: "about:quit", title: "Quit Kadomo Menu", parent: p, icon: .symbol("xmark.circle"), keywords: ["exit", "stop"],
                          action: .builtin("quit"), order: 10))
        return items
    }
}
