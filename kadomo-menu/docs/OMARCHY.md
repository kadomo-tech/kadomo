# Omarchy themes

Kadomo Menu has two theme systems, side by side:

- **Kadomo Themes** (Appearance › Kadomo Themes): Kadomo's own. The launcher's
  TOML themes ([THEMES.md](THEMES.md)) and, with the theme manager installed,
  the desktop themes that style every app. Always there, offline, and never
  dependent on anything below.
- **Omarchy Themes** (Appearance › Omarchy Themes): an optional integration that
  installs themes from the [Omarchy](https://github.com/omacom/omarchy)
  ecosystem. Applying one styles the launcher and, with the theme manager
  installed, every app the theme manager styles and the wallpaper, just as a
  Kadomo theme does.

They are separate libraries with separate storage, parsers, installers, and
menus. Only one theme styles the launcher at a time, and the launcher always
knows which provider it came from (`kadomo-menu theme provider`).

## Using it

| Where | What |
| --- | --- |
| Omarchy Themes › Installed | your Omarchy themes; ↩ applies, ⇥ for Update, Show in Finder, Remove |
| Omarchy Themes › Official Themes | the themes in Omarchy's repository (Load Official Themes the first time), plus official themes Omarchy has since dropped, from the release the community catalog names (Osaka Jade from v4.0.6, say) |
| Omarchy Themes › Community Themes | the omarchytheme.com catalog; type to search by name, author, or description |
| Omarchy Themes › Install from Git | type or paste an `https://` URL, then ↩ |
| Omarchy Themes › Import Local Theme… | pick a folder with a `colors.toml` |
| Omarchy Themes › Check for Updates | fetch newer versions of everything installed |
| Use Kadomo Theme (in either list) | back to Kadomo's own theme |

Selecting a theme row previews it on the launcher right away, before
anything is installed when the catalog lists its colors. ↩ installs (if
needed) and applies: the launcher at once, then the rest of the desktop in
the background (below). Moving off the row, Escape, or closing the launcher
puts back the theme you had; previews never touch the other apps. Use Kadomo
Theme puts the launcher and the desktop back on your last Kadomo theme. So
does picking any theme under Kadomo Themes, or switching the desktop theme
with `theme-set`. Your Omarchy pick is remembered for next time, and nothing
is uninstalled.

## Every app and the wallpaper

With the Kadomo theme manager installed (`~/.local/bin/theme-set`), applying
an Omarchy theme runs

```sh
theme-set --external "<its folder in the Omarchy library>" omarchy-<name> "<Theme Name>"
```

which treats the folder as someone else's theme and uses it in place:

| What | From the Omarchy theme |
| --- | --- |
| Ghostty, kitty, Terminal, the window borders, Neovim and Vim (the `kadomo` colorscheme), the Starship prompt | rendered from its `colors.toml` by the theme manager's templates, like any Kadomo theme |
| btop | its own `btop.theme` when it ships one, else rendered |
| VS Code | the Kadomo color theme rendered from its `colors.toml`. Its `vscode.json` (a Marketplace extension to install) is ignored: Kadomo never installs an extension for a theme. See the theme manager's [VS Code](../../kadomo-theme-manager/README.md#vs-code) |
| Wallpaper | its `backgrounds/` (still images), first one first; `theme-bg-next` and Appearance › Backgrounds cycle through them. A theme with none (or only videos or Git LFS files) gets one drawn from its background and accent colors, so the wallpaper always changes |
| macOS light or dark mode | its `mode`, or a `light.mode` file |
| The launcher | the Omarchy theme's own look, from its `[launcher]` colors (below) |

Its own `ghostty.conf`, `kitty.conf`, `neovim.lua` (a LazyVim plugin spec),
`hyprland.*`, scripts, and every other file are not used: they can run
programs. Neovim and Vim get the theme's colors through the theme manager's
`kadomo` colorscheme instead. `theme-current` shows the Omarchy theme's name,
and `theme-refresh` re-applies it. The theme manager remembers your last
Kadomo theme in `current/native.name`; `theme-set --native` goes back to it.

`[omarchy] desktop = false` in config.toml keeps Omarchy themes on the
launcher only. Without the theme manager they style only the launcher.

A theme installed without its wallpapers (before they were kept, or when
GitHub refused the download, such as at its hourly limit) is marked
incomplete. Applying it fetches it again in the background and applies it
once more when the wallpapers arrive; Check for Updates does the same for all.
The wallpaper changes on every Space.

The same from a terminal:

```sh
kadomo-menu omarchy official                     # official themes (i = installed)
kadomo-menu omarchy install tokyo-night          # official theme, then apply
kadomo-menu omarchy community lumon              # search the community catalog
kadomo-menu omarchy install lumon                # a community theme by slug
kadomo-menu omarchy install https://github.com/OldJobobo/omarchy-lumon-theme
kadomo-menu omarchy import ~/themes/my-theme     # copy a local folder in
kadomo-menu omarchy check ~/themes/my-theme      # would it install? copies nothing
kadomo-menu omarchy list                         # installed (* active), with notes
kadomo-menu omarchy apply official:nord
kadomo-menu omarchy update [<id>]
kadomo-menu omarchy remove <id>
kadomo-menu theme provider                       # kadomo <theme> | omarchy <id>
```

Add `--no-apply` to an install to only install.

## The launcher's look

On the launcher an Omarchy theme changes the colors and light/dark mode only,
through Kadomo's **appearance contract** (`ThemeAppearance` in
`KadomoMenuCore`). Fonts, sizes, layout, effects, key bindings, and commands
stay as they are. Kadomo's built-in default theme supplies everything else.

