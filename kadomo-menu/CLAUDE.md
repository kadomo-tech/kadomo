# kadomo-menu

Keyboard-first macOS launcher. Swift 6 + AppKit, SwiftPM, no dependencies.

## Layout

- `Sources/KadomoMenuCore/` platform-free: TOML parser, config/theme schema, search and ranking, catalog, the keyboard state machine (`LauncherModel`), usage, IPC types, benchmarks. Tests in `Tests/KadomoMenuCoreTests/` (Swift Testing).
- `Sources/KadomoOmarchy/` the optional Omarchy theme integration (Foundation only). It may import Core; Core and the native theme code must never import or call it. The app reaches it only through `ExternalThemeProvider` (`App/ThemeProviders.swift`, `Integrations/`), inside `#if canImport(KadomoOmarchy)`. Tests in `Tests/KadomoOmarchyTests/`. See docs/OMARCHY.md.
- `Sources/KadomoMenu/` the AppKit app and CLI (same binary). `App/Launcher.swift` owns state; `UI/` draws; `Platform/` talks to macOS.
- `docs/` architecture, themes, commands, benchmarks. `examples/` sample config, commands, themes.

## Build and check

- `./build.sh [--open]` installs `~/Applications/KadomoMenu.app` and `~/.local/bin/kadomo-menu`.
- `install.sh` ships the prebuilt zip in `release/`, not the sources. After a fix that should reach installs, run `./build.sh --universal --package` and commit `release/` with `install.sh`.
- `swift test`, or `tools/dev-build.sh test` where SwiftPM cannot write its temp files.
- `tools/selftest.sh` end-to-end in-process checks; `tools/check-cli.sh` the CLI over the socket.
- `tools/snap.sh` renders every theme and state to `.build/shots/*.png`. Look at them after UI changes. `KADOMO_MENU_SNAPSHOT_OMARCHY=<folder>` adds Omarchy themes.
- `KADOMO_OMARCHY=0 tools/dev-build.sh` builds without the Omarchy module; it must still compile and pass the self-test.
- `tools/omarchy-compat.sh` checks the adapter against upstream Omarchy as it is today. `KADOMO_SELFTEST_NETWORK=1 tools/selftest.sh` adds live installs.
- Never point tests at the real `~/.config/kadomo-menu`: use `KADOMO_MENU_CONFIG_DIR`, `KADOMO_MENU_STATE_DIR`, `KADOMO_MENU_SOCKET`.

## Rules

- Nothing on the open or typing path may touch disk, network, or other processes. Measure with `KADOMO_MENU_PROFILE=1` before and after performance changes and update docs/BENCHMARKS.md.
- Presentation values come from `Theme`/`Style`, never literals in views.
- New behavior in the state machine gets a test in `ModelTests`.
- User commands run with argument arrays; only an explicit `shell` key uses a shell.
- Omarchy themes are untrusted data: only the allowlist in `SafeThemeCopy` is copied, nothing from a theme runs, and an external theme can change only what `ThemeAppearance` carries. The one exception is `vscode.json`: it names a VS Code Marketplace theme that the theme manager (`theme-vscode`) checks and has VS Code install.
