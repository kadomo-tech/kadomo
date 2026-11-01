# VS Code in the Kadomo theme's colors. Sourced (after common.sh) by the
# vscode reloader, theme-vscode, and uninstall.sh. Plain Bash 3.2.
#
# Every theme gets a VS Code color theme rendered from its palette
# (themed/vscode-theme.json.tpl, ported from Omarchy), installed as a local
# extension, "Kadomo", in ~/.vscode/extensions/kadomo.kadomo-theme. A theme
# whose vscode.json names a Marketplace theme (most Omarchy themes do: Tokyo
# Night is enkia.tokyo-night) gets that one: it is installed in the
# background, and Kadomo's colors show until it is there. Either way only
# workbench.colorTheme in settings.json changes; the rest stays as written.
#
# What Kadomo did is in $STATE/vscode.txt, one line each, so theme-vscode
# disable (and uninstalling the theme manager) undoes exactly that:
#   before|<theme>      workbench.colorTheme before Kadomo (empty: unset)
#   set|<theme>         a theme Kadomo set
#   extension|<id>      a Marketplace extension Kadomo installed
#   created|<path>      a file or folder Kadomo made (settings.json, the registry)

VSCODE_USER="${KADOMO_VSCODE_USER:-$HOME/Library/Application Support/Code/User}"
VSCODE_SETTINGS="$VSCODE_USER/settings.json"
VSCODE_EXTENSIONS="${KADOMO_VSCODE_EXTENSIONS:-$HOME/.vscode/extensions}"
VSCODE_THEME_ID="kadomo.kadomo-theme"
VSCODE_THEME_LABEL="Kadomo"
VSCODE_RECORD="$STATE/vscode.txt"
VSCODE_LOG="$STATE/vscode.log"
VSCODE_APP="Visual Studio Code.app"

