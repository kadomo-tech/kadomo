import Foundation
import KadomoMenuCore

/// The Kadomo theme manager (`theme-set`), which styles every app and the
/// wallpaper. Kadomo Menu asks it to show an external provider's theme
/// (`theme-set --external`) and to go back to Kadomo's own (`theme-set --native`).
/// Without the theme manager, an external theme styles only the launcher.
enum DesktopThemes {
    /// `$KADOMO_MENU_THEME_SET` (empty turns this off; tests point it at a
    /// stub), else the theme manager's `~/.local/bin/theme-set`.
    static var themeSet: String? {
        if let path = ProcessInfo.processInfo.environment["KADOMO_MENU_THEME_SET"] {
            return path.isEmpty ? nil : (FileManager.default.isExecutableFile(atPath: Paths.expand(path)) ? Paths.expand(path) : nil)
        }
        let path = NSHomeDirectory() + "/.local/bin/theme-set"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    static var available: Bool { themeSet != nil }

    /// Styles every app with a theme folder kept by another provider. Runs in
    /// the background; `done` gets nil or what went wrong.
    static func applyExternal(folder: String, name: String, label: String, done: @escaping @MainActor (String?) -> Void) {
        guard let bin = themeSet else { done(nil); return }
        Executor.run(.exec(path: bin, args: ["--external", folder, name, label]), title: "Theme \(label)") { error in
            done(error.map { message in
                message.contains("not a theme name: '--external'")
                    ? "The theme manager is too old to show Omarchy themes on every app; run its ./install.sh again"
                    : message
            })
        }
    }

    /// Back to the last of Kadomo's own desktop themes. Does nothing when one
    /// is already showing.
    static func restoreNative(done: @escaping @MainActor (String?) -> Void = { _ in }) {
        guard let bin = themeSet else { done(nil); return }
        Executor.run(.exec(path: bin, args: ["--native"]), title: "Kadomo theme") { done($0) }
    }
}
