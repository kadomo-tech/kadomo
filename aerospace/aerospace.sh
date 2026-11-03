# Shared by install.sh, uninstall.sh, remove-legacy.sh and the top-level
# install.sh: where AeroSpace Kadomo and Kadomo's pieces for it live, the
# record of what Kadomo installed, and whether this Mac can run it.
# Sourced, never run. Runs on the Bash 3.2 that ships with macOS.

AEROSPACE_APP="${KADOMO_AEROSPACE_APP:-/Applications/AeroSpace Kadomo.app}"
AEROSPACE_ID="tech.kadomo.aerospace"
# The command inside the app, from the same build.
AEROSPACE_APP_CLI="$AEROSPACE_APP/Contents/Helpers/aerospace"
AEROSPACE_CLI_LINK="$HOME/.local/bin/aerospace"
AEROSPACE_BIN="$HOME/.local/bin/kadomo-aerospace"
BORDERS_BIN="$HOME/.local/bin/kadomo-borders"
AEROSPACE_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/aerospace/aerospace.toml"
# AeroSpace reads this one too, and refuses to start when both exist.
AEROSPACE_DOT_CONFIG="$HOME/.aerospace.toml"
BORDERS_RC="${XDG_CONFIG_HOME:-$HOME/.config}/borders/bordersrc"
BORDERS_FORMULA="felixkratz/formulae/borders"
AEROSPACE_MENU_FILE="${KADOMO_CONFIG:-$HOME/.config/kadomo}/menu/commands/aerospace-kadomo.toml"
# AeroSpace Kadomo's own state (the layout picked for each workspace).
AEROSPACE_LAYOUT_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/aerospace-kadomo"

# One <key>|<value> line per fact: version (the build installed), app (Kadomo
# put the app there), formula (Kadomo installed borders with Homebrew), and
# backup|<path> (a file of yours set aside as <path>.before-kadomo; it goes
# back on uninstall).
# Its name differs from the older aerospace-installed.txt on purpose:
# remove-legacy.sh never mistakes one for the other.
AEROSPACE_STATE_DIR="${KADOMO_STATE_DIR:-$HOME/Library/Application Support/kadomo}"
AEROSPACE_MANIFEST="$AEROSPACE_STATE_DIR/aerospace-kadomo-installed.txt"
AEROSPACE_BACKUP_SUFFIX=".before-kadomo"

# AeroSpace runs on macOS 13 or later, Apple silicon and Intel.
aerospace_supported() {
    local major
    major="$(sw_vers -productVersion 2>/dev/null)"; major="${major%%.*}"
    [[ "$major" =~ ^[0-9]+$ ]] && ((major >= 13))
}
aerospace_requirement() { printf 'needs macOS 13 or later'; }

aerospace_app_version() {
    /usr/bin/plutil -extract CFBundleShortVersionString raw -o - "${1:-$AEROSPACE_APP}/Contents/Info.plist" 2>/dev/null || true
}

# The build release.txt pins: its version, url and sha256.
aerospace_release_field() { # <release.txt> <field>
    sed -n "s/^$2=//p" "$1" | head -n 1
}

# Whether the app in /Applications is the renewed build: 0.21.3-kadomo.3 and
# later. An older Kadomo shipped 0.21.3-kadomo.1 and .2 at the same place;
# remove-legacy.sh removes those.
aerospace_renewed_version() { # <version>
    local n
    [[ "$1" == *-kadomo.* ]] || return 1
    n="${1##*-kadomo.}"; n="${n%%[!0-9]*}"
    [[ "$n" =~ ^[0-9]+$ ]] && ((n >= 3))
}
aerospace_renewed_installed() {
    [[ -s "$AEROSPACE_MANIFEST" ]] || aerospace_renewed_version "$(aerospace_app_version)"
}

# Records a fact, replacing any earlier value of the key.
aerospace_record() { # <key> <value>
    mkdir -p "$AEROSPACE_STATE_DIR"
    aerospace_forget "$1"
    printf '%s|%s\n' "$1" "$2" >>"$AEROSPACE_MANIFEST"
}
# Records one more value of a key that has several (backup), once.
aerospace_record_also() { # <key> <value>
    mkdir -p "$AEROSPACE_STATE_DIR"
    aerospace_forget "$1" "$2"
    printf '%s|%s\n' "$1" "$2" >>"$AEROSPACE_MANIFEST"
}
# Forgets every line with this key, or only the one with this value.
aerospace_forget() { # <key> [value]
    [[ -f "$AEROSPACE_MANIFEST" ]] || return 0
    awk -F'|' -v k="$1" -v v="${2:-}" '!($1 == k && (v == "" || $2 == v))' "$AEROSPACE_MANIFEST" >"$AEROSPACE_MANIFEST.tmp"
    mv "$AEROSPACE_MANIFEST.tmp" "$AEROSPACE_MANIFEST"
}
aerospace_recorded() { # <key>: every value, one per line
    [[ -f "$AEROSPACE_MANIFEST" ]] || return 0
    awk -F'|' -v k="$1" '$1 == k { print $2 }' "$AEROSPACE_MANIFEST"
}

# Whether everything install.sh puts in place is there and current.
aerospace_up_to_date() { # <aerospace/ source folder>
    local src="$1" version
    version="$(aerospace_release_field "$src/release.txt" version)"
    [[ -d "$AEROSPACE_APP" && "$(aerospace_app_version)" == "$version" ]] || return 1
    [[ -L "$AEROSPACE_CLI_LINK" && "$(readlink "$AEROSPACE_CLI_LINK")" == "$AEROSPACE_APP_CLI" ]] || return 1
    cmp -s "$src/bin/kadomo-aerospace" "$AEROSPACE_BIN" && cmp -s "$src/bin/kadomo-borders" "$BORDERS_BIN" \
        && cmp -s "$src/../wm/bin/kadomo-wm" "$HOME/.local/bin/kadomo-wm" \
        && [[ -f "$AEROSPACE_CONFIG" && -f "$BORDERS_RC" && -f "$AEROSPACE_MENU_FILE" ]] \
        && PATH="$PATH:/opt/homebrew/bin:/usr/local/bin" command -v borders >/dev/null 2>&1
}
