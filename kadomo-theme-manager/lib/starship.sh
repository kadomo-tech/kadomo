# Starship for zsh, in the Kadomo theme's colors. Sourced (after common.sh and
# apply.sh) by theme-starship, the starship reloader, preview.sh, and
# uninstall.sh. Plain Bash 3.2, BSD tools.
#
# What it owns, all in ~/.config/kadomo/starship:
#   starship.toml   the active config; zsh points STARSHIP_CONFIG at it, and
#                   Starship reads it again at every prompt
#   init.zsh        sets STARSHIP_CONFIG and starts Starship (once); also turns
#                   on bright `ls` colors (CLICOLOR, LSCOLORS, LS_COLORS), since
#                   it is Kadomo's one zsh entry point and those are just env vars
#   settings.conf   match, theme, icons (data, never sourced)
#   enabled.txt     what enable changed, so disable undoes exactly that
# and one marked block in your .zshrc that sources init.zsh. A personal
# ~/.config/starship.toml is never touched.

STARSHIP_GENERATOR=1
STARSHIP_DIR="$KADOMO_CONFIG/starship"
STARSHIP_TOML="$STARSHIP_DIR/starship.toml"
STARSHIP_INIT="$STARSHIP_DIR/init.zsh"
STARSHIP_SETTINGS="$STARSHIP_DIR/settings.conf"
STARSHIP_RECORD="$STARSHIP_DIR/enabled.txt"
STARSHIP_BEGIN="# >>> kadomo starship (added by theme-starship; theme-starship disable removes it)"
STARSHIP_END="# <<< kadomo starship"
# Prompt roles, in the order they are written. themed/starship-palette.toml.tpl
# gives each theme's color for each: seg_X is a block's background, seg_X_fg
# its matching, legible text; success/error are the plain ❯/✗ at the end.
STARSHIP_ROLES="seg_user seg_user_fg seg_dir seg_dir_fg seg_git seg_git_fg seg_runtime seg_runtime_fg seg_duration seg_duration_fg success error"

# `ls` colors: bold (bright) directory/symlink/socket/executable, in the
# basic 8 ANSI slots, left default otherwise. Index-based, not hex, so they
# need no per-theme rendering: a terminal's bold colors follow its own bright
# ANSI palette, which Ghostty already sets from the theme's bright_* colors
# (themed/ghostty.conf.tpl, slots 8-15), so these come out theme-matched for
# free. BSD format (macOS's own `ls -G`), then the GNU one other tools read
# (eza, coreutils ls, grep --color, ...) for the types that matter; GNU ls
# falls back to its own defaults for any type left unset.
LS_COLORS_BSD="ExGxFxdxCxegedabagacad"
LS_COLORS_GNU="di=1;34:ln=1;36:so=1;35:pi=33:ex=1;32"

# A path with the home folder as ~ (setup.sh has the same one).
declare -F short_path >/dev/null || short_path() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

# --- settings and records: key = value / key=value lines, never sourced --------

starship_setting() { # <key> [default]
    local value=""
    [[ -f "$STARSHIP_SETTINGS" ]] && value="$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$STARSHIP_SETTINGS" | tail -n 1 | tr -d '[:space:]')"
    printf '%s' "${value:-${2:-}}"
}

starship_set_setting() { # <key> <value>
    local tmp="$STARSHIP_SETTINGS.tmp.$$"
    mkdir -p "$STARSHIP_DIR"
    if [[ -f "$STARSHIP_SETTINGS" ]]; then
        awk -v k="$1" -v v="$2" '
            $0 ~ "^[ \t]*" k "[ \t]*=" { if (!done) print k " = " v; done = 1; next }
            { print }
            END { if (!done) print k " = " v }' "$STARSHIP_SETTINGS" >"$tmp"
    else
        {
            printf "# Kadomo's Starship settings; theme-starship changes them.\n"
            printf '#   match = on    the prompt follows the Kadomo theme; off keeps "theme"\n'
            printf '#   theme         the prompt theme while match is off\n'
            printf '#   icons         nerd (needs a Nerd Font) or plain\n'
            printf '%s = %s\n' "$1" "$2"
        } >"$tmp"
    fi
    mv -f "$tmp" "$STARSHIP_SETTINGS"
}

starship_record() { [[ -f "$STARSHIP_RECORD" ]] && sed -n "s/^$1=//p" "$STARSHIP_RECORD" | head -n 1; }
starship_on() { [[ -s "$STARSHIP_RECORD" ]]; }

# --- finding things -----------------------------------------------------------

