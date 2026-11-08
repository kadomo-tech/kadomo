# Shared by install.sh and uninstall.sh: where the theme manager is installed,
# the record of what was changed, and the per-app wiring. Sourced after
# lib/common.sh; uses the caller's run and DRY_RUN.

SHARE="$HOME/.local/share/kadomo/theme-manager"
BIN_DIR="$HOME/.local/bin"
COMMANDS=(theme-set theme-refresh theme-list theme-current theme-bg-next theme-bg-set theme-bg-pick
          theme-pick theme-remove theme-color theme-osc theme-starship theme-vscode)
# Commands an older install linked that are gone now. install.sh removes
# their links; uninstall.sh removes them with the rest of what it recorded.
RETIRED_COMMANDS=(theme-install)

# What install.sh changed, so uninstall.sh can undo exactly that.
STATE_DIR="${KADOMO_STATE_DIR:-$HOME/Library/Application Support/kadomo}"
RECORD_DIR="$STATE_DIR/theme-manager"
# One line per change: link|<path> (a symlink we made), dir|<path> (a folder
# we made), block|<file>|<created or empty> (lines we added to your config).
RECORD="$RECORD_DIR/installed.txt"
# How things were before the first install, put back on uninstall.
MENU_BEFORE="$RECORD_DIR/kadomo-menu-theme.txt"      # the launcher's theme id
APPEARANCE_BEFORE="$RECORD_DIR/appearance.txt"       # dark or light
WALLPAPER_BEFORE="$RECORD_DIR/wallpapers.txt"        # one picture per display
WALLPAPER_STORE_BEFORE="$RECORD_DIR/wallpaper-store.plist" # macOS's wallpaper store: every Space
# btop's previous theme, "created" or "previous|<color_theme>", then, once
# Kadomo turned theme_background off, "background|<theme_background>". Same
# file the dotfiles used before the theme manager took btop over.
BTOP_MANIFEST="$STATE_DIR/btop-theme.txt"
# The record older dotfiles kept of a Terminal profile they made. Kadomo leaves
# Terminal alone now; uninstall.sh only deletes this record.
LEGACY_TERMINAL_DIR="$STATE_DIR/terminal"

record() {
    ((DRY_RUN)) && return 0
    mkdir -p "$RECORD_DIR"
    grep -qxF "$1" "$RECORD" 2>/dev/null || printf '%s\n' "$1" >>"$RECORD"
}

