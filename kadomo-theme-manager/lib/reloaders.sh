# One reloader per app, run in parallel after every theme change. Each reads
# the current theme (not the one that started it), does nothing when its app
# is not installed or not running, and says nothing unless something failed.
# Sourced by apply.sh.

source "$LIB/starship.sh"
source "$LIB/vscode.sh"

# Running Ghostty apps, one "<pid> <executable>" line each. Found with ps by the
# app's executable path, because pgrep does not match Ghostty's process name.
ghostty_processes() {
    ps -axo pid=,comm= 2>/dev/null | sed -n 's|^ *\([0-9][0-9]*\) \(.*\.app/Contents/MacOS/ghostty\)$|\1 \2|p'
}

# Whether the Ghostty at this executable reloads its config on SIGUSR2 (1.2 and
# later). An older one would quit on that signal instead.
ghostty_reloads_on_signal() {
    local version major minor
    version="$(defaults read "${1%/MacOS/*}/Info.plist" CFBundleShortVersionString 2>/dev/null)" || return 1
    major="${version%%.*}"; minor="${version#*.}"; minor="${minor%%[!0-9]*}"
    [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
    ((major > 1 || (major == 1 && minor >= 2)))
}

# Ghostty reads current/theme/ghostty.conf through config-file in its config.
reload_ghostty() {
    local pid exe
    while read -r pid exe; do
        if ghostty_reloads_on_signal "$exe"; then
            kill -USR2 "$pid" 2>/dev/null || warn "theme: could not signal Ghostty; press Cmd+Shift+, in it"
        else
            warn "theme: this Ghostty is older than 1.2; press Cmd+Shift+, in it to reload"
        fi
    done < <(ghostty_processes)
}

# kitty includes current/theme/kitty.conf and reloads its config on SIGUSR1.
reload_kitty() {
    pgrep -xq kitty 2>/dev/null || return 0
    pkill -USR1 -x kitty 2>/dev/null || warn "theme: could not signal kitty; press Ctrl+Cmd+, in it"
}

# btop shows ~/.config/btop/themes/current.theme, a link to current/theme/btop.theme.
# btop 1.3 and later reload their config, theme included, on SIGUSR2; an
# older one would quit on that signal.
reload_btop() {
    local version major minor
    pgrep -xq btop 2>/dev/null || return 0
    version="$(btop --version 2>/dev/null | tr -d '\033' | sed -n 's/\[[0-9;]*m//g; s/^btop version: *\([0-9][0-9.]*\).*/\1/p' | head -n 1)"
    major="${version%%.*}"; minor="${version#*.}"; minor="${minor%%.*}"
    if [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] && ((major > 1 || (major == 1 && minor >= 3))); then
        pkill -USR2 -x btop 2>/dev/null || true
    else
        warn "theme: quit btop and open it again for the new colors"
    fi
}

# OmniWM keeps its border colors in ~/.config/omniwm/settings.toml and reloads
# that file when it changes: kadomo-omniwm puts current/theme/omniwm.toml's
# colors there, whether OmniWM runs or not.
reload_omniwm() {
    local bin="$HOME/.local/bin/kadomo-omniwm"
    [[ -x "$bin" ]] || return 0
    "$bin" theme || warn "theme: could not update OmniWM's border colors"
}

# Kadomo Menu watches current/theme/kadomo-menu.toml and restyles itself
# while its theme is "kadomo"; a launcher set to another theme, or showing an
# Omarchy theme (omarchy:<id>), is put back on "kadomo": picking a Kadomo theme
# styles the launcher too. An external theme (theme-set --external, which
# Kadomo Menu runs for Omarchy themes) leaves the launcher on the theme that
# asked for it. Nothing happens when it is not running.
reload_kadomo_menu() {
    local bin="$HOME/.local/bin/kadomo-menu" id
    [[ -x "$bin" ]] || return 0
    id="$("$bin" theme current 2>/dev/null)" || return 0
    ! current_is_external || return 0
    [[ "$id" == kadomo ]] || "$bin" theme set kadomo >/dev/null 2>&1 || true
}

# The sockets of running Neovims: each listens in stdpath("run"), under the
# user's temporary folder, at nvim.<user>/<random>/nvim.<pid>.0.
nvim_sockets() {
    local dir seen=" "
    for dir in "${TMPDIR:-}" "$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)" "${XDG_RUNTIME_DIR:-}"; do
        dir="${dir%/}"
        [[ -n "$dir" && -d "$dir/nvim.$USER" && "$seen" != *" $dir "* ]] || continue
        seen+="$dir "
        find "$dir/nvim.$USER" -maxdepth 2 -type s -name 'nvim.*' 2>/dev/null
    done
}

# Neovim shows the "kadomo" colorscheme: ~/.config/nvim/colors/kadomo.lua
# links to the theme's neovim-colors.lua. Every running Neovim that shows it
# loads it again; one showing another colorscheme is left alone.
# LazyVim loads every spec in lua/plugins, so the theme's neovim.lua (which
# picks "kadomo", or a colorscheme plugin the theme names) goes in as
# lua/plugins/theme.lua, a link into the current theme; a theme.lua of your
# own is never touched. LazyVim picks that up the next time Neovim starts.
reload_neovim() {
    local plugins="$HOME/.config/nvim/lua/plugins" link socket nvim
    if [[ -d "$plugins" ]]; then
        link="$plugins/theme.lua"
        if [[ -L "$link" && "$(readlink "$link")" == "$THEME_DIR/neovim.lua" ]] || [[ ! -e "$link" && ! -L "$link" ]]; then
            if [[ -f "$THEME_DIR/neovim.lua" ]]; then
                [[ -L "$link" ]] || ln -s "$THEME_DIR/neovim.lua" "$link"
            else
                rm -f -- "$link"
            fi
        fi
    fi
    nvim="$(command -v nvim 2>/dev/null)" || return 0
    while IFS= read -r socket; do
        [[ -n "$socket" ]] || continue
        with_timeout 3 "$nvim" --server "$socket" --remote-expr \
            'execute(get(g:, "colors_name", "") ==# "kadomo" ? "colorscheme kadomo" : "")' >/dev/null 2>&1 || true
    done < <(nvim_sockets)
}

# Vim shows the "kadomo" colorscheme: ~/.vim/colors/kadomo.vim links to the
# theme's vim-colors.vim. The Vim that comes with macOS cannot be reached
# while it runs, so it shows the new theme the next time it starts.
reload_vim() { :; }

# VS Code shows the "Kadomo" color theme, a local extension rendered from
# the theme (or the Marketplace theme its vscode.json names, fetched in the
# background), through workbench.colorTheme. It watches the theme file, so
# an open window changes at once. See lib/vscode.sh.
reload_vscode() { vscode_apply background; }

# Starship (zsh): Kadomo's starship.toml is written again from the theme's
# starship-palette.toml (or, with matching off, the theme you picked), and
# Starship reads it at the next prompt. Nothing happens until theme-starship
# enable has turned it on.
reload_starship() {
    starship_on || return 0
    starship_apply || warn "theme: the Starship prompt kept its old colors; retry with theme-starship apply"
}

# Whether macOS is in dark mode now.
macos_dark() { [[ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" == Dark ]]; }

# Sets macOS to dark ($1 = true) or light (false). System Events asks once for permission.
macos_set_dark() {
    osascript -e 'on run {d}' -e 'tell application "System Events" to tell appearance preferences to set dark mode to (d is "true")' -e 'end run' "$1" >/dev/null
}

# The theme's mode (dark or light) sets the macOS appearance, and with it
# every app that follows the system.
reload_appearance() {
    local mode
    mode="$(awk -F'\t' '$1 == "mode" { print $2; exit }' "$THEME_DIR/palette.tsv" 2>/dev/null)"
    case "$mode" in
        dark) macos_dark || macos_set_dark true ;;
        light) ! macos_dark || macos_set_dark false ;;
        *) return 0 ;;
    esac || warn "theme: could not switch macOS to $mode mode (allow System Events under Privacy & Security > Automation)"
}