# Starship however it was installed: on PATH, Homebrew (Apple silicon, Intel),
# its own install script, cargo. KADOMO_STARSHIP_SEARCH (colon-separated
# paths) replaces the list, for tests.
starship_bin() {
    local candidates=() path
    if [[ -n "${KADOMO_STARSHIP_SEARCH+set}" ]]; then
        IFS=: read -r -a candidates <<<"$KADOMO_STARSHIP_SEARCH"
    else
        candidates=("$(command -v starship 2>/dev/null || true)" /opt/homebrew/bin/starship /usr/local/bin/starship
                    "$HOME/.local/bin/starship" "$HOME/.cargo/bin/starship")
    fi
    for path in ${candidates[@]+"${candidates[@]}"}; do
        [[ -n "$path" && -f "$path" && -x "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}

# "1.27.0", or nothing when the binary does not answer like Starship.
starship_version() { with_timeout 5 "$1" --version 2>/dev/null | sed -n 's/^starship v\{0,1\}\([0-9][0-9.]*\).*/\1/p' | head -n 1; }

# The folder zsh reads its startup files from: ZDOTDIR as zsh itself sees it
# (it is often set in ~/.zshenv), else HOME.
starship_zdotdir() {
    local dir=""
    if command -v zsh >/dev/null 2>&1; then
        dir="$(with_timeout 5 zsh -c 'printf "%s" "${ZDOTDIR:-$HOME}"' </dev/null 2>/dev/null || true)"
    fi
    [[ -n "$dir" && -d "$dir" ]] || dir="${ZDOTDIR:-$HOME}"
    printf '%s' "${dir%/}"
}

# The .zshrc Kadomo uses: the one it edited, else ZDOTDIR's.
starship_zshrc() {
    local file
    file="$(starship_record zshrc)"
    [[ -n "$file" ]] || file="$(starship_zdotdir)/.zshrc"
    printf '%s' "$file"
}

# icons default: nerd when a Nerd Font is installed (Kadomo installs
# JetBrainsMono Nerd Font for the launcher; Ghostty has the symbols built
# in), plain otherwise. KADOMO_FONT_DIRS overrides where to look.
starship_default_icons() {
    local dirs=() dir file
    if [[ -n "${KADOMO_FONT_DIRS+set}" ]]; then IFS=: read -r -a dirs <<<"$KADOMO_FONT_DIRS"
    else dirs=("$HOME/Library/Fonts" /Library/Fonts); fi
    for dir in ${dirs[@]+"${dirs[@]}"}; do
        for file in "$dir"/*NerdFont*; do [[ -e "$file" ]] && { printf nerd; return; }; done
    done
    printf plain
}

starship_icons() {
    local icons
    icons="$(starship_setting icons)"
    case "$icons" in nerd|plain) printf '%s' "$icons" ;; *) starship_default_icons ;; esac
}

# The theme the prompt shows: the Kadomo theme while match is on, else the one
# picked with theme-starship set (the Kadomo theme again if that one is gone).
starship_theme() {
    local name current
    current="$(current_name 2>/dev/null || true)"
    [[ -n "$current" ]] || current=tmac2k
    if [[ "$(starship_setting match on)" == off ]]; then
        name="$(starship_setting theme)"
        if [[ -n "$name" ]] && theme_exists "$name"; then printf '%s' "$name"; return; fi
        [[ -z "$name" ]] || warn "theme-starship: the prompt theme $name is gone; using $(display_name "$current")"
    fi
    printf '%s' "$current"
}

# --- quoting ----------------------------------------------------------------

# A zsh word for a path: "$HOME/..." under the home folder, else single-quoted.
zsh_path_word() {
    local rest
    if [[ "$1" == "$HOME"/* ]]; then
        rest="$(printf '%s' "${1#"$HOME"}" | sed -e 's/[\\"$`]/\\&/g')"
        printf '"$HOME%s"' "$rest"
    else
        printf "'%s'" "$(printf '%s' "$1" | sed -e "s/'/'\\\\''/g")"
    fi
}

# The one line Kadomo's block holds.
starship_block_body() {
    local word
    word="$(zsh_path_word "$STARSHIP_INIT")"
    printf '[[ -r %s ]] && source %s' "$word" "$word"
}

# --- the config ----------------------------------------------------------------

# Symbols for icons $1, shared by the config and the preview so they match.
# CAP_L/CAP_R are the M365Princess-style diamond cap at each end of the row;
# ARROW is the powerline chevron merging one block into the next. All three
# are fixed, top-level parts of the format (not any one module's), so the
# chain stays joined whether or not the block next to a given arrow has
# anything to show. Empty in plain mode, so the row is then plain color
# blocks, flush against each other, and still works in any font.
starship_symbols() {
    SYM_OK=$'\xe2\x9d\xaf'          # ❯
    SYM_ERR=$'\xe2\x9c\x97'         # ✗
    if [[ "$1" == nerd ]]; then
        SYM_BRANCH=$'\xee\x82\xa0 ' SYM_NODE=$'\xee\x9c\x98 ' SYM_JAVA=$'\xee\x89\x96 ' SYM_PYTHON=$'\xee\x88\xb5 '
        SYM_RUST=$'\xee\x9e\xa8 ' SYM_GO=$'\xee\x98\xa7 ' SYM_RO=$' \xef\x80\xa3'
        CAP_L=$'\xee\x82\xb6' ARROW=$'\xee\x82\xb0' CAP_R=$'\xee\x82\xb0 '
    else
        SYM_BRANCH="" SYM_NODE="node " SYM_JAVA="java " SYM_PYTHON="py " SYM_RUST="rs " SYM_GO="go " SYM_RO=" (ro)"
        CAP_L="" ARROW=" " CAP_R=""
    fi
}

# The prompt layout, the same for every theme; colors are palette role names.
# Literal TOML strings ('...'), so nothing in them is an escape. Styled after
# oh-my-posh's M365Princess: one chevron-joined row of solid color blocks
# (user, folder, Git, runtime, a slow command's time); then ❯ or ✗. The
# chevrons between blocks are fixed, so a block with nothing to show (no SSH,
# no Git repo, a fast command) just leaves a thin sliver of its color rather
# than breaking the chain, the same way oh-my-posh's own presets handle it.
starship_layout() {
    starship_symbols "$1"
    cat <<EOF
"\$schema" = 'https://starship.rs/config-schema.json'
palette = 'kadomo'
add_newline = false
# User and host show only over SSH (or as root).
format = '[$CAP_L](fg:seg_user)\$username\$hostname[$ARROW](fg:seg_user bg:seg_dir)\$directory[$ARROW](fg:seg_dir bg:seg_git)\$git_branch\$git_state\$git_status[$ARROW](fg:seg_git bg:seg_runtime)\$nodejs\$java\$python\$rust\$golang[$ARROW](fg:seg_runtime bg:seg_duration)\$cmd_duration[$CAP_R](fg:seg_duration)\$line_break\$character'

[username]
style_user = 'bg:seg_user fg:seg_user_fg'
style_root = 'bg:seg_user fg:seg_user_fg bold'
format = '[ \$user ](\$style)'

[hostname]
ssh_only = true
style = 'bg:seg_user fg:seg_user_fg'
format = '[@\$hostname ](\$style)'

[directory]
style = 'bg:seg_dir fg:seg_dir_fg'
read_only = '$SYM_RO'
read_only_style = 'bg:seg_dir fg:seg_dir_fg bold'
truncation_length = 3
truncate_to_repo = true
format = '[ \$path ](\$style)[\$read_only](\$read_only_style)'

[git_branch]
symbol = '$SYM_BRANCH'
style = 'bg:seg_git fg:seg_git_fg'
format = '[ \$symbol\$branch ](\$style)'

[git_state]
style = 'bg:seg_git fg:seg_git_fg'
format = '([\$state( \$progress_current/\$progress_total) ](\$style))'

[git_status]
style = 'bg:seg_git fg:seg_git_fg'
format = '([\$all_status\$ahead_behind ](\$style))'

[nodejs]
symbol = '$SYM_NODE'
style = 'bg:seg_runtime fg:seg_runtime_fg'
format = '[ \$symbol(\$version) ](\$style)'

[java]
symbol = '$SYM_JAVA'
style = 'bg:seg_runtime fg:seg_runtime_fg'
format = '[ \$symbol(\$version) ](\$style)'

[python]
symbol = '$SYM_PYTHON'
style = 'bg:seg_runtime fg:seg_runtime_fg'
format = '[ \$symbol\$version( \(\$virtualenv\)) ](\$style)'

[rust]
symbol = '$SYM_RUST'
style = 'bg:seg_runtime fg:seg_runtime_fg'
format = '[ \$symbol(\$version) ](\$style)'

[golang]
symbol = '$SYM_GO'
style = 'bg:seg_runtime fg:seg_runtime_fg'
format = '[ \$symbol(\$version) ](\$style)'

[cmd_duration]
min_time = 2000
style = 'bg:seg_duration fg:seg_duration_fg'
format = '[ \$duration ](\$style)'

[character]
success_symbol = '[$SYM_OK](bold success)'
error_symbol = '[$SYM_ERR](bold error)'
EOF
}

# A theme's role colors as 'role = "#rrggbb"' lines, in role order. The
# current theme's are already rendered; another theme is staged and rendered
# in a scratch folder, so nothing current changes. Only well-formed lines of a
# theme's own starship-palette.toml are used; a missing role fails.
starship_palette() {
    local name="$1" file tmp="" status=0
    if [[ "$name" == "$(current_name 2>/dev/null || true)" && -f "$THEME_DIR/starship-palette.toml" ]]; then
        file="$THEME_DIR/starship-palette.toml"
    else
        theme_exists "$name" || { warn "theme-starship: no theme named $name"; return 1; }
        tmp="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-starship.XXXXXX")"
        ( NEXT_DIR="$tmp/theme"; stage_theme "$name"; render_templates "$NEXT_DIR" "$name" ) >/dev/null 2>&1 || true
        file="$tmp/theme/starship-palette.toml"
    fi
    awk -v roles="$STARSHIP_ROLES" '
        BEGIN { n = split(roles, R, " ") }
        {
            line = $0
            gsub(/[ \t]/, "", line)
            if (line ~ /^[a-z_]+="#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]"$/) {
                eq = index(line, "=")
                C[substr(line, 1, eq - 1)] = tolower(substr(line, eq + 2, 7))
            }
        }
        END {
            for (i = 1; i <= n; i++) if (!(R[i] in C)) { printf "theme-starship: no %s color\n", R[i] > "/dev/stderr"; exit 1 }
            for (i = 1; i <= n; i++) printf "%s = \"%s\"\n", R[i], C[R[i]]
        }' "$file" 2>/dev/null || status=1
    [[ -z "$tmp" ]] || rm -rf -- "$tmp"
    return "$status"
}

# The whole config for theme $1 with icons $2 and palette lines $3.
starship_config() {
    printf "# Kadomo's Starship config, written by theme-starship. Changes here are\n"
    printf '# replaced: make your own with theme-starship disable and ~/.config/starship.toml.\n'
    printf '# kadomo-starship generator=%s theme=%s icons=%s\n\n' "$STARSHIP_GENERATOR" "$1" "$2"
    starship_layout "$2"
    printf '\n[palettes.kadomo]\n%s\n' "$3"
}

# Checks a config before it is used: every line a table header, a comment, or
# key = a quoted string, number, or boolean; every role in the palette. Then,
# with Starship installed, Starship itself must render it without a config warning.
starship_validate() {
    local file="$1" bin tmp err role
    awk '
        /^[ \t]*(#.*)?$/ { next }
        /^\[[a-z_.]+\]$/ { next }
        /^("\$schema"|[A-Za-z_]+) = (\047[^\047]*\047|"[^"\\]*"|true|false|[0-9]+)$/ { next }
        { printf "theme-starship: line %d is not valid: %s\n", NR, $0 > "/dev/stderr"; bad = 1 }
        END { exit bad }' "$file" || return 1
    for role in $STARSHIP_ROLES; do
        awk -v r="$role" '/^\[palettes\.kadomo\]$/ { p = 1; next } /^\[/ { p = 0 } p && $1 == r { found = 1 } END { exit !found }' "$file" \
            || { warn "theme-starship: the palette has no $role"; return 1; }
    done
    bin="$(starship_bin)" || return 0
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-starship-check.XXXXXX")"
    ( cd "$tmp" && with_timeout 5 env STARSHIP_CONFIG="$file" STARSHIP_CACHE="$tmp" STARSHIP_LOG=warn "$bin" prompt >/dev/null 2>"$tmp/err" ) || true
    err="$(grep -i 'starship::config\|toml' "$tmp/err" 2>/dev/null | head -n 5 || true)"
    rm -rf -- "$tmp"
    [[ -z "$err" ]] || { warn "theme-starship: Starship does not accept the config:"; warn "$err"; return 1; }
}

# Writes starship.toml for the prompt theme: built next to it, checked, then
# moved over it in one step. On any failure the old one stays.
starship_apply() {
    local name icons palette tmp
    name="$(starship_theme)"
    icons="$(starship_icons)"
    palette="$(starship_palette "$name")" || { warn "theme-starship: no prompt colors for $(display_name "$name"); the prompt keeps its last ones"; return 1; }
    mkdir -p "$STARSHIP_DIR"
    tmp="$STARSHIP_TOML.tmp.$$"
    starship_config "$name" "$icons" "$palette" >"$tmp"
    if ! starship_validate "$tmp"; then
        rm -f -- "$tmp"
        warn "theme-starship: kept the previous prompt config"
        return 1
    fi
    mv -f "$tmp" "$STARSHIP_TOML"
}

# init.zsh: point Starship at Kadomo's config, and start it (mode init) unless
# it already runs in this shell. Mode config leaves starting it to your own
# "starship init" line, so it is never started twice.
starship_write_init() {
    local mode="$1" tmp="$STARSHIP_INIT.tmp.$$"
    mkdir -p "$STARSHIP_DIR"
    {
        printf '# Written by theme-starship (Kadomo); theme-starship disable removes it.\n'
        printf '# Starship reads this config at every prompt, so theme changes show at the next one.\n'
        printf 'export STARSHIP_CONFIG=%s\n' "$(zsh_path_word "$STARSHIP_TOML")"
        printf '# Bright, theme-matched ls colors (follows Ghostty'"'"'s ANSI palette); a value\n'
        printf '# already set (here or earlier in your zsh startup) wins.\n'
        printf 'export CLICOLOR="${CLICOLOR:-1}"\n'
        printf 'export LSCOLORS="${LSCOLORS:-%s}"\n' "$LS_COLORS_BSD"
        printf 'export LS_COLORS="${LS_COLORS:-%s}"\n' "$LS_COLORS_GNU"
        if [[ "$mode" == init ]]; then
            cat <<'EOF'
if (( ! ${+functions[prompt_starship_precmd]} && ! ${+functions[starship_precmd]} )); then
    for _kadomo_starship in "${commands[starship]:-}" /opt/homebrew/bin/starship /usr/local/bin/starship \
        "$HOME/.local/bin/starship" "$HOME/.cargo/bin/starship"; do
        [[ -n "$_kadomo_starship" && -x "$_kadomo_starship" ]] || continue
        eval "$("$_kadomo_starship" init zsh)"
        break
    done
    unset _kadomo_starship
fi
EOF
        else
            printf '# Your own "starship init" line starts Starship; this only picks the config.\n'
        fi
    } >"$tmp"
    mv -f "$tmp" "$STARSHIP_INIT"
}

# --- reading .zshrc -----------------------------------------------------------

starship_has_block() { [[ -f "$1" ]] && grep -qxF -- "$STARSHIP_BEGIN" "$1"; }

# The lines inside Kadomo's block.
starship_block_text() {
    awk -v b="$STARSHIP_BEGIN" -v e="$STARSHIP_END" '$0 == b { s = 1; next } s && $0 == e { exit } s { print }' "$1"
}

# A line of yours, outside the block, that sources Kadomo's init.zsh.
starship_manual_line() {
    [[ -f "$1" ]] || return 1
    awk -v b="$STARSHIP_BEGIN" -v e="$STARSHIP_END" '
        $0 == b { s = 1; next } s { if ($0 == e) s = 0; next }
        /^[ \t]*#/ { next }
        /kadomo\/starship\/init\.zsh/ { found = 1 }
        END { exit !found }' "$1"
}

# What in your zsh setup Kadomo must not override silently, one
# "<kind>|<file>|<line>|<text>" per finding: init (Starship is already
# started), config (STARSHIP_CONFIG is set), prompt (another prompt manager),
# personal (your own starship.toml). Comments and Kadomo's block are skipped.
starship_scan() {
    local dir="$1" file seen=" " personal
    for file in "$dir/.zshenv" "$dir/.zprofile" "$dir/.zshrc" "$dir/.zlogin" "$HOME/.zshenv"; do
        [[ -f "$file" && "$seen" != *" $file "* ]] || continue
        seen="$seen$file "
        awk -v b="$STARSHIP_BEGIN" -v e="$STARSHIP_END" -v file="$file" '
            function found(kind) { t = $0; sub(/^[ \t]+/, "", t); print kind "|" file "|" FNR "|" substr(t, 1, 80) }
            $0 == b { s = 1; next } s { if ($0 == e) s = 0; next }
            /^[ \t]*#/ { next }
            /kadomo\/starship\/init\.zsh/ { next }
            /starship[ \t]+init/ { found("init"); next }
            /STARSHIP_CONFIG[ \t]*=/ { found("config"); next }
            /powerlevel(9|10)k|p10k|oh-my-posh|spaceship/ { found("prompt"); next }
            /^[ \t]*(export[ \t]+)?ZSH_THEME=["\047]?[A-Za-z0-9]/ { found("prompt"); next }
            /prompt[ \t]+pure|pure\.zsh|sindresorhus\/pure/ { found("prompt"); next }
        ' "$file"
    done
    personal="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
    [[ ! -f "$personal" ]] || printf 'personal|%s|0|\n' "$personal"
}

# --- enable, disable, status ------------------------------------------------

# Adds "starship" to theme.conf's apps, so theme-set rebuilds the prompt config.
starship_follow_theme() {
    [[ -f "$SETTINGS" ]] || return 0
    app_enabled starship && return 0
    [[ -n "${KADOMO_THEME_APPS+set}" ]] && return 0
    sed -i '' -e 's/^\([[:space:]]*apps[[:space:]]*=.*[^[:space:]]\)[[:space:]]*$/\1 starship/' "$SETTINGS"
}

# The settings a first enable starts with: matching on, icons by font.
starship_default_settings() {
    [[ -n "$(starship_setting match)" ]] || starship_set_setting match on
    [[ -n "$(starship_setting icons)" ]] || starship_set_setting icons "$(starship_default_icons)"
}

starship_say_timing() {
    echo "  i  Open a new terminal tab (or run exec zsh) for the new prompt. After that, theme"
    echo "     changes show at the next prompt in every open shell."
}

# Turns Starship on for zsh. Returns 0 when it is on, 1 on failure, and 3 when
# your setup needs a decision first (nothing is changed then).
#   --use-kadomo      go ahead despite your own Starship or prompt setup
#   --edit-symlinked  .zshrc is a symlink: add the block to the file it points to
starship_enable() {
    local use=0 follow=0 bin version dir zshrc findings="" kind file lnum text mode=init body created=0 backup="" target
    while (($#)); do
        case "$1" in
            --use-kadomo) use=1 ;;
            --edit-symlinked) follow=1 ;;
            *) warn "theme-starship enable: unknown option $1"; return 2 ;;
        esac
        shift
    done
    if ! bin="$(starship_bin)"; then
        warn "  !  Starship is not installed. Install it with: brew install starship"
        warn "     (or developer/install.sh --only starship in Kadomo; without Homebrew,"
        warn "     see https://starship.rs/guide/#step-1-install-starship), then run this again."
        return 1
    fi
    version="$(starship_version "$bin")"
    [[ -n "$version" ]] || { warn "  !  $bin does not run (no version); reinstall Starship (brew reinstall starship)"; return 1; }

    # Already on: bring the files up to date, nothing more.
    if starship_on; then
        zshrc="$(starship_record zshrc)"
        if starship_has_block "$zshrc" || starship_manual_line "$zshrc"; then
            starship_default_settings
            starship_apply || return 1
            starship_write_init "$(starship_record mode)"
            starship_follow_theme
            echo "  =  Starship $version is already on in $(short_path "$zshrc"); config refreshed"
            return 0
        fi
        # The block was taken out by hand: start over.
        rm -f -- "$STARSHIP_RECORD"
    fi

    dir="$(starship_zdotdir)"
    zshrc="$dir/.zshrc"
    findings="$(starship_scan "$dir")"
    if [[ -n "$findings" ]] && ! ((use)); then
        echo "  !  Your zsh setup has a prompt of its own. Nothing was changed:"
        while IFS='|' read -r kind file lnum text; do
            case "$kind" in
                init) echo "     $(short_path "$file"):$lnum starts Starship already ($text)."
                      echo "       Kadomo would leave that line and only point it at Kadomo's config, so it is not started twice." ;;
                config) echo "     $(short_path "$file"):$lnum sets STARSHIP_CONFIG ($text)."
                        echo "       Kadomo's block comes later and would win while it is on." ;;
                prompt) echo "     $(short_path "$file"):$lnum sets up another prompt ($text)."
                        echo "       Starship would draw over it in new shells; turn that one off yourself so both do not load." ;;
                personal) echo "     $(short_path "$file") is your own Starship config. Kadomo leaves it as it is, but"
                          echo "       Starship reads Kadomo's config instead while this is on (and yours again after disable)." ;;
            esac
        done <<<"$findings"
        echo "     Use Kadomo's prompt anyway: theme-starship enable --use-kadomo"
        echo "     Keep yours: do nothing."
        return 3
    fi
    if printf '%s\n' "$findings" | grep -q '^init|'; then mode=config; fi
    body="$(starship_block_body)"

    if starship_manual_line "$zshrc"; then
        starship_default_settings
        starship_apply || return 1
        starship_write_init "$mode"
        printf 'zshrc=%s\ncreated=0\nbackup=\nmode=%s\nmanual=1\nbody=%s\n' "$zshrc" "$mode" "$body" >"$STARSHIP_RECORD"
        starship_follow_theme
        echo "  =  $(short_path "$zshrc") already sources Kadomo's init.zsh; Starship $version is on"
        return 0
    fi

    if [[ -L "$zshrc" ]] && ! ((follow)); then
        target="$(readlink "$zshrc")"
        echo "  !  $(short_path "$zshrc") is a symlink (to $target), likely from a dotfiles repository,"
        echo "     so Kadomo does not edit it on its own. Nothing was changed. Either add this line to it:"
        echo "       $body"
        echo "     and run theme-starship enable again, or let Kadomo add its block to the file it points to:"
        echo "       theme-starship enable --use-kadomo --edit-symlinked"
        return 3
    fi

    # The config and init.zsh first: .zshrc only changes once they work.
    starship_default_settings
    starship_apply || return 1
    starship_write_init "$mode"

    if [[ -e "$zshrc" ]]; then
        backup="$zshrc.kadomo-backup.$(date +%Y%m%d-%H%M%S)"
        cp -p "$zshrc" "$backup" || { warn "  !  could not back up $(short_path "$zshrc"); nothing was changed there"; return 1; }
    else
        created=1
        mkdir -p "$(dirname "$zshrc")"
    fi
    # Appended, so a symlinked .zshrc stays a symlink and every other line stays as it is.
    if ! printf '\n%s\n%s\n%s\n' "$STARSHIP_BEGIN" "$body" "$STARSHIP_END" >>"$zshrc"; then
        warn "  !  could not write $(short_path "$zshrc")"
        [[ -z "$backup" ]] || rm -f -- "$backup"
        return 1
    fi
    printf 'zshrc=%s\ncreated=%s\nbackup=%s\nmode=%s\nmanual=0\nbody=%s\n' "$zshrc" "$created" "$backup" "$mode" "$body" >"$STARSHIP_RECORD"
    starship_follow_theme
    if ((created)); then echo "  +  $(short_path "$zshrc") (made, with Kadomo's Starship block)"
    else echo "  +  $(short_path "$zshrc") (Kadomo's Starship block; backed up to ${backup##*/})"; fi
    [[ "$mode" == init ]] || echo "  i  Your own starship init line keeps starting Starship; Kadomo only picks its config."
    echo "  ✓  Starship $version is on for zsh, in $(display_name "$(starship_theme)")'s colors"
    starship_say_timing
    return 0
}

# Turns it off again: takes out Kadomo's block (unless you changed it), and
# removes init.zsh and the config. Settings stay for next time; Starship
# itself is never uninstalled here. Returns 1 when something needs you.
starship_disable() {
    local zshrc created backup body status=0 tmp label
    if ! starship_on; then
        rm -f -- "$STARSHIP_INIT" "$STARSHIP_TOML"
        echo "  =  Starship is not on through Kadomo"
        return 0
    fi
    zshrc="$(starship_record zshrc)"; created="$(starship_record created)"
    backup="$(starship_record backup)"; body="$(starship_record body)"
    label="$(short_path "$zshrc")"
    if starship_has_block "$zshrc"; then
        if [[ "$(starship_block_text "$zshrc")" == "$body" ]]; then
            tmp="$(mktemp "${TMPDIR:-/tmp}/kadomo-zshrc.XXXXXX")"
            # The block, and the blank line enable put before it.
            awk -v b="$STARSHIP_BEGIN" -v e="$STARSHIP_END" '
                $0 == b { skip = 1; held = 0; next }
                skip { if ($0 == e) skip = 0; next }
                { if (held) print ""; held = 0; if ($0 == "") { held = 1; next } print }
                END { if (held) print "" }' "$zshrc" >"$tmp"
            if [[ "$created" == 1 && -z "$(tr -d '[:space:]' <"$tmp")" ]]; then
                rm -f -- "$zshrc"
                echo "  -  $label (Kadomo made it, and it held only the Starship block)"
            else
                # Written in place, so a symlinked .zshrc stays a symlink.
                cat "$tmp" >"$zshrc"
                echo "  -  $label (Kadomo's Starship block)"
            fi
            rm -f -- "$tmp"
        else
            echo "  !  The Kadomo block in $label was changed since it was added, so it is left in place." >&2
            echo "     Delete the lines from \"$STARSHIP_BEGIN\" to \"$STARSHIP_END\" yourself; it does nothing now." >&2
            status=1
        fi
    elif starship_manual_line "$zshrc"; then
        echo "  !  $label sources Kadomo's init.zsh on a line of yours; remove it yourself (it does nothing now)." >&2
    fi
    if [[ -n "$backup" && -f "$backup" ]]; then
        if [[ -f "$zshrc" ]] && cmp -s "$zshrc" "$backup"; then
            rm -f -- "$backup"
        else
            echo "  i  $(short_path "$backup") (the .zshrc from before) is kept; delete it when you no longer need it"
        fi
    fi
    rm -f -- "$STARSHIP_INIT" "$STARSHIP_TOML" "$STARSHIP_RECORD"
    echo "  -  $(short_path "$STARSHIP_DIR")/init.zsh and starship.toml"
    echo "  i  New terminal tabs start without Kadomo's prompt; open shells keep it until you close"
    echo "     them or run exec zsh. Starship itself stays installed."
    return "$status"
}

# Sets STARSHIP_STATE to not-installed, installed (not on), enabled, or
# attention, and STARSHIP_PROBLEM and STARSHIP_FIX for attention.
starship_state() {
    local bin zshrc
    STARSHIP_STATE="" STARSHIP_PROBLEM="" STARSHIP_FIX=""
    bin="$(starship_bin || true)"
    if ! starship_on; then
        [[ -n "$bin" ]] && STARSHIP_STATE=installed || STARSHIP_STATE=not-installed
        return 0
    fi
    zshrc="$(starship_record zshrc)"
    if [[ -z "$bin" ]] || [[ -z "$(starship_version "$bin")" ]]; then
        STARSHIP_PROBLEM="Starship is on for zsh, but the starship command is missing or does not run; shells start with the default prompt."
        STARSHIP_FIX="brew install starship (or brew reinstall starship), or theme-starship disable"
    elif ! starship_has_block "$zshrc" && ! starship_manual_line "$zshrc"; then
        STARSHIP_PROBLEM="Kadomo's block is gone from $(short_path "$zshrc")."
        STARSHIP_FIX="theme-starship enable (adds it again), or theme-starship disable"
    elif starship_has_block "$zshrc" && [[ "$(starship_block_text "$zshrc")" != "$(starship_record body)" ]]; then
        STARSHIP_PROBLEM="Kadomo's block in $(short_path "$zshrc") was edited."
        STARSHIP_FIX="put it back as: $(starship_record body)"
    elif [[ ! -f "$STARSHIP_INIT" || ! -f "$STARSHIP_TOML" ]]; then
        STARSHIP_PROBLEM="Kadomo's init.zsh or starship.toml is missing."
        STARSHIP_FIX="theme-starship enable (writes them again)"
    elif ! starship_validate "$STARSHIP_TOML" 2>/dev/null; then
        STARSHIP_PROBLEM="Kadomo's starship.toml is not valid."
        STARSHIP_FIX="theme-starship apply"
    fi
    if [[ -n "$STARSHIP_PROBLEM" ]]; then STARSHIP_STATE=attention; else STARSHIP_STATE=enabled; fi
}

# --- preview: simulated prompts, drawn here; nothing runs, nothing changes ----

starship_fg() { printf '\033[38;2;%d;%d;%dm' $((16#${1:1:2})) $((16#${1:3:2})) $((16#${1:5:2})); }
starship_bg() { printf '\033[48;2;%d;%d;%dm' $((16#${1:1:2})) $((16#${1:3:2})) $((16#${1:5:2})); }

# Prints the sample prompts for theme $1 with icons $2, on the theme's own
# background, as the generated config draws them: one chevron-joined row of
# color blocks, each from the palette, with its own legible text. The
# chevrons are fixed (as in the real config), so an empty block between two
# of them shows as a thin sliver of its color, same as the real prompt.
starship_preview() {
    local name="$1" icons="$2" palette bg="" dir role value r=$'\033[0m' on
    local seg_user seg_user_fg seg_dir seg_dir_fg seg_git seg_git_fg
    local seg_runtime seg_runtime_fg seg_duration seg_duration_fg success error
    palette="$(starship_palette "$name")" || return 1
    while IFS= read -r line; do
        role="${line%% =*}"; value="${line#*\"}"; value="${value%\"}"
        case " $STARSHIP_ROLES " in *" $role "*) eval "$role=\$value" ;; esac
    done <<<"$palette"
    for dir in "$USER_THEMES/$name" "$BUILTIN_THEMES/$name"; do
        [[ -f "$dir/colors.toml" ]] || continue
        bg="$(resolve_palette "$dir/colors.toml" 2>/dev/null | awk -F'\t' '$1 == "background" { print $2; exit }')"
        break
    done
    [[ -n "$bg" ]] || bg="#000000"
    on="$(starship_bg "$bg")"
    starship_symbols "$icons"
    # One prompt line on the background, padded so the background shows.
    show() { printf '  %s %s\033[K%s\n' "$on" "$1" "$r"; }
    label() { printf '  %s\n' "$1"; }
    cap() { local color="$1" glyph="$2"; [[ -z "$glyph" ]] || printf '%s%s%s%s' "$(starship_fg "$color")" "$glyph" "$r" "$on"; }
    arrow() { printf '%s%s%s%s%s' "$(starship_fg "$1")" "$(starship_bg "$2")" "$ARROW" "$r" "$on"; }
    block() { local segbg="$1" segfg="$2" text="$3"; [[ -z "$text" ]] || printf '%s%s %s %s%s' "$(starship_bg "$segbg")" "$(starship_fg "$segfg")" "$text" "$r" "$on"; }
    # A full row: user, folder, git, runtime, and duration text (empty for
    # none), joined exactly as $CAP_L$username...$ARROW...$CAP_R is in the
    # real format string.
    row() {
        printf '%s%s%s%s%s%s%s%s%s%s' \
            "$(cap "$seg_user" "$CAP_L")" "$(block "$seg_user" "$seg_user_fg" "$1")" "$(arrow "$seg_user" "$seg_dir")" \
            "$(block "$seg_dir" "$seg_dir_fg" "$2")" "$(arrow "$seg_dir" "$seg_git")" \
            "$(block "$seg_git" "$seg_git_fg" "$3")" "$(arrow "$seg_git" "$seg_runtime")" \
            "$(block "$seg_runtime" "$seg_runtime_fg" "$4")" "$(arrow "$seg_runtime" "$seg_duration")" \
            "$(block "$seg_duration" "$seg_duration_fg" "$5")$(cap "$seg_duration" "$CAP_R")"
    }
    local ok no
    ok="$(starship_fg "$success")$SYM_OK$r$on" no="$(starship_fg "$error")$SYM_ERR$r$on"
    printf '  Starship prompt: %s, %s icons (simulated preview; nothing runs, nothing changes)\n\n' "$(display_name "$name")" "$icons"
    label "A folder";                 show "$(row '' '~/Documents' '' '' '') "; show "$ok "
    label "A Git repository with changes"; show "$(row '' '~/code/kadomo' "${SYM_BRANCH}main [!?]" '' '') "; show "$ok "
    label "A Node.js project";        show "$(row '' '~/code/web-app' "${SYM_BRANCH}main" "${SYM_NODE}v26.13.0" '') "; show "$ok "
    label "After a failed command";   show "$(row '' '~/code/kadomo' "${SYM_BRANCH}main" '' '') "; show "$no "
    label "After a slow command";     show "$(row '' '~/code/kadomo' '' '' '12s') "; show "$ok "
    printf '\n'
}
