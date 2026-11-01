# The steps of theme-set: stage a theme, render its configs, swap it in, pick
# a wallpaper, then nudge the apps and run your hooks. Sourced after common.sh.

source "$LIB/reloaders.sh"

# Files someone else's theme (git, or another provider) may bring: color data
# and images, nothing that runs or makes anything install. A vscode.json
# (Omarchy themes ship one, naming a Marketplace extension) is ignored.
untrusted_allowed() {
    case "$1" in
        colors.toml|alacritty.toml|btop.theme|kadomo-menu.toml|kadomo-menu.*.toml) return 0 ;;
        preview.*) is_image "$1" ;;
        *) return 1 ;;
    esac
}

# Copies one theme folder over $NEXT_DIR. Backgrounds stay where they are (see
# set_background), and .git is never copied.
overlay_theme() {
    local src="$1" label="$2" untrusted="${3:-}" entry base ignored=()
    if [[ "$untrusted" == untrusted ]] || theme_untrusted "$src"; then
        for entry in "$src"/* "$src"/.[!.]*; do
            [[ -e "$entry" || -L "$entry" ]] || continue
            base="${entry##*/}"
            case "$base" in .git) continue ;; esac
            if [[ "$base" == backgrounds && -d "$entry" && ! -L "$entry" ]]; then
                # Images are used in place; anything else in there is ignored.
                for entry in "$entry"/* "$entry"/.[!.]*; do
                    [[ -e "$entry" || -L "$entry" ]] || continue
                    [[ -f "$entry" && ! -L "$entry" ]] && is_image "$entry" && continue
                    ignored+=("backgrounds/${entry##*/}")
                done
                continue
            fi
            if [[ -f "$entry" && ! -L "$entry" ]] && untrusted_allowed "$base"; then
                cp -P "$entry" "$NEXT_DIR/$base"
            elif [[ " ${QUIET_IGNORE:-} " == *" $base "* ]]; then
                :   # the provider keeps it for its own use
            else
                ignored+=("$base")
            fi
        done
        if ((${#ignored[@]})); then
            warn "theme: $label is someone else's (from git or another provider), so only its colors and images are used. Ignored:"
            printf '  %s\n' "${ignored[@]}" >&2
        fi
    else
        for entry in "$src"/* "$src"/.[!.]*; do
            [[ -e "$entry" || -L "$entry" ]] || continue
            base="${entry##*/}"
            case "$base" in backgrounds|.git) continue ;; esac
            rm -rf -- "$NEXT_DIR/$base"
            cp -RP "$entry" "$NEXT_DIR/$base"
        done
    fi
}

# Fills $NEXT_DIR with theme $1: the built-in copy, then yours on top.
stage_theme() {
    local name="$1" dir
    rm -rf -- "$NEXT_DIR"
    mkdir -p "$NEXT_DIR"
    if dir="$(builtin_theme_dir "$name")"; then overlay_theme "$dir" "$name"; fi
    if dir="$(user_theme_dir "$name")"; then overlay_theme "$dir" "$USER_THEMES/$name"; fi
    if [[ ! -f "$NEXT_DIR/colors.toml" && -f "$NEXT_DIR/alacritty.toml" ]]; then
        import_alacritty "$NEXT_DIR"
        # An untrusted alacritty.toml could set the shell Alacritty starts.
        if dir="$(user_theme_dir "$name")" && theme_untrusted "$dir"; then rm -f -- "$NEXT_DIR/alacritty.toml"; fi
    fi
}

# Fills $NEXT_DIR from an external theme folder (theme-set --external): always
# treated as someone else's, so only its colors and images are used.
stage_external() {
    local folder="$1" label="$2"
    rm -rf -- "$NEXT_DIR"
    mkdir -p "$NEXT_DIR"
    QUIET_IGNORE="shell.toml light.mode" overlay_theme "$folder" "$label" untrusted
    if [[ ! -f "$NEXT_DIR/colors.toml" && -f "$NEXT_DIR/alacritty.toml" ]]; then import_alacritty "$NEXT_DIR"; fi
    rm -f -- "$NEXT_DIR/alacritty.toml"
    # Omarchy marks a light theme with a light.mode file; colors.toml may not say.
    if [[ -f "$folder/light.mode" && ! -L "$folder/light.mode" && -f "$NEXT_DIR/colors.toml" ]] \
        && ! grep -qE '^[[:space:]]*mode[[:space:]]*=' "$NEXT_DIR/colors.toml"; then
        { printf 'mode = "light"\n'; cat "$NEXT_DIR/colors.toml"; } >"$NEXT_DIR/colors.toml.tmp"
        mv -f "$NEXT_DIR/colors.toml.tmp" "$NEXT_DIR/colors.toml"
    fi
}

