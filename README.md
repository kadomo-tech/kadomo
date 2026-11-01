# kadomo-alpha
Early version of Kadomo

Version: see [`VERSION`](VERSION) (currently 0.1.1), or run `./install.sh --version`.
Kadomo follows [Semantic Versioning](https://semver.org); while it is 0.x,
any release can change how things behave or install. Each release is tagged
`vX.Y.Z`.

## Install

```sh
./install.sh                          # pick categories (or every item), review, install
./install.sh --yes                    # Kadomo Core, no questions
./install.sh --only core,developer    # these categories, no questions
```

The installer asks what to set up by category. Kadomo Core is on; the others
start off. The window manager is OmniWM; it starts at login once you turn that
on in its own settings, and nothing of Kadomo's runs in the background for it.
Updating from an older Kadomo removes the AeroSpace it installed (Kadomo's
build, its commands and login agents, its config, and JankyBorders):

| Category | What it sets up |
| --- | --- |
| Kadomo Core | Homebrew (when it is not on the Mac yet), Kadomo Menu and its font, the [OmniWM](https://github.com/BarutSRB/OmniWM) window manager (its focus border follows the theme), Ghostty and kitty with their configs, btop, htop, the Starship prompt, and the theme manager with its themes (btop, the wallpaper, and light/dark mode follow the theme; Terminal.app is left alone) |
| Developer | Neovim and Kadomo's Vim and Neovim settings, Node.js, Java 25 (Temurin JDK), Rancher Desktop, and Visual Studio Code in the theme's colors (an Omarchy theme's own VS Code theme when it names one) |
| Gaming | Moonlight, and Moonlight Mouse Optimization (LinearMouse) |
| Other | Firefox |

OmniWM needs macOS 26 or later on Apple silicon; on another Mac, Kadomo installs no window manager.

Something already on the Mac is left as it is. **Advanced** lists every item
under its category, so you can turn each one on or off. Nothing is installed
until you confirm the review. Each part then installs as one step, with its
output in a log, and anything that still needs you (an Accessibility
permission, say) is listed at the end. Java 25 asks for your password, so the
developer tools install in the open when it is selected.

Most apps come from [Homebrew](https://brew.sh). When it is not on the Mac,
Kadomo Core installs it first, with Homebrew's own installer: it asks for your
password once, needs an administrator account, and adds the Xcode Command Line
Tools if they are missing (that can take a few minutes). On Apple silicon a
marked block in `~/.zprofile` puts `brew` on your PATH. Run from zsh, the
installer ends by starting a new zsh in the same window, so `brew` and the
Starship prompt work right away (windows already open get them in a new
one). A Homebrew that is already there is used as it is.

| Component | What it installs |
| --- | --- |
| `homebrew/` | Homebrew, with its own installer, when it is not on the Mac yet, and the PATH block in `~/.zprofile` (Apple silicon) |
| `kadomo-menu/` | the launcher app, the `kadomo-menu` command, and its font. Besides Kadomo's own themes it can install Omarchy themes, which style the launcher and, through the theme manager, every app and the wallpaper (Appearance › Omarchy Themes; see [kadomo-menu/docs/OMARCHY.md](kadomo-menu/docs/OMARCHY.md)) |
| `omniwm/` | OmniWM from Homebrew (unless it is already on the Mac), `kadomo-omniwm`, a command that puts the theme's colors on its focus border and writes Kadomo Menu › Services › OmniWM and its keys under Keybinds, and `remove-aerospace.sh`, which removes what an older Kadomo installed for AeroSpace. See [omniwm/README.md](omniwm/README.md) |
| `dotfiles/` | configs copied to where each tool reads them (files they replace are backed up) |
| `apps/` | Ghostty, kitty, btop, htop, Neovim, Moonlight, and Firefox from Homebrew; an app already on the Mac is skipped |
| `moonlight-mouse/` | LinearMouse from Homebrew (unless it is already on the Mac) and one LinearMouse profile that applies only to a mouse in Moonlight: no pointer or scroll acceleration, no smoothing, 3 lines per wheel step, Windows-style direction. Your other LinearMouse settings are kept. See [moonlight-mouse/README.md](moonlight-mouse/README.md) |
| `kadomo-theme-manager/` | `theme-set` and its themes (tmac2k, Catppuccin, Catppuccin Latte, Gruvbox, Rosé Pine, Sora): one command switches Ghostty, kitty, OmniWM's border, Kadomo Menu, btop, Neovim, Vim, VS Code, the Starship prompt, the wallpaper, and light/dark mode, live |
| `developer/` | Node.js, Java 25 (Temurin JDK), Rancher Desktop, and VS Code (in the theme's colors) from Homebrew, and the Starship prompt for zsh in the theme's colors (one marked block in `.zshrc`; a prompt setup of your own is left alone). A tool already on the Mac is used as it is. See [developer/README.md](developer/README.md) |

Each component also has its own `install.sh` and `uninstall.sh`; the installers
with more than one item take `--only` to install just some of them.

## Uninstall

```sh
./uninstall.sh        # lists what Kadomo set up, review, remove
./uninstall.sh --yes  # removes everything found, no questions
```

The uninstaller finds what Kadomo put on this Mac and lists it, all checked;
`d` shows exactly what each part removes or puts back. Before anything is
removed, the apps and services about to go are stopped: their login agents
are unloaded and the apps quit (an app that does not quit in time is stopped),
so nothing is removed while it runs. When something you chose is in a system
folder (Java 25, Rancher Desktop's helper files, Homebrew and the Command Line
Tools it added), it asks for your Mac password once, right after you confirm,
and lists why. Run it from the Terminal app that comes
with macOS: started in a terminal Kadomo installed (Ghostty or kitty), it
stops before changing anything and says why. It would have to quit that
terminal, which ends the uninstall halfway, and a running app cannot be
removed. When it turns off Kadomo's Starship prompt (or removes Homebrew's
PATH block), the zsh you ran it from still has Starship loaded, so at the
end it starts a new zsh in that window that reads your startup files as they
are now, with the prompt from before Kadomo. Neovim is left open, so no unsaved work is lost. This removes everything `install.sh` put in place and restores the configs the
dotfiles replaced. What an older Kadomo installed for AeroSpace goes; a regular AeroSpace you installed stays. OmniWM goes only if Kadomo installed it (its settings stay), and its border gets back the colors it had before Kadomo. btop, Kadomo Menu, the wallpaper, and light/dark mode go back to what they were. A
config you edited after installing is kept as `<name>.bak.<timestamp>`. The
kadomo-menu uninstaller also deletes its config, usage history, and
preferences. The apps uninstaller removes only the apps Kadomo installed
(recorded in `~/Library/Application Support/kadomo/apps-installed.txt`), asks
running ones to quit first, and leaves their own data, such as Firefox
profiles, in place. The moonlight-mouse uninstaller takes out only Kadomo's
Moonlight profile (your other LinearMouse profiles stay) and the launch agent
that opens LinearMouse at login, and uninstalls LinearMouse only when Kadomo installed it and
nothing else is set up in it. The developer uninstaller turns Kadomo's Starship
prompt off (your `.zshrc` goes back to how it was), puts back VS Code's color
theme from before, and removes only the developer tools Kadomo installed. Homebrew goes last, and only when Kadomo
installed it and nothing of yours is in it: Homebrew's own uninstaller removes
it, along with its PATH block and the Xcode Command Line Tools if its installer
added them. A Homebrew you have installed your own packages with stays. This
checkout is left alone.
