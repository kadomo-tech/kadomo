# developer

Developer tools from Homebrew, and the Starship prompt in the Kadomo theme's
colors. Off by default in the top-level checklist; pick the ones you want.

| Item | What it installs |
| --- | --- |
| `node` | Node.js with npm: `brew install node` (the current release line) |
| `java` | Java 25 LTS, the Eclipse Temurin JDK: `brew install --cask temurin@25`. It is a macOS package, so macOS asks for your password; the JDK goes in `/Library/Java/JavaVirtualMachines`, where `java`, `/usr/libexec/java_home`, and IDEs find it with no PATH changes |
| `rancher` | Rancher Desktop: `brew install --cask rancher`. Containers (`docker`, `nerdctl`) and Kubernetes (`kubectl`) in a small VM |
| `vscode` | Visual Studio Code: `brew install --cask visual-studio-code`, then `theme-vscode enable` (below): its colors follow the theme. Homebrew puts the `code` command on your PATH |
| `starship` | Starship: `brew install starship`, then `theme-starship enable` (below) |

```sh
./install.sh                          # all five
./install.sh --only node,java         # some of them
./install.sh --dry-run
./uninstall.sh                        # removes what install.sh installed
```

A tool already on the Mac, however it got there, is used as it is and never
uninstalled. What Kadomo installed is recorded in
`~/Library/Application Support/kadomo/developer-installed.txt`, and
`uninstall.sh` removes exactly that: VS Code's color theme goes back to what
it was and Kadomo's prompt is turned off first, then the Homebrew packages go
(Rancher Desktop and VS Code are asked to quit first). Each tool's own data
stays, as with a plain `brew uninstall`: npm's global packages, Rancher
Desktop's VM and images, your own VS Code settings and extensions.

A failed download (offline, say) is reported, nothing half-done is recorded as
working, and running the installer again picks up where it stopped.

## Rancher Desktop

Open it once after installing: it asks for the container engine (containerd
or dockerd/moby) and whether to run Kubernetes, and puts `docker`, `nerdctl`,
and `kubectl` in `~/.rd/bin`. It can add that folder to your PATH itself, which it does by editing your
shell profile; that is Rancher Desktop's doing, not Kadomo's.
With Docker Desktop installed as well, run one at a time: both provide the
`docker` command and socket.

## VS Code

VS Code takes its colors from the theme manager, so install that too (it is in
the top-level checklist). The installer then runs `theme-vscode enable`, and
from then on every theme switch reaches VS Code, Omarchy themes included:

Every theme, Kadomo's and Omarchy's, shows as the **Kadomo** color theme,
drawn from the theme's palette (a local extension in
`~/.vscode/extensions/kadomo.kadomo-theme`). An open window changes at once.
Nothing is installed from the VS Code Marketplace: an extension is code, so the
`vscode.json` Omarchy themes ship is ignored.

Only `workbench.colorTheme` in your `settings.json` changes; comments and
everything else stay as you wrote them, and a `settings.json` that is a symlink
stays one. `theme-vscode disable` (and the uninstaller) puts back the color
theme you had, unless you picked another since, and removes the Kadomo extension
and any Marketplace theme an older Kadomo installed. See
[the theme manager's README](../kadomo-theme-manager/README.md#vs-code).

## Starship

Starship takes its colors from the theme manager, so install that too (it is
in the top-level checklist). The installer then runs `theme-starship enable`:

1. Uses the Starship that is there (Homebrew on Apple silicon or Intel,
   `HOMEBREW_PREFIX`, PATH, `~/.local/bin`, cargo), else installs it with
   Homebrew. Without Homebrew, Kadomo does not install Homebrew for you: install
   it from https://brew.sh, or run `./install.sh --starship-script` to use
   Starship's official installer (into `~/.local/bin`, no sudo).
2. Checks your zsh setup (in `$ZDOTDIR` when you set one, also in `~/.zshenv`).
   If you already start Starship, set `STARSHIP_CONFIG`, use another prompt
   (Powerlevel10k, Oh My Zsh themes, Pure, Spaceship, Oh My Posh), or have your
   own `~/.config/starship.toml`, it explains what it found and asks before
   changing anything. With `--yes` it leaves your setup alone and tells you
   how to switch later; `--use-kadomo-prompt` switches without asking.
3. Writes Kadomo's own Starship config and adds one marked block to `.zshrc`
   (backed up first), then shows the prompt in the current theme's colors.

Open a new terminal tab (or run `exec zsh`) to see it. After that, each theme
change shows at the next prompt. Everything else, from previews to choosing a
prompt theme apart from the Kadomo theme, is `theme-starship`: see
[the theme manager's README](../kadomo-theme-manager/README.md#starship).

The prompt uses Nerd Font symbols (branch, Node.js, Java...) when a Nerd Font
is installed. Kadomo's font item installs JetBrainsMono Nerd Font, and Ghostty
has the symbols built in. Otherwise it uses plain text. Kadomo never changes
your terminal's font for this; `theme-starship icons plain` or `nerd` switches.

## Tests

```sh
tests/test.sh
```

Runs in a throwaway HOME with a stand-in `brew`, so nothing is installed and
no real shell config is touched.