# The template for an output file: yours in ~/.config/kadomo/themed, else the built-in one.
template_for() {
    if [[ -f "$USER_TEMPLATES/$1.tpl" ]]; then printf '%s' "$USER_TEMPLATES/$1.tpl"
    elif [[ -f "$BUILTIN_TEMPLATES/$1.tpl" ]]; then printf '%s' "$BUILTIN_TEMPLATES/$1.tpl"
    fi
}

# Every output a template exists for, built-in or yours.
template_outputs() {
    local tpl
    for tpl in "$BUILTIN_TEMPLATES"/*.tpl "$USER_TEMPLATES"/*.tpl; do
        [[ -f "$tpl" ]] || continue
        tpl="${tpl##*/}"
        printf '%s\n' "${tpl%.tpl}"
    done | LC_ALL=C sort -u
}

# Renders every template into theme folder $1 (named $2), except outputs the
# theme ships itself, then applies <file>.<section>.toml overrides.
render_templates() {
    local dir="$1" name="$2" out tpl generated=() section
    if [[ ! -f "$dir/colors.toml" ]]; then
        warn "theme: $name has no colors.toml; only the files it ships are used"
        return 0
    fi
    {
        resolve_palette "$dir/colors.toml"
        printf 'theme\t%s\ntheme_name\t%s\n' "$name" "${THEME_LABEL:-$(display_name "$name")}"
    } >"$dir/palette.tsv"
    while IFS= read -r out; do
        [[ -n "$out" && ! -e "$dir/$out" ]] || continue
        tpl="$(template_for "$out")"
        awk -f "$LIB/render.awk" "$dir/palette.tsv" "$tpl" >"$dir/$out"
        generated+=("$out")
    done < <(template_outputs)
    for out in ${generated[@]+"${generated[@]}"}; do
        [[ "$out" == *.toml ]] || continue
        for section in "$dir/${out%.toml}".*.toml; do
            [[ -f "$section" ]] || continue
            section="${section##*/}"; section="${section#"${out%.toml}".}"; section="${section%.toml}"
            awk -v section="$section" -f "$LIB/section.awk" "$dir/${out%.toml}.$section.toml" "$dir/$out" >"$dir/$out.tmp"
            mv -f "$dir/$out.tmp" "$dir/$out"
        done
    done
}

# Moves the staged theme into place: two renames, so the current theme is
# never a half-written folder.
swap_theme() {
    local name="$1"
    rm -rf -- "$OLD_DIR"
    [[ ! -d "$THEME_DIR" ]] || mv "$THEME_DIR" "$OLD_DIR"
    mv "$NEXT_DIR" "$THEME_DIR"
    rm -rf -- "$OLD_DIR"
    printf '%s\n' "$name" >"$NAME_FILE.tmp"
    mv -f "$NAME_FILE.tmp" "$NAME_FILE"
    # Which kind of theme this is: someone else's folder, or one of Kadomo's.
    if [[ -n "${EXTERNAL_FOLDER:-}" ]]; then
        printf '%s\t%s\t%s\n' "$name" "${THEME_LABEL:-$name}" "$EXTERNAL_FOLDER" >"$EXTERNAL_FILE.tmp"
        mv -f "$EXTERNAL_FILE.tmp" "$EXTERNAL_FILE"
    else
        rm -f -- "$EXTERNAL_FILE"
        printf '%s\n' "$name" >"$NATIVE_FILE.tmp"
        mv -f "$NATIVE_FILE.tmp" "$NATIVE_FILE"
    fi
}

# Points current/background at an image and puts it on the desktop.
show_background() {
    ln -s "$1" "$BG_LINK.tmp.$$"
    mv -f "$BG_LINK.tmp.$$" "$BG_LINK"
    if app_enabled wallpaper; then
        osascript -l JavaScript "$LIB/wallpaper.js" set "$1" >/dev/null \
            || warn "theme: could not set the wallpaper to $1"
    fi
}

