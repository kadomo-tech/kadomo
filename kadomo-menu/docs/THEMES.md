# Themes

A theme is a TOML file of design tokens. Every token is optional: a theme
names a parent with `extends` and overrides only what it changes. Built-ins
are written in the same format (`Sources/KadomoMenuCore/BuiltinThemes.swift`).

Where themes come from, later ones replacing earlier ones with the same id:

1. Built-ins: `kadomo-dark`, `kadomo-minimal`, `kadomo-terminal`, `kadomo-light`
2. `~/.config/kadomo-menu/themes/<id>.toml`
3. `kadomo`: Kadomo's `~/.config/kadomo/current/theme/kadomo-menu.toml`
   (inherits `kadomo-dark` unless it says otherwise)

Select one with `theme = "<id>"` in config.toml, `kadomo-menu theme set <id>`,
or Appearance › Kadomo Themes. Saving a theme file applies it immediately. A theme
with an error is rejected as a whole; the last valid theme stays on screen
and the error shows at the bottom of the launcher and in
`kadomo-menu config check`. Themes contain no code.

## Top level

| Key | Values | Default (Kadomo Dark) |
| --- | --- | --- |
| `name` | display name | `"Kadomo Dark"` |
| `extends` | theme id | none (built-in defaults) |
| `appearance` | `dark`, `light`, `auto` | `dark` |
| `layout` | `center`, `top`, `compact` | `center` |

`auto` follows macOS light/dark and uses `[colors.light]` in light mode.
`top` pins the panel near the menu bar; `compact` caps the width at 460 pt.

## `[colors]` and `[colors.light]`

Colors are `#rgb`, `#rrggbb`, or `#rrggbbaa`.

| Key | Used for |
| --- | --- |
| `background` | panel fill (multiplied by `effects.background_opacity`) |
| `foreground` | titles, search text |
| `muted` | subtitles, empty-state text |
| `accent` | favorite and current marks, bar selection |
| `selection_background`, `selection_foreground` | the selected row |
| `border` | a color, or an array of two or more for a diagonal gradient |
| `separator` | line under the search field |
| `shadow` | reserved for custom shadows |
| `placeholder` | the "Go…" text |
| `caret` | text cursor |
| `breadcrumb` | the category path left of the search |
| `hint` | shortcut hints and chevrons |
| `error`, `warning` | footer messages, toasts, confirmations |

## `[font]`

| Key | Values | Default |
| --- | --- | --- |
| `family` | `monospace` (SF Mono), `system`, `rounded`, or any installed family (`"JetBrainsMono Nerd Font"`) | `JetBrainsMono Nerd Font` |
| `size` | 8–40 | 15 |
| `weight`, `selected_weight` | `ultralight` … `black` | `regular` |
| `search_family` | like `family` | `family` |
| `search_size`, `search_weight` | | 16, `regular` |
| `subtitle_size`, `hint_size` | | 11, 12 |

A missing family falls back to the monospaced system font.

## `[geometry]` (points)

| Key | Range | Default |
| --- | --- | --- |
| `width` | 240–1600 | 295 |
| `max_rows` | 1–30 | 10 |
| `keybind_rows` | 1–60 | 22 (rows and headings in the Keybinds list, which uses shorter rows; the screen height caps it) |
| `row_height`, `row_spacing` | | 48, 4 |
| `padding`, `gap`, `row_inset` | | 18, 10, 20 |
| `search_height` | | 44 |
| `corner_radius`, `row_corner_radius` | | 16, 8 |
| `border_width` | 0–8 | 2 |
| `icon_size` | 0–64 (0 hides icons) | 18 |
| `top_offset` | 0–0.8, fraction of the screen above the panel | 0.22 |

## `[effects]`

| Key | Values | Default |
| --- | --- | --- |
| `background_opacity` | 0–1 | 0.97 |
| `material` | `none`, `hud`, `popover`, `menu`, `sidebar`, `under-window` (macOS blur behind the panel) | `none` |
| `shadow_radius` | 0 turns the window shadow off | 30 |
| `animation_duration` | seconds for height changes; 0 off. Reduce Motion always turns it off | 0.08 |
| `selection_style` | `fill`, `bar`, `outline` | `fill` |
| `show_icons`, `show_subtitles`, `show_hints`, `show_chevrons`, `show_breadcrumb`, `show_separator`, `show_footer` | booleans | icons, hints, chevrons, breadcrumb on |
| `icon_style` | `auto` (app icons for apps, symbols elsewhere), `symbols` (monochrome only), `none` | `auto` |
| `placeholder` | search placeholder | `"Go…"` |

## Example

```toml
name = "Rosé"
extends = "kadomo-dark"

[colors]
background = "#191724"
foreground = "#e0def4"
muted = "#908caa"
accent = "#ebbcba"
selection_background = "#26233a"
selection_foreground = "#ebbcba"
border = ["#c4a7e7", "#ebbcba"]
breadcrumb = "#c4a7e7"
caret = "#ebbcba"

[font]
family = "JetBrainsMono Nerd Font"

[effects]
selection_style = "bar"
```

More in [examples/themes](../examples/themes).

## Omarchy themes

Omarchy themes are a separate, optional theme system with their own menu
(Appearance › Omarchy Themes), storage, and installer; they are never stored
as files here and never needed by anything on this page. See
[OMARCHY.md](OMARCHY.md). While one is active, `kadomo-menu theme current`
prints `omarchy:<id>`, and setting any theme above makes Kadomo's theme active
again.

## Kadomo

A Kadomo theme ships `kadomo-menu.toml` next to its other per-app files.
When Kadomo switches the current theme (re-pointing `~/.config/kadomo/current`),
the launcher sees the file change and restyles. Set `theme = "kadomo"`.