# A path with the home folder as ~ (setup.sh has the same one).
declare -F short_path >/dev/null || short_path() { case "$1" in "$HOME"/*) printf "~%s" "${1#"$HOME"}" ;; *) printf "%s" "$1" ;; esac; }

vscode_js() { osascript -l JavaScript "$LIB/vscode.js" "$@"; }

# VS Code's command line tool: in the app, else on PATH. KADOMO_VSCODE_CLI
# replaces the search (empty: no VS Code), for tests.
vscode_cli() {
    local path
    if [[ -n "${KADOMO_VSCODE_CLI+set}" ]]; then
        [[ -n "$KADOMO_VSCODE_CLI" && -x "$KADOMO_VSCODE_CLI" ]] && { printf '%s' "$KADOMO_VSCODE_CLI"; return 0; }
        return 1
    fi
    for path in "/Applications/$VSCODE_APP/Contents/Resources/app/bin/code" \
        "$HOME/Applications/$VSCODE_APP/Contents/Resources/app/bin/code" "$(command -v code 2>/dev/null)"; do
        [[ -n "$path" && -x "$path" ]] && { printf '%s' "$path"; return 0; }
    done
    return 1
}

vscode_recorded() { [[ -f "$VSCODE_RECORD" ]] && grep -qxF -- "$1" "$VSCODE_RECORD"; }
vscode_record() {
    vscode_recorded "$1" && return 0
    mkdir -p "$STATE"
    printf '%s\n' "$1" >>"$VSCODE_RECORD"
}

# mkdir -p, recording each folder it made.
vscode_mkdir() {
    local dir="$1" made=()
    while [[ ! -d "$dir" ]]; do made+=("$dir"); dir="$(dirname "$dir")"; done
    ((${#made[@]})) || return 0
    mkdir -p "$1"
    for dir in "${made[@]}"; do vscode_record "created|$dir"; done
}

vscode_current_theme() { [[ -f "$VSCODE_SETTINGS" ]] && vscode_js get "$VSCODE_SETTINGS" 2>/dev/null; }

# Writes settings.json through a temporary file next to it, in place, so a
# settings.json that is a symlink (a dotfiles repository) stays one.
vscode_edit_settings() { # set <name> | unset
    local tmp="$VSCODE_SETTINGS.kadomo-tmp.$$"
    if vscode_js "$1" "$VSCODE_SETTINGS" ${2+"$2"} >"$tmp"; then
        cat "$tmp" >"$VSCODE_SETTINGS"
        rm -f -- "$tmp"
    else
        rm -f -- "$tmp"
        warn "theme: VS Code: could not edit $(short_path "$VSCODE_SETTINGS"); its color theme is unchanged"
        return 1
    fi
}

# Sets workbench.colorTheme, remembering the one from before Kadomo first.
vscode_set_theme() {
    local name="$1" now
    now="$(vscode_current_theme)" || now=""
    if ! grep -q '^before|' "$VSCODE_RECORD" 2>/dev/null; then
        [[ -f "$VSCODE_SETTINGS" ]] || vscode_record "created|$VSCODE_SETTINGS"
        vscode_record "before|$now"
    fi
    vscode_record "set|$name"
    [[ "$now" != "$name" ]] || return 0
    vscode_mkdir "$VSCODE_USER"
    vscode_edit_settings set "$name"
}

# Whether a Marketplace extension is installed: VS Code's registry, else
# (no registry yet) VS Code itself.
vscode_has_extension() { # <cli> <id>
    if [[ -f "$VSCODE_EXTENSIONS/extensions.json" ]]; then
        vscode_js installed "$VSCODE_EXTENSIONS" "$2" 2>/dev/null
    else
        "$1" --list-extensions 2>/dev/null | grep -Fixq -- "$2"
    fi
}

# The current theme's colors as the "Kadomo" extension. Its version comes
# from the colors, so VS Code reloads it when they change and keeps its cache
# when they do not.
vscode_install_generated() {
    local src="$THEME_DIR/vscode-theme.json" dir="$VSCODE_EXTENSIONS/$VSCODE_THEME_ID" version ui=vs-dark
    [[ -f "$src" ]] || return 1
    version="1.0.$(cksum <"$src" | cut -d' ' -f1)"
    [[ "$(awk -F'\t' '$1 == "mode" { print $2; exit }' "$THEME_DIR/palette.tsv" 2>/dev/null)" != light ]] || ui=vs
    vscode_mkdir "$dir/themes"
    [[ -f "$VSCODE_EXTENSIONS/extensions.json" ]] || vscode_record "created|$VSCODE_EXTENSIONS/extensions.json"
    # A real file rather than a link into current/theme: VS Code watches it
    # (_watch), and current/theme is replaced by a rename on every switch.
    cat "$src" >"$dir/themes/kadomo-color-theme.json"
    cat >"$dir/package.json" <<EOF
{
    "name": "kadomo-theme",
    "displayName": "Kadomo",
    "description": "The current Kadomo theme's colors (kadomo-theme-manager writes this; theme-vscode disable removes it)",
    "publisher": "kadomo",
    "version": "$version",
    "engines": { "vscode": "^1.70.0" },
    "categories": ["Themes"],
    "contributes": {
        "themes": [{
            "label": "$VSCODE_THEME_LABEL",
            "uiTheme": "$ui",
            "path": "./themes/kadomo-color-theme.json",
            "_watch": true
        }]
    }
}
EOF
    vscode_js register "$VSCODE_EXTENSIONS" "$VSCODE_THEME_ID" "$version"
}

# The theme's own VS Code pick from its vscode.json, checked: "<name>\t<id>"
# (the id empty for a theme VS Code has built in), or nothing.
vscode_descriptor() {
    [[ -f "$THEME_DIR/vscode.json" && ! -L "$THEME_DIR/vscode.json" ]] || return 1
    vscode_js descriptor "$THEME_DIR/vscode.json" 2>/dev/null
}

# Shows the current theme in VS Code. With "background" (theme-set), a
# Marketplace theme still to download is fetched by a process of its own, so
# the switch never waits on the network; otherwise it is fetched here.
vscode_apply() {
    local mode="${1:-}" cli line name="" ext=""
    cli="$(vscode_cli)" || return 0
    vscode_install_generated || { warn "theme: VS Code: the current theme has no vscode-theme.json (try theme-refresh)"; return 1; }
    if line="$(vscode_descriptor)"; then
        name="${line%%$'\t'*}"; ext="${line#*$'\t'}"
    fi
    if [[ -z "$name" ]]; then
        vscode_set_theme "$VSCODE_THEME_LABEL"
    elif [[ -z "$ext" ]] || vscode_has_extension "$cli" "$ext"; then
        vscode_set_theme "$name"
    else
        # Kadomo's colors for this theme while its own downloads.
        vscode_set_theme "$VSCODE_THEME_LABEL"
        if [[ "$mode" == background ]]; then
            nohup "$KADOMO_THEME_ROOT/bin/theme-vscode" fetch "$ext" "$name" </dev/null >/dev/null 2>&1 &
        else
            vscode_fetch "$ext" "$name"
        fi
    fi
}

# Installs Marketplace extension $1 and, when the theme showing still wants
# it, switches VS Code to its theme $2. One at a time.
vscode_fetch() {
    local ext="$1" name="$2" cli status=0
    cli="$(vscode_cli)" || return 0
    lock_acquire "$STATE/vscode.lock"
    if ! vscode_has_extension "$cli" "$ext"; then
        mkdir -p "$STATE"
        if with_timeout 180 "$cli" --install-extension "$ext" >>"$VSCODE_LOG" 2>&1 && vscode_has_extension "$cli" "$ext"; then
            vscode_record "extension|$ext"
        else
            warn "theme: VS Code: could not install $ext from the Marketplace (offline?); it shows Kadomo's colors for this theme"
            status=1
        fi
    fi
    if ((status == 0)) && [[ "$(vscode_descriptor)" == "$name"$'\t'"$ext" ]]; then
        vscode_set_theme "$name" || status=1
    fi
    lock_release "$STATE/vscode.lock"
    return "$status"
}

# Whether Kadomo has left anything in VS Code.
vscode_touched() { [[ -s "$VSCODE_RECORD" || -d "$VSCODE_EXTENSIONS/$VSCODE_THEME_ID" ]]; }

# Undoes it all: workbench.colorTheme goes back to what it was (unless you
# picked another since), and the Kadomo extension, the Marketplace themes
# Kadomo installed, and files and folders it made go. Uses the caller's
# DRY_RUN when there is one.
vscode_remove() {
    local dry="${DRY_RUN:-0}" now before cli ext rel path
    vscode_touched || return 0
    if now="$(vscode_current_theme)" && vscode_recorded "set|$now"; then
        before="$(sed -n 's/^before|//p' "$VSCODE_RECORD" 2>/dev/null | head -n 1)"
        if [[ -n "$before" ]]; then
            echo "  ↩  VS Code color theme → $before"
            ((dry)) || vscode_edit_settings set "$before" || true
        else
            echo "  -  VS Code color theme ($now, set by Kadomo)"
            ((dry)) || vscode_edit_settings unset || true
        fi
    elif [[ -n "${now:-}" ]]; then
        echo "  =  VS Code color theme ($now: changed since; left as is)"
    fi
    if [[ -d "$VSCODE_EXTENSIONS/$VSCODE_THEME_ID" ]]; then
        echo "  -  VS Code theme extension Kadomo ($(short_path "$VSCODE_EXTENSIONS/$VSCODE_THEME_ID"))"
        if ! ((dry)); then
            vscode_js unregister "$VSCODE_EXTENSIONS" "$VSCODE_THEME_ID" >/dev/null 2>&1 || true
            rm -rf -- "${VSCODE_EXTENSIONS:?}/$VSCODE_THEME_ID"
        fi
    fi
    cli="$(vscode_cli || true)"
    while IFS= read -r ext; do
        [[ -n "$ext" ]] || continue
        echo "  -  VS Code extension $ext (Kadomo installed it for a theme)"
        ((dry)) && continue
        if [[ -n "$cli" ]] && "$cli" --uninstall-extension "$ext" >/dev/null 2>&1; then continue; fi
        # VS Code is gone already: its registry entry and folder go by hand.
        while IFS= read -r rel; do
            [[ -n "$rel" && "$rel" != */* && "$rel" != . && "$rel" != .. ]] && rm -rf -- "${VSCODE_EXTENSIONS:?}/$rel"
        done < <(vscode_js unregister "$VSCODE_EXTENSIONS" "$ext" 2>/dev/null)
    done < <(sed -n 's/^extension|//p' "$VSCODE_RECORD" 2>/dev/null)
    ((dry)) && return 0
    # What Kadomo made, when nothing else is in it now; deepest first.
    while IFS= read -r path; do
        if [[ "$path" == "$VSCODE_SETTINGS" ]]; then
            [[ -f "$path" ]] && vscode_js bare "$path" 2>/dev/null && rm -f -- "$path"
        elif [[ "$path" == */extensions.json ]]; then
            [[ -f "$path" && "$(tr -d '[:space:]' <"$path")" == "[]" ]] && rm -f -- "$path"
        else
            rmdir "$path" 2>/dev/null || true
        fi
    done < <(sed -n 's/^created|//p' "$VSCODE_RECORD" 2>/dev/null | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-)
    rm -f -- "$VSCODE_RECORD" "$VSCODE_LOG"
}

# theme.conf's apps line, with vscode added (on) or taken out (off).
vscode_follow() { # on|off
    local apps
    [[ -f "$SETTINGS" ]] || return 0
    apps=" $(sed -n 's/^[[:space:]]*apps[[:space:]]*=[[:space:]]*//p' "$SETTINGS" | tail -n 1) "
    apps="${apps// vscode / }"
    [[ "$1" == off ]] || apps="$apps vscode"
    apps="$(printf '%s' "$apps" | tr -s ' ' | sed 's/^ //; s/ $//')"
    awk -v apps="$apps" '/^[[:space:]]*apps[[:space:]]*=/ { if (!done) print "apps = " apps; done = 1; next } { print } END { if (!done) print "apps = " apps }' \
        "$SETTINGS" >"$SETTINGS.tmp.$$" && mv -f "$SETTINGS.tmp.$$" "$SETTINGS"
}