| Launcher token | From the Omarchy theme |
| --- | --- |
| background | `[launcher] background` in `shell.toml`, else `background` (or `color0`) |
| foreground (titles, search text) | `[launcher] text`, else `foreground` (or `color7`), moved to 4.5:1 contrast if needed |
| muted, placeholder, hint | `dark_foreground`, else a background/foreground blend, at 3:1 |
| accent, caret, breadcrumb | `accent`, else `blue`, else `color4` |
| selection background | `[launcher] selected-background`, else `selection`, else `selection_background`, else `lighter_background` |
| selection text | the first of `[launcher] selected-text`, `selection_foreground`, accent, `bright_foreground`, foreground that reads at 4.5:1 |
| border | `[launcher] border` (a color or gradient), else `muted`, else `color8` |
| separator | `lighter_background` |
| error, warning | `red`/`color1`, `yellow`/`color3`, at 3:1 |
| light or dark | `mode`, else a `light.mode` file, else the background's brightness |

A theme from before `colors.toml` (only an `alacritty.toml`, like
Justikun/omarchy-osaka-jade-theme) gets a `colors.toml` made from its
alacritty colors, the way Omarchy does it; the `alacritty.toml` itself is not
kept. An official theme Omarchy no longer ships is installed from the release
the catalog names and stays at that release; Update does not move it.

`[menu]` is used when a `shell.toml` has no `[launcher]`. Values that refer to
something Kadomo cannot resolve (`hyprland.active-border-foreground`, template
text) are skipped and the palette fills in, with a note in `omarchy list`.
Legacy names (`bg`, `fg`, `dark_bg`, `light_fg`, ...) are read; the modern
name wins when both are set. Colors may be `#rgb`, `#rrggbb`, `#rrggbbaa`,
`rgb(rrggbb)`, `rgba(rrggbbaa)`, or `rgba(r, g, b, a)`.

## Storage

```text
~/Library/Application Support/kadomo-menu/
├── integrations/omarchy/
│   ├── themes/<name>-<hash>/    colors.toml, shell.toml, light.mode, btop.theme, preview.*, backgrounds/
│   ├── metadata/<name>-<hash>.json
│   ├── catalog-cache.json       the last official and community listings
│   └── staging/                 imports in progress
└── settings/active-theme.json   which provider and theme style the launcher
```

Kadomo's own themes stay where they always were (`~/.config/kadomo-menu`,
`~/.config/kadomo`); nothing here reads or writes them. Each theme's metadata
holds where it came from, the Git commit (`sourceRevision`), the adapter
version that validated it, when, its status, and the **last appearance that
validated**. Applying a theme reads only that file: no TOML parsing, no
network. Equal names from different sources are separate themes
(`official:nord`, `git:github.com/someone/omarchy-nord-theme:root`,
`local:nord`).

`active-theme.json`:

```json
{
  "activeTheme" : { "provider" : "omarchy", "themeId" : "official:nord" },
  "lastSelected" : { "kadomo" : "kadomo", "omarchy" : "official:nord" }
}
```

