# Shared by homebrew/install.sh and uninstall.sh, and the top-level install.sh
# and uninstall.sh: where Homebrew's own installer and uninstaller are, the
# PATH block in ~/.zprofile, and the record of what Kadomo installed.

# find_brew, STATE_DIR.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/apps/apps.sh"

# Homebrew's own scripts, the way https://brew.sh installs it. The KADOMO_
# variables here replace them and the Command Line Tools folder, for tests.
HOMEBREW_INSTALL_URL="${KADOMO_HOMEBREW_INSTALL_URL:-https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh}"
HOMEBREW_UNINSTALL_URL="${KADOMO_HOMEBREW_UNINSTALL_URL:-https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh}"

# One <key>|<value> line per fact: prefix (where Kadomo installed Homebrew),
# clt|added (its installer added the Xcode Command Line Tools), zprofile (the
# file Kadomo's PATH block is in), zprofile-created|1 (Kadomo made that file).
HOMEBREW_RECORD="$STATE_DIR/homebrew-installed.txt"
HOMEBREW_ZPROFILE="${ZDOTDIR:-$HOME}/.zprofile"
HOMEBREW_BEGIN="# >>> kadomo homebrew (added by Kadomo's installer; ./uninstall.sh removes it)"
HOMEBREW_END="# <<< kadomo homebrew"
CLT_DIR="${KADOMO_CLT_DIR:-/Library/Developer/CommandLineTools}"

declare -F short_path >/dev/null || short_path() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

hb_recorded() { [[ -f "$HOMEBREW_RECORD" ]] && awk -F'|' -v k="$1" '$1 == k { print $2; exit }' "$HOMEBREW_RECORD"; }
hb_record() { mkdir -p "$STATE_DIR"; printf '%s|%s\n' "$1" "$2" >>"$HOMEBREW_RECORD"; }

# Homebrew needs an administrator account (it asks for your password, and
# makes its folder with sudo).
is_admin() { id -Gn 2>/dev/null | tr ' ' '\n' | grep -qx admin; }

# Where a Homebrew prefix's brew is: <prefix>/bin/brew.
hb_prefix_of() { dirname "$(dirname "$1")"; }

hb_has_block() { [[ -f "$1" ]] && grep -qxF -- "$HOMEBREW_BEGIN" "$1"; }

# The packages in Homebrew that someone asked for (formulae, not the ones
# installed only as dependencies, and casks), short names, one per line.
hb_packages() { # <brew>
    { "$1" leaves --installed-on-request 2>/dev/null || "$1" leaves 2>/dev/null || true
      "$1" list --cask -1 2>/dev/null || true; } | sed 's|.*/||; /^$/d' | sort -u
}

# The Homebrew names Kadomo's other parts recorded installing, one per line,
# short names (felixkratz/formulae/borders is borders).
hb_kadomo_packages() {
    local file
    for file in "$STATE_DIR/apps-installed.txt" "$STATE_DIR/developer-installed.txt" "$STATE_DIR/omniwm-installed.txt" \
        "$STATE_DIR/aerospace-kadomo-installed.txt"; do
        [[ -f "$file" ]] && awk -F'|' '$1 == "formula" || $1 == "cask" { print $2 }' "$file"
    done
    [[ -f "$STATE_DIR/packages-installed.txt" ]] && cut -d'|' -f1 "$STATE_DIR/packages-installed.txt"
    [[ -e "$STATE_DIR/moonlight-mouse/installed-linearmouse" ]] && echo linearmouse
    return 0
}

# The packages in Homebrew that are not Kadomo's: yours, which keep Homebrew here.
hb_other_packages() { # <brew>
    local kadomo
    kadomo="$(hb_kadomo_packages | sed 's|.*/||' | sort -u)"
    hb_packages "$1" | while IFS= read -r name; do
        printf '%s\n' "$kadomo" | grep -qxF -- "$name" || printf '%s\n' "$name"
    done
}
