#!/bin/bash
# Installs Homebrew with its own installer (https://brew.sh), when it is not on
# this Mac yet: in /opt/homebrew on Apple silicon, /usr/local on Intel. It asks
# for your password, and needs an administrator account. Homebrew's installer
# adds the Xcode Command Line Tools when they are missing, which can take a
# few minutes. On Apple silicon, a marked block in ~/.zprofile puts brew on
# your PATH. What it did is recorded, so ./uninstall.sh can undo it.
#
# Usage: ./install.sh
#
# Runs on the Bash 3.2 that ships with macOS.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/homebrew.sh"

case "${1:-}" in
    "") ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

if brew="$(find_brew)"; then
    echo "  =  Homebrew (already installed in $(hb_prefix_of "$brew"))"
    exit 0
fi
if ! is_admin; then
    echo "  !  Homebrew needs an administrator account, and $(id -un) is not one." >&2
    echo "     Ask an administrator to install it (https://brew.sh), then run Kadomo's installer again." >&2
    exit 1
fi

# The password now, before the long part; Homebrew's installer runs without
# asking anything (NONINTERACTIVE), so sudo must already be ready for it.
if ! sudo -n true 2>/dev/null; then
    if [[ ! -t 0 ]] && ! { : </dev/tty; } 2>/dev/null; then
        echo "  !  Homebrew asks for your password: run this in a terminal." >&2
        exit 1
    fi
    echo "  Homebrew needs your Mac password to install."
    sudo -v -p "  Password for $(id -un): " </dev/tty || { echo "  !  no password, so Homebrew was not installed" >&2; exit 1; }
fi
# Keep sudo ready while the installer runs: the Command Line Tools alone can take longer than sudo remembers.
( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 30; done ) &
keep_alive=$!

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-homebrew.XXXXXX")"
cleanup() {
    if [[ -n "$keep_alive" ]]; then { kill "$keep_alive"; wait "$keep_alive"; } 2>/dev/null || true; fi
    rm -rf -- "$WORK"
}
trap cleanup EXIT

had_clt=0; [[ -d "$CLT_DIR" ]] && had_clt=1

echo "  ↓  Homebrew's installer ($HOMEBREW_INSTALL_URL)"
if ! curl -fsSL --retry 2 -o "$WORK/install.sh" "$HOMEBREW_INSTALL_URL" || [[ ! -s "$WORK/install.sh" ]]; then
    echo "  !  could not download Homebrew's installer; check the network and run this again" >&2
    exit 1
fi
echo "  +  Homebrew (its installer prints what it does below)"
if ! NONINTERACTIVE=1 /bin/bash "$WORK/install.sh"; then
    echo "  !  Homebrew's installer failed; see above" >&2
    exit 1
fi
if ! brew="$(find_brew)"; then
    echo "  !  Homebrew's installer finished, but brew is not where it should be" >&2
    exit 1
fi
prefix="$(hb_prefix_of "$brew")"
rm -f -- "$HOMEBREW_RECORD"
hb_record prefix "$prefix"
((had_clt)) || [[ ! -d "$CLT_DIR" ]] || hb_record clt added

# /usr/local/bin is on PATH already; /opt/homebrew/bin is not, so new shells get it from ~/.zprofile.
todo=()
if [[ "$prefix" != /usr/local ]]; then
    if [[ -f "$HOMEBREW_ZPROFILE" ]] && grep -q 'brew shellenv' "$HOMEBREW_ZPROFILE"; then
        echo "  =  $(short_path "$HOMEBREW_ZPROFILE") (sets up brew already)"
    else
        [[ -e "$HOMEBREW_ZPROFILE" ]] || hb_record zprofile-created 1
        echo "  +  $(short_path "$HOMEBREW_ZPROFILE") (a marked block that puts brew on your PATH)"
        printf '\n%s\neval "$(%s shellenv)"\n%s\n' "$HOMEBREW_BEGIN" "$brew" "$HOMEBREW_END" >>"$HOMEBREW_ZPROFILE"
        hb_record zprofile "$HOMEBREW_ZPROFILE"
    fi
    if [[ "${KADOMO_NEW_SHELL:-}" == 1 ]]; then
        echo "  i  this window gets a new zsh when the install finishes, so brew works here too"
    else
        todo+=("Open a new terminal window (or tab) before you type brew yourself. Kadomo put brew on your PATH in $(short_path "$HOMEBREW_ZPROFILE"), but zsh reads that file only when a window opens, so in this window brew says \"command not found\". Kadomo's own steps find brew without it; nothing else to do.")
    fi
fi

echo "  ✓  Homebrew $("$brew" --version 2>/dev/null | head -n 1 | awk '{ print $2 }') in $prefix"
if ((${#todo[@]})); then
    printf '\n  Still needs you:\n'
    for ((i=0; i<${#todo[@]}; i++)); do printf '  %s. %s\n' "$((i+1))" "${todo[i]}"; done
fi
exit 0