# Moves to the next wallpaper of theme $1, wrapping around; the first one
# when the current wallpaper is not one of the theme's. Images are used where
# they are rather than copied, so each keeps a path macOS can rely on.
set_background() {
    local name="$1" list current next first="" take=0 file
    list="$(theme_backgrounds "$name")"
    if [[ -z "$list" ]]; then
        # No wallpapers of its own: one drawn from its colors, so a new theme
        # never leaves the last theme's picture on the desktop.
        if file="$(generated_background "$name")"; then show_background "$file"; else rm -f -- "$BG_LINK"; fi
        return 0
    fi
    current="$(readlink "$BG_LINK" 2>/dev/null || true)"
    next=""
    while IFS= read -r file; do
        [[ -n "$first" ]] || first="$file"
        if ((take)); then next="$file"; break; fi
        [[ "$file" == "$current" ]] && take=1
    done <<<"$list"
    show_background "${next:-$first}"
}

# A wallpaper drawn from the current theme's background and accent (theme $1
# has none of its own). Kept in $STATE/wallpapers, named by theme and colors,
# so macOS always has a path that stays put; the 20 newest are kept.
generated_background() {
    local name="$1" palette="$THEME_DIR/palette.tsv" bg accent dir file
    [[ -f "$palette" ]] || return 1
    bg="$(awk -F'\t' '$1 == "background" { print $2; exit }' "$palette")"
    accent="$(awk -F'\t' '$1 == "accent" { print $2; exit }' "$palette")"
    [[ "$bg" =~ ^#[0-9a-fA-F]{6}$ && "$accent" =~ ^#[0-9a-fA-F]{6}$ ]] || return 1
    dir="$STATE/wallpapers"
    file="$dir/$name-$(printf '%s %s' "$bg" "$accent" | shasum | cut -c1-10).png"
    if [[ ! -s "$file" ]]; then
        mkdir -p "$dir"
        osascript -l JavaScript "$LIB/wallpaper.js" render "$file.tmp.png" "$bg" "$accent" >/dev/null 2>&1 \
            && mv -f "$file.tmp.png" "$file" || { rm -f -- "$file.tmp.png"; warn "theme: could not draw a wallpaper for $(theme_label "$name")"; return 1; }
        ls -t "$dir"/*.png 2>/dev/null | tail -n +21 | while IFS= read -r old; do rm -f -- "$old"; done
    fi
    printf '%s' "$file"
}

# Runs every enabled app's reloader at once and waits for them. A reloader
# that hangs is stopped after 20 s; one app never holds up the others.
run_reloaders() {
    local app fn
    for app in $(enabled_apps); do
        fn="reload_${app//-/_}"
        [[ "$app" == wallpaper ]] && continue
        if ! declare -F "$fn" >/dev/null; then warn "theme: no reloader for $app (in $SETTINGS)"; continue; fi
        with_timeout 20 "$fn" &
    done
    wait
}

# Runs each executable in hooks/theme-set.d with the theme name, in name order.
run_hooks() {
    local hook
    for hook in "$HOOKS_DIR"/*; do
        [[ -f "$hook" && -x "$hook" && "$hook" != *.sample ]] || continue
        with_timeout 30 "$hook" "$1" || warn "theme: hook ${hook##*/} failed"
    done
}

# TOML string contents: backslashes and quotes escaped.
toml_escape() { local s="${1//\\/\\\\}"; printf '%s' "${s//\"/\\\"}"; }

# "0-winding-road.jpg" -> "Winding Road".
background_title() {
    local base="${1##*/}"
    base="${base%.*}"
    base="$(printf '%s' "$base" | sed -e 's/^[0-9][0-9]*[-_ ]//' -e 's/[-_]/ /g')"
    display_name "${base// /-}"
}

# Lists the themes under Kadomo Menu's Appearance › Themes, where picking one
# switches every app (the launcher then offers no themes of its own), and the
# current theme's wallpapers under Appearance › Backgrounds. The launcher
# reloads the file when it changes.
write_menu_commands() {
    local name current bin="$KADOMO_THEME_ROOT/bin" file bg tmp
    current="$(current_name || true)"
    bg="$(readlink "$BG_LINK" 2>/dev/null || true)"
    mkdir -p "$(dirname "$MENU_COMMANDS")"
    tmp="$MENU_COMMANDS.tmp.$$"
    {
        printf '# Written by theme-set; changes here are replaced.\n\n'
        printf '[[category]]\nid = "appearance/backgrounds"\ntitle = "Backgrounds"\nsubtitle = "Wallpapers of the current theme"\nicon = "photo.on.rectangle"\nkeywords = ["wallpaper", "background", "desktop"]\n\n'
        while IFS= read -r name; do
            [[ -n "$name" && "$name" != *[[:cntrl:]]* ]] || continue
            printf '[[command]]\nid = "kadomo-theme-%s"\ntitle = "%s"\nsubtitle = "Every app and the wallpaper"\ncategory = "appearance/themes"\nicon = "paintpalette"\nkeywords = ["theme", "colors", "wallpaper"]\n' \
                "$(toml_escape "$name")" "$(toml_escape "$(display_name "$name")")"
            [[ "$name" != "$current" ]] || printf 'hint = "current"\norder = -1\n'
            printf 'exec = "%s"\nargs = ["%s"]\n\n' "$(toml_escape "$bin/theme-set")" "$(toml_escape "$name")"
        done < <(theme_names)
        printf '[[command]]\nid = "kadomo-theme-bg-next"\ntitle = "Next Background"\ncategory = "appearance/backgrounds"\nicon = "arrow.right.circle"\norder = -2\nexec = "%s"\n\n' "$(toml_escape "$bin/theme-bg-next")"
        printf '[[command]]\nid = "kadomo-theme-refresh"\ntitle = "Refresh Theme"\nsubtitle = "Apply template edits"\ncategory = "appearance/themes"\nicon = "arrow.clockwise"\norder = 100\nexec = "%s"\n\n' "$(toml_escape "$bin/theme-refresh")"
        if [[ -n "$current" ]]; then
            while IFS= read -r file; do
                [[ -n "$file" && "$file" != *[[:cntrl:]]* ]] || continue
                printf '[[command]]\ntitle = "%s"\nid = "kadomo-bg-%s"\ncategory = "appearance/backgrounds"\nicon = "photo"\n' \
                    "$(toml_escape "$(background_title "$file")")" "$(toml_escape "$(printf '%s' "$file" | shasum | cut -c1-12)")"
                [[ "$file" != "$bg" ]] || printf 'hint = "current"\n'
                printf 'exec = "%s"\nargs = ["%s"]\n\n' "$(toml_escape "$bin/theme-bg-set")" "$(toml_escape "$file")"
            done < <(theme_backgrounds "$current")
        fi
    } >"$tmp"
    mv -f "$tmp" "$MENU_COMMANDS"
}

# Thumbnails for the pickers: ~/.cache/kadomo/theme-selector/previews/<name>.<ext>,
# symlinks to each theme's preview image, else its first wallpaper. Rebuilt
# only when a theme folder has changed since.
warm_previews() {
    local stamp name image dir ext
    stamp="$(stat -f '%m' "$BUILTIN_THEMES" "$BUILTIN_THEMES"/*/ "$USER_THEMES" "$USER_THEMES"/*/ "$USER_BACKGROUNDS" 2>/dev/null | tr '\n' ' ')"
    [[ "$stamp" != "$(cat "$PREVIEWS/.stamp" 2>/dev/null)" ]] || return 0
    rm -rf -- "$PREVIEWS"
    mkdir -p "$PREVIEWS"
    while IFS= read -r name; do
        image=""
        for dir in "$USER_THEMES/$name" "$BUILTIN_THEMES/$name"; do
            for image in "$dir"/preview.*; do
                [[ -f "$image" && ! -L "$image" ]] && is_image "$image" && break 2
                image=""
            done
        done
        [[ -n "$image" ]] || image="$(theme_backgrounds "$name" | head -n 1)"
        [[ -n "$image" ]] || continue
        ext="$(printf '%s' "${image##*.}" | tr '[:upper:]' '[:lower:]')"
        ln -sf "$image" "$PREVIEWS/$name.$ext"
    done < <(theme_names)
    printf '%s' "$stamp" >"$PREVIEWS/.stamp"
}