The Kadomo provider's theme is still `theme =` in config.toml; a missing or
unreadable `active-theme.json` means Kadomo's theme.

## Safety

Themes from Git, catalogs, and folders are untrusted data.

- Only an allowlist is copied: `colors.toml` (64 KB), `shell.toml` (256 KB),
  `light.mode`, `btop.theme` (64 KB, colors only), `preview.*`, and the still
  images in `backgrounds/` (PNG, JPEG, or WebP by content, 25 MB each, 40 and
  300 MB at most; videos such as `backgrounds/intros/` are skipped). Scripts,
  Lua, terminal configs, `vscode.json`, and everything else stay behind and
  never run. The theme manager applies the folder with the same rules it has
  for themes from git, so a file Kadomo kept can still only be color data.
- Symlinks are refused (a symlinked `colors.toml` or theme folder fails the
  import), names come from Kadomo, not from the theme, and nothing is read
  outside the theme folder.
- Git runs with hooks off (`core.hooksPath=/dev/null`), no submodules,
  HTTPS only (`protocol.allow=never`, `protocol.https.allow=always`), no
  symlinks in checkouts, your global and system Git config ignored, no
  credential prompts, a shallow clone, and limits: two minutes, 1 GB or 100,000
  files in the clone, and 4 MB of output. URLs with credentials, queries, or
  other transports (`ext::`, `file://`, `ssh`) are refused.
- A download has a size limit and five minutes in all, however steadily the
  server keeps sending.
- Every install is staged in `staging/`, validated, and only then swapped in
  with two renames. A failed install or update leaves the installed version,
  its files, and its appearance as they were; staging is cleaned up.
- Network and Git work runs off the main thread and never happens at startup,
  when the launcher opens, or when a theme is applied.

## When things go wrong

| Situation | What happens |
| --- | --- |
| Catalog or GitHub unreachable | The browser keeps the last cached list and shows the error on a status row; installed themes keep working offline |
| Omarchy changes its format | New or updated themes that no longer validate are refused with the reason; installed ones keep their last good appearance |
| The adapter is upgraded | Installed themes are revalidated in the background; one that fails is marked stale and keeps its last good appearance |
| The active Omarchy theme is gone or its metadata is unreadable | The launcher switches to Kadomo's theme (config.toml's, else Kadomo Dark), says so in a toast, and `kadomo-menu status` lists it |
| An install fails | The current theme stays; the error shows in the launcher |
| The theme manager cannot apply it (too old, a broken template) | The launcher keeps the Omarchy theme and says the other apps did not follow; the desktop keeps the theme it had |
| The active Omarchy theme is removed | Launcher and desktop go back to your last Kadomo theme |
| `[omarchy] enabled = false` | The Omarchy menu and commands are gone; Kadomo's theme is shown; installed Omarchy themes and your Omarchy pick are kept for when it is turned back on |
| Built without it (`KADOMO_OMARCHY=0 tools/dev-build.sh`) | The same, at build time: the app does not contain the module |

Upstream checks: `tools/omarchy-compat.sh` downloads every official theme and
the community catalog as they are today and runs them through the adapter.
Run it after an Omarchy release.

## Known limitations

- The other apps follow an Omarchy theme only through the theme manager's
  templates: an Omarchy theme's hand-made configs for Ghostty, kitty, or
  Neovim (and its LazyVim colorscheme plugin) are not used, because they can
  run programs. btop's is used.
- `shell.toml` is read for `[launcher]`/`[menu]` colors only; its sizes,
  fonts, spacing, and the other sections are ignored. Hyprland references
  inside it are not resolved.
- Wallpapers are still images only; intro videos, `icons.theme`,
  `keyboard.rgb`, `preview-unlock.png`, and Linux application configs are
  ignored.
- omarchy.org/themes is an HTML gallery without an API, so community discovery
  uses the third-party omarchytheme.com catalog. When that is down, use Install
  from Git with the theme's repository URL.
- Rows show colors as a live preview, not thumbnails; the preview image is
  stored for later use.
- GitHub limits unauthenticated API use to 60 requests an hour. Listing the
  official themes takes three; installing one from the list takes one (to list
  its wallpapers) and downloads its files at the listed commit.
- A theme in a subfolder of a Git repository works for GitHub links
  (`https://github.com/<owner>/<repo>/tree/<ref>/<path>`) only.
- Themes imported from a folder are copies; import again to update.