# Makes a folder and any missing parents, recording each one made so
# uninstall.sh can remove it again once it is empty.
make_dirs() {
    local dir="$1" made=()
    while [[ ! -d "$dir" ]]; do made+=("$dir"); dir="$(dirname "$dir")"; done
    ((${#made[@]})) || return 0
    run mkdir -p "$1"
    for dir in "${made[@]}"; do record "dir|$dir"; done
}

# --- wiring: one marked block in an app's own config ------------------------

# The block's first and last lines, after the file's comment leader (#, --, ").
BLOCK_BEGIN=">>> kadomo theme (added by kadomo-theme-manager; uninstall removes it)"
BLOCK_END="<<< kadomo theme"

# Config files and the line that makes each app read the current theme.
GHOSTTY_LINE="config-file = ?\"~/.config/kadomo/current/theme/ghostty.conf\""
NVIM_LUA_LINES='vim.o.termguicolors = true
pcall(vim.cmd.colorscheme, "kadomo")'
NVIM_VIM_LINES='set termguicolors
silent! colorscheme kadomo'
# Vim leaves out its defaults when a vimrc exists, so a vimrc made here loads them.
VIM_DEFAULTS='unlet! skip_defaults_vim
source $VIMRUNTIME/defaults.vim'
VIM_LINES='syntax on
if has('"'"'termguicolors'"'"')
  " Vim only knows the true-color codes for xterm-like terminals.
  if &term !~# '"'"'^xterm'"'"'
    let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
    let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
  endif
  set termguicolors
endif
silent! colorscheme kadomo'

ghostty_config() {
    local file
    for file in "$HOME/.config/ghostty/config.ghostty" "$HOME/.config/ghostty/config"; do
        [[ -f "$file" ]] && { printf '%s' "$file"; return; }
    done
    printf '%s' "$HOME/.config/ghostty/config.ghostty"
}
nvim_config() {
    [[ ! -f "$HOME/.config/nvim/init.vim" || -f "$HOME/.config/nvim/init.lua" ]] \
        && printf '%s' "$HOME/.config/nvim/init.lua" || printf '%s' "$HOME/.config/nvim/init.vim"
}
vim_config() {
    [[ ! -f "$HOME/.vim/vimrc" || -f "$HOME/.vimrc" ]] && printf '%s' "$HOME/.vimrc" || printf '%s' "$HOME/.vim/vimrc"
}

# Adds a block with the lines $2 to file $1, as comments with leader $4 (#
# by default), unless the file already has $3 (the Kadomo dotfiles do).
wire() {
    local file="$1" lines="$2" marker="${3:-kadomo/current/theme/}" leader="${4:-#}" label created=""
    label="$(short_path "$file")"
    if [[ -f "$file" ]] && grep -qF -- "$marker" "$file"; then
        echo "  =  $label (already reads the current theme)"
        return 0
    fi
    [[ -e "$file" ]] || created=created
    echo "  +  $label (reads the current theme)"
    make_dirs "$(dirname "$file")"
    if ! ((DRY_RUN)); then
        printf '\n%s %s\n%s\n%s %s\n' "$leader" "$BLOCK_BEGIN" "$lines" "$leader" "$BLOCK_END" >>"$file"
    fi
    record "block|$file|$created|$leader"
}

# A link from an app's own folder into the current theme, unless a file of
# yours is in the way.
link_theme() {
    local link="$1" target="$2"
    if [[ -e "$link" && ! -L "$link" ]]; then
        echo "  !  $(short_path "$link") is a file of yours; left alone" >&2
        return 1
    fi
    [[ "$(readlink "$link" 2>/dev/null)" == "$target" ]] || echo "  +  $(short_path "$link")"
    make_dirs "$(dirname "$link")"
    run ln -sfh "$target" "$link"
    record "link|$link"
}

# Neovim and Vim show the "kadomo" colorscheme, a link to the theme's colors,
# and their config selects it. LazyVim selects it through lua/plugins/theme.lua
# instead (see reload_neovim), so its init.lua is left alone.
wire_editors() {
    local file
    link_theme "$HOME/.config/nvim/colors/kadomo.lua" "$THEME_DIR/neovim-colors.lua" || true
    if [[ ! -d "$HOME/.config/nvim/lua/plugins" ]]; then
        file="$(nvim_config)"
        if [[ "$file" == *.lua ]]; then wire "$file" "$NVIM_LUA_LINES" 'colorscheme, "kadomo"' "--"
        else wire "$file" "$NVIM_VIM_LINES" "colorscheme kadomo" '"'; fi
    fi
    link_theme "$HOME/.vim/colors/kadomo.vim" "$THEME_DIR/vim-colors.vim" || true
    file="$(vim_config)"
    if [[ -e "$file" ]]; then wire "$file" "$VIM_LINES" "colorscheme kadomo" '"'
    else wire "$file" "$VIM_DEFAULTS"$'\n'"$VIM_LINES" "colorscheme kadomo" '"'; fi
}

# Takes the block out of file $1 again; deletes a file that held only it.
# $3 is the block's comment leader.
unwire() {
    local file="$1" created="$2" leader="${3:-#}" label
    label="$(short_path "$file")"
    [[ -f "$file" ]] && grep -qxF -- "$leader $BLOCK_BEGIN" "$file" || return 0
    if ((DRY_RUN)); then echo "  -  $label (theme lines)"; return 0; fi
    # The block, and the blank line wire() put before it.
    awk -v b="$leader $BLOCK_BEGIN" -v e="$leader $BLOCK_END" '
        $0 == b { skip = 1; held = 0; next }
        skip { if ($0 == e) skip = 0; next }
        { if (held) print ""; held = 0; if ($0 == "") { held = 1; next } print }
        END { if (held) print "" }' "$file" >"$file.tmp.$$"
    if [[ -n "$created" && -z "$(tr -d '[:space:]' <"$file.tmp.$$")" ]]; then
        rm -f -- "$file" "$file.tmp.$$"
        echo "  -  $label"
    else
        # Written in place, so a config that is a symlink stays one.
        cat "$file.tmp.$$" >"$file"
        rm -f -- "$file.tmp.$$"
        echo "  -  $label (theme lines)"
    fi
}

short_path() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

# --- btop -------------------------------------------------------------------
# btop rewrites btop.conf (adding all its defaults) when it quits, so only two
# lines are set: color_theme, to "current" (~/.config/btop/themes/current.theme,
# a link to the current theme's btop.theme), and theme_background, to false, so
# a theme's own btop.theme that sets main_bg still shows Ghostty's opacity.

BTOP_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/btop/btop.conf"
BTOP_LINK="${XDG_CONFIG_HOME:-$HOME/.config}/btop/themes/current.theme"

btop_get() {
    [[ -f "$BTOP_CONF" ]] || return 0
    sed -n "s/^$1 *= *//p" "$BTOP_CONF" | tail -n 1
}

btop_set() {
    if ((DRY_RUN)); then echo "    would set $1 = $2 in $BTOP_CONF"; return 0; fi
    if grep -q "^$1 *=" "$BTOP_CONF"; then
        sed -i '' "s|^$1 *=.*|$1 = $2|" "$BTOP_CONF"
    else
        printf '%s = %s\n' "$1" "$2" >>"$BTOP_CONF"
    fi
}

btop_theme() { btop_get color_theme; }
btop_set_theme() { btop_set color_theme "$1"; }

btop_install() {
    local label current
    label="$(short_path "$BTOP_CONF")"
    if [[ -L "$BTOP_LINK" || ! -e "$BTOP_LINK" ]]; then
        if [[ "$(readlink "$BTOP_LINK" 2>/dev/null)" != "$THEME_DIR/btop.theme" ]]; then
            echo "  +  $(short_path "$BTOP_LINK") (the current theme's colors)"
            make_dirs "$(dirname "$BTOP_LINK")"
            run ln -sfh "$THEME_DIR/btop.theme" "$BTOP_LINK"
        fi
        record "link|$BTOP_LINK"
    else
        echo "  !  $(short_path "$BTOP_LINK") is a file of yours; btop keeps it" >&2
        return 0
    fi
    current="$(btop_theme)"
    if [[ "$current" == '"current"' ]]; then
        echo "  =  $label (theme current already selected)"
    elif [[ ! -f "$BTOP_CONF" ]]; then
        echo "  +  $label (color_theme = current)"
        make_dirs "$(dirname "$BTOP_CONF")"
        if ! ((DRY_RUN)); then
            printf '# Kadomo: show the current theme. btop adds its other settings when it quits.\ncolor_theme = "current"\ntheme_background = false\n' >"$BTOP_CONF"
        fi
        # A record from an earlier install is kept: it knows what was there first.
        [[ -s "$BTOP_MANIFEST" ]] || ((DRY_RUN)) || { mkdir -p "$STATE_DIR"; echo created >"$BTOP_MANIFEST"; }
    else
        echo "  ~  $label (color_theme ${current:-unset} → current)"
        btop_set_theme '"current"'
        [[ -s "$BTOP_MANIFEST" ]] || ((DRY_RUN)) || { mkdir -p "$STATE_DIR"; printf 'previous|%s\n' "$current" >"$BTOP_MANIFEST"; }
    fi
    current="$(btop_get theme_background)"
    if [[ "$current" != false ]]; then
        echo "  ~  $label (theme_background ${current:-unset} → false, for the terminal's opacity)"
        btop_set theme_background false
        grep -qs '^background|' "$BTOP_MANIFEST" || ((DRY_RUN)) || { mkdir -p "$STATE_DIR"; printf 'background|%s\n' "$current" >>"$BTOP_MANIFEST"; }
    fi
}

# Puts btop's old theme and theme_background back. Also undoes the dotfiles'
# older tmac2k selection.
btop_uninstall() {
    [[ -s "$BTOP_MANIFEST" ]] || return 0
    local label record background previous now
    label="$(short_path "$BTOP_CONF")"
    record="$(grep -v '^background|' "$BTOP_MANIFEST" | head -n 1)"
    background=""
    # Unset before, or a btop.conf Kadomo wrote: btop's own default is on.
    if grep -q '^background|' "$BTOP_MANIFEST" || [[ "$record" == created ]]; then
        background="$(sed -n 's/^background|//p' "$BTOP_MANIFEST" | head -n 1)"
        background="${background:-true}"
    fi
    now="$(btop_theme)"
    if [[ -z "$record" ]]; then
        : # Only theme_background was changed.
    elif [[ "$now" != '"current"' && "$now" != '"tmac2k"' ]]; then
        # Another theme was picked since: that choice stays.
        [[ ! -f "$BTOP_CONF" ]] || echo "  =  $label (theme changed since install; left as is)"
    elif [[ "$record" == created ]]; then
        if [[ "$(grep -v '^#' "$BTOP_CONF" | grep -Evc '^(color_theme|theme_background) *=')" == 0 ]]; then
            # Still only the lines Kadomo wrote: btop never ran, so remove the file.
            echo "  -  $label"
            run rm -f -- "$BTOP_CONF"
            background=""
        else
            echo "  ~  $label (color_theme → Default; btop's other settings kept)"
            btop_set_theme '"Default"'
        fi
    else
        previous="${record#previous|}"
        echo "  ↩  $label (color_theme → ${previous:-Default})"
        btop_set_theme "${previous:-\"Default\"}"
    fi
    if [[ -n "$background" && -f "$BTOP_CONF" && "$(btop_get theme_background)" == false ]]; then
        echo "  ↩  $label (theme_background → $background)"
        btop_set theme_background "$background"
    fi
    run rm -f -- "$BTOP_MANIFEST"
}

# --- Kadomo Menu ------------------------------------------------------------
# The launcher shows ~/.config/kadomo/current/theme/kadomo-menu.toml while its
# theme is "kadomo". The running app is asked through its CLI; when it is not
# running, the theme line of its config.toml is edited, as the app itself does.

MENU_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/kadomo-menu/config.toml"
MENU_BIN="$HOME/.local/bin/kadomo-menu"

menu_installed() { [[ -x "$MENU_BIN" || -f "$MENU_CONFIG" ]]; }

menu_theme() {
    local id
    # An Omarchy theme (omarchy:<id>) is not one config.toml can name: record
    # the launcher's own theme from config.toml instead.
    if [[ -x "$MENU_BIN" ]] && id="$("$MENU_BIN" theme current 2>/dev/null)" && [[ -n "$id" && "$id" != omarchy:* ]]; then
        printf '%s' "$id"; return 0
    fi
    id="$(awk '/^[ \t]*\[/ { exit } /^[ \t]*theme[ \t]*=/ { sub(/^[^=]*=[ \t]*"?/, ""); sub(/".*$/, ""); print; exit }' "$MENU_CONFIG" 2>/dev/null)"
    printf '%s' "${id:-kadomo-dark}"
}

menu_set_theme() {
    if ((DRY_RUN)); then echo "    would set Kadomo Menu's theme to $1"; return 0; fi
    if [[ -x "$MENU_BIN" ]] && "$MENU_BIN" theme set "$1" >/dev/null 2>&1; then return 0; fi
    [[ -f "$MENU_CONFIG" ]] || return 0
    if awk '/^[ \t]*\[/ { exit 1 } /^[ \t]*theme[ \t]*=/ { found = 1; exit } END { exit !found }' "$MENU_CONFIG"; then
        awk -v id="$1" '!done && /^[ \t]*theme[ \t]*=/ { print "theme = \"" id "\""; done = 1; next } { print }' "$MENU_CONFIG" >"$MENU_CONFIG.tmp.$$"
    else
        { printf 'theme = "%s"\n' "$1"; cat "$MENU_CONFIG"; } >"$MENU_CONFIG.tmp.$$"
    fi
    cat "$MENU_CONFIG.tmp.$$" >"$MENU_CONFIG"
    rm -f -- "$MENU_CONFIG.tmp.$$"
}
