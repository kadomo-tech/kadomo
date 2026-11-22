# Shared by homebrew/install.sh and uninstall.sh, and the top-level install.sh
# and uninstall.sh: where Homebrew's own installer and uninstaller are, the
# PATH block in ~/.zprofile, and the record of what Kadomo installed.

# find_brew, STATE_DIR.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/apps/apps.sh"

# Update the commit and both SHA-256 digests together after reviewing the scripts.
HOMEBREW_INSTALL_COMMIT="c9c975046f78e6e6d662deb801bd461ebd6a54ed"
HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/$HOMEBREW_INSTALL_COMMIT/install.sh"
HOMEBREW_UNINSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/$HOMEBREW_INSTALL_COMMIT/uninstall.sh"
HOMEBREW_INSTALL_SHA256="8fd2f1a5287a7c2e3d7362924c677edcc04c5a0e16448c77132d056bc88cf1ed"
HOMEBREW_UNINSTALL_SHA256="7e5576d1200bdf4fbd1fe38513f129139473ec39f04890ff5c7f1d05480af78a"
CLT_DIR="/Library/Developer/CommandLineTools"

hb_download_script() {
    local url="$1" digest="$2" target="$3" actual
    if ! /usr/bin/curl -q -fsSL --proto '=https' --proto-redir '=https' --retry 2 -o "$target" "$url"; then
        echo "  !  could not download $url" >&2
        return 1
    fi
    actual="$(/usr/bin/shasum -a 256 "$target")" || return 1
    if [[ "${actual%% *}" != "$digest" ]]; then
        echo "  !  Homebrew script checksum mismatch: $url" >&2
        return 1
    fi
}

# One <key>|<value> line per fact: prefix (where Kadomo installed Homebrew),
# clt|added (its installer added the Xcode Command Line Tools), zprofile (the
# file Kadomo's PATH block is in), zprofile-created|1 (Kadomo made that file).
HOMEBREW_RECORD="$STATE_DIR/homebrew-installed.txt"
HOMEBREW_ZPROFILE="${ZDOTDIR:-$HOME}/.zprofile"
HOMEBREW_BEGIN="# >>> kadomo homebrew (added by Kadomo's installer; ./uninstall.sh removes it)"
HOMEBREW_END="# <<< kadomo homebrew"

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
    for file in "$STATE_DIR/apps-installed.txt" "$STATE_DIR/developer-installed.txt" "$STATE_DIR/omniwm-installed.txt" "$STATE_DIR/sketchybar-installed.txt"; do
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
