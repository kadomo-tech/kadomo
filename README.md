<div align="center">

# Kadomo

**A themed, keyboard-first desktop for macOS, set up with one command.**

A launcher, a tiling window manager, good terminals, and one theme that
restyles all of it at once. Removing it is just as easy.

![version](https://img.shields.io/badge/version-0.1.2-7aa2f7)
![macOS](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![status](https://img.shields.io/badge/status-alpha-e0af68)

</div>

---

## Quick start

Open **Terminal** (the one that comes with macOS) and paste:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kadomo-tech/kadomo/main/install.sh)"
```

You don't need to clone anything or install git. Choose what you want, check
the summary, and confirm. Nothing is installed until you confirm.

When it finishes, press **⌥ Space** (Option-Space) to open Kadomo Menu.

## Uninstall

In **Terminal**, run either of these:

```sh
~/.local/share/kadomo/source/uninstall.sh
```

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kadomo-tech/kadomo/main/uninstall.sh)"
```

You'll see a list of everything Kadomo set up, all checked. Uncheck anything
you want to keep, then confirm. Everything you leave checked is removed, and
the configs Kadomo replaced come back. Once nothing of Kadomo is left, its
downloaded copy is deleted too.

> [!IMPORTANT]
> Uninstall from macOS's own **Terminal** app, not Ghostty. The
> uninstaller has to quit that app, which would stop it partway through.

---

## What you get

Pick any mix of these when you install. **Kadomo Core** is on by default.

| Category | Includes |
| --- | --- |
| 🧩 **Kadomo Core** | Kadomo Menu (launcher), [OmniWM](https://github.com/BarutSRB/OmniWM) tiling window manager with its own menu bar, the Ghostty terminal, btop, htop, the Starship prompt, the theme manager and its themes, and Homebrew if you don't have it |
| 🛠 **Developer** | Neovim set up as an IDE for Java, JavaScript/TypeScript, Node, and AWS ([LazyVim](https://www.lazyvim.org)), Node.js, Java 25 (Temurin), Rancher Desktop, and VS Code in your theme's colors |
| 🤖 **AI** | GitHub Copilot in Neovim, and [Claude Code](https://code.claude.com) with its Neovim integration ([details](neovim/README.md#the-ai-tools)) |
| 🎮 **Gaming** | Moonlight, plus a mouse profile with no acceleration that applies only inside Moonlight (LinearMouse) |
| 🌐 **Other** | Firefox |

**Advanced** in the installer lists every item separately, so you can turn
each one on or off.

### One theme for everything

```sh
theme-set catppuccin
```

Switches Ghostty, OmniWM's focus border, Kadomo Menu, btop, Neovim (LazyVim too),
Vim, VS Code, the Starship prompt, the wallpaper, and light/dark mode, all
live. Included themes: `tmac2k`, `catppuccin`, `catppuccin-latte`, `gruvbox`,
`rose-pine`, `sora`. Kadomo Menu can also install
[Omarchy themes](kadomo-menu/docs/OMARCHY.md)
(Appearance › Omarchy Themes).

---

## Requirements

- **macOS**. OmniWM needs **macOS 26 or later on Apple silicon**, and version
  **0.8 or later** for its own menu bar; Kadomo upgrades a copy it installed.
  On any other Mac, Kadomo installs everything except the window manager.
- **An administrator account**, if Homebrew isn't installed yet. Homebrew's
  installer asks for your password once, and may add the Xcode Command Line
  Tools, which can take a few minutes.

## Install options

Options go after a `_`. Put `KADOMO_REF` in front to choose a version:

```sh
# Install categories without any questions
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kadomo-tech/kadomo/main/install.sh)" _ --only core,developer

# Kadomo Core only, no questions
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kadomo-tech/kadomo/main/install.sh)" _ --yes

# A specific release (installs come from releases only, never a branch)
KADOMO_REF=0.1.2 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kadomo-tech/kadomo/main/install.sh)"
```

| Option | What it does |
| --- | --- |
| *(none)* | Menus: pick categories or single items, review, install |
| `--yes` | Installs Kadomo Core without asking anything |
| `--only LIST` | Installs these categories without asking: `core`, `developer`, `ai`, `gaming`, `other` |
| `--version` | Prints the Kadomo version |

To update, run the install command again. It downloads the new version and
installs anything new.

<details>
<summary><b>Working from a clone</b> (for contributors)</summary>

```sh
git clone https://github.com/kadomo-tech/kadomo.git
cd kadomo

./install.sh                          # menus
./install.sh --yes                    # Kadomo Core, no questions
./install.sh --only core,developer    # these categories, no questions

./uninstall.sh                        # review and remove
./uninstall.sh --yes                  # remove everything found
```

Uninstalling leaves the clone itself in place.

</details>

---

## How it behaves

<details>
<summary><b>Installing</b></summary>

- **Your existing setup is respected.** An app that's already on your Mac is
  left as it is. A config Kadomo replaces is backed up next to itself first.
- **Each part installs as one step**, and its output goes to a log. Anything
  that still needs you at the end, such as an Accessibility permission, is
  listed for you.
- **Java 25 asks for your password**, so when it's selected the developer
  tools install in the foreground.
- **Homebrew on Apple silicon.** A marked block in `~/.zprofile` puts `brew`
  on your PATH. When you run the installer from zsh, it ends by starting a new
  zsh, so `brew` and the prompt work right away.
- **OmniWM starts itself** once you turn on "start at login" in its own
  settings. Kadomo runs nothing in the background for it.
- **Upgrading from an older Kadomo** removes the AeroSpace setup it installed
  (Kadomo's build, its commands and login agents, its config, and
  JankyBorders). An AeroSpace you installed yourself stays.
- **SketchyBar is gone.** OmniWM 0.8 draws its own menu bar, so Kadomo no
  longer installs SketchyBar. What an older Kadomo installed for it is
  removed (its config, menu entries, and packages, if Kadomo installed
  them), and the macOS menu bar and OmniWM's settings go back to how they
  were.

</details>

<details>
<summary><b>Uninstalling</b></summary>

- **It removes only what Kadomo added.** Anything that was on your Mac before
  stays, and so does each app's own data (Firefox profiles, for example).
- **Configs are restored.** A config you edited after installing is kept as
  `<name>.bak.<timestamp>`.
- **Apps are quit first.** Their login agents are stopped and the apps are
  quit before anything is deleted. Neovim is left open so you don't lose
  unsaved work.
- **Your password is asked for once**, and only when something is in a
  system folder (Java 25, Rancher Desktop's helper files, Homebrew, the
  Command Line Tools).
- **Everything goes back to how it was.** btop, Kadomo Menu, VS Code's colors,
  the wallpaper, light/dark mode, and OmniWM's border colors all return to
  their settings from before Kadomo. Your `.zshrc` loses Kadomo's Starship
  block, and a new zsh starts with your old prompt.
- **OmniWM and LinearMouse** are removed only if Kadomo installed them. OmniWM
  keeps its settings, and your other LinearMouse profiles stay.
- **Homebrew goes last**, and only if Kadomo installed it and you haven't
  installed anything else with it. Press `d` on any item in the list to see
  exactly what it removes.

</details>

<details>
<summary><b>Project layout</b></summary>

Each folder has its own `install.sh` and `uninstall.sh`. The top-level
scripts run them in order.

| Folder | What it does |
| --- | --- |
| [`homebrew/`](homebrew) | Installs Homebrew if it's missing, and adds the PATH block to `~/.zprofile` |
| [`kadomo-menu/`](kadomo-menu) | The launcher app, the `kadomo-menu` command, and its font |
| [`omniwm/`](omniwm/README.md) | OmniWM, plus `kadomo-omniwm` for themed borders and the menu's keybinds, and what it removes from an older Kadomo (AeroSpace, SketchyBar) |
| [`dotfiles/`](dotfiles) | Configs, copied to where each tool reads them |
| [`apps/`](apps) | Ghostty, btop, htop, Neovim, Moonlight, and Firefox |
| [`neovim/`](neovim/README.md) | Kadomo's LazyVim config and what it needs, GitHub Copilot, and Claude Code |
| [`moonlight-mouse/`](moonlight-mouse/README.md) | The LinearMouse profile for Moonlight |
| [`kadomo-theme-manager/`](kadomo-theme-manager) | `theme-set` and the themes |
| [`developer/`](developer/README.md) | Node.js, Java 25, Rancher Desktop, VS Code, and the Starship prompt |

The curl installer keeps its copy of Kadomo in `~/.local/share/kadomo/source`.

</details>

---

## Versioning

Kadomo follows [Semantic Versioning](https://semver.org). The current
version is in [`VERSION`](VERSION) (0.1.2), and releases are tagged `vX.Y.Z`.
While Kadomo is at **0.x**, any release can change how things behave or
install.
