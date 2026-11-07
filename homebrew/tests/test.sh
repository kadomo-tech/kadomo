#!/bin/bash
# Checks homebrew/install.sh and uninstall.sh in a throwaway HOME, with a
# stand-in brew, sudo, and Homebrew install and uninstall scripts. Nothing is
# installed on this Mac, nothing is downloaded, and no real shell config is
# read or changed.
#
# Usage: homebrew/tests/test.sh
set -uo pipefail

HB="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-homebrew-test.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$WORK"' EXIT
PASS=0
FAIL=0

check() {
    local what="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); printf '  ✓ %s\n' "$what"
    else FAIL=$((FAIL + 1)); printf '  ✗ %s\n' "$what"; fi
}
has() { grep -qF -- "$2" "$1" 2>/dev/null; }
lacks() { ! grep -qF -- "$2" "$1" 2>/dev/null; }

# A fresh world: HOME, a Homebrew prefix that does not exist yet, stand-in
# install/uninstall scripts (file:// URLs), and a sudo that only runs rm.
# PACKAGES lists what the stand-in brew says is installed.
setup() {
    W="$WORK/$1"
    rm -rf -- "$W"; mkdir -p "$W/home" "$W/bin" "$W/scripts"
    PREFIX="$W/prefix"
    cat >"$W/scripts/install.sh" <<EOS
#!/bin/bash
[[ "\${NONINTERACTIVE:-}" == 1 ]] || { echo "not NONINTERACTIVE" >&2; exit 1; }
mkdir -p '$PREFIX/bin' '$W/clt'
cat >'$PREFIX/bin/brew' <<'EOB'
#!/bin/bash
case "\$1" in
    --version) echo "Homebrew 9.9.9" ;;
    leaves) cat "\$(dirname "\$0")/../formulae" 2>/dev/null ;;
    list) cat "\$(dirname "\$0")/../casks" 2>/dev/null ;;
esac
exit 0
EOB
chmod +x '$PREFIX/bin/brew'
echo "installed" >>'$W/log'
EOS
    cat >"$W/scripts/uninstall.sh" <<EOS
#!/bin/bash
echo "uninstall \$*" >>'$W/log'
rm -rf '$PREFIX/bin'
EOS
    cat >"$W/bin/sudo" <<EOS
#!/bin/bash
echo "sudo \$*" >>'$W/log'
case "\$1" in -n|-v) exit 0 ;; rm) "\$@" ;; esac
exit 0
EOS
    chmod +x "$W/bin/sudo"
    export HOME="$W/home" ZDOTDIR="$W/home" KADOMO_STATE_DIR="$W/state" KADOMO_BREW="$PREFIX/bin/brew"
    export KADOMO_TEST_HOOKS=1 KADOMO_HOMEBREW_INSTALL_URL="file://$W/scripts/install.sh" KADOMO_HOMEBREW_UNINSTALL_URL="file://$W/scripts/uninstall.sh"
    export KADOMO_CLT_DIR="$W/clt" PATH="$W/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    RECORD="$W/state/homebrew-installed.txt"
}

echo "Installing Homebrew"
setup install
"$HB/install.sh" >"$W/out" 2>&1; status=$?
check "it succeeds" test "$status" -eq 0
check "it ran Homebrew's installer" has "$W/log" installed
check "brew is there" test -x "$PREFIX/bin/brew"
check "it recorded the prefix" has "$RECORD" "prefix|$PREFIX"
check "it recorded the Command Line Tools it added" has "$RECORD" "clt|added"
check "~/.zprofile has the PATH block" has "$HOME/.zprofile" "eval \"\$($PREFIX/bin/brew shellenv)\""
check "it recorded that it made ~/.zprofile" has "$RECORD" "zprofile-created|1"
check "it asks for a new terminal window" has "$W/out" "Open a new terminal window"

echo "Installing again"
"$HB/install.sh" >"$W/out2" 2>&1
check "it leaves Homebrew as it is" has "$W/out2" "already installed"
check "one PATH block" test "$(grep -c 'brew shellenv' "$HOME/.zprofile")" -eq 1

echo "Uninstalling: a package of yours keeps Homebrew"
echo wget >"$PREFIX/formulae"
"$HB/uninstall.sh" >"$W/out3" 2>&1
check "it says why" has "$W/out3" "you installed wget"
check "Homebrew stays" test -x "$PREFIX/bin/brew"
check "the PATH block stays" has "$HOME/.zprofile" "brew shellenv"
check "Kadomo's record goes" test ! -e "$RECORD"
check "Homebrew's uninstaller did not run" lacks "$W/log" uninstall

echo "Uninstalling: only Kadomo's packages left"
setup kadomo-left
"$HB/install.sh" >/dev/null 2>&1
printf 'cask|ghostty\n' >"$W/state/apps-installed.txt"
echo ghostty >"$PREFIX/casks"
"$HB/uninstall.sh" --dry-run >"$W/dry" 2>&1
check "the plan removes Homebrew (the apps go before it)" has "$W/dry" "Homebrew in $PREFIX"
"$HB/uninstall.sh" >"$W/out" 2>&1
check "for real, Homebrew stays for Kadomo's Ghostty" has "$W/out" "left in place: Kadomo's ghostty"
check "and says to run it again" has "$W/out" "Still needs you"
check "the record stays for that run" test -s "$RECORD"

echo "Uninstalling: nothing left in it"
rm -f "$PREFIX/casks" "$W/state/apps-installed.txt"
echo "# mine" >>"$HOME/.zprofile"
"$HB/uninstall.sh" >"$W/out" 2>&1; status=$?
check "it succeeds" test "$status" -eq 0
check "it ran Homebrew's uninstaller for that prefix" has "$W/log" "uninstall --force --path=$PREFIX"
check "brew is gone" test ! -e "$PREFIX/bin/brew"
check "the Command Line Tools it added are gone" test ! -e "$W/clt"
check "the PATH block is gone" lacks "$HOME/.zprofile" "brew shellenv"
check "your line in ~/.zprofile stays" has "$HOME/.zprofile" "# mine"
check "the record is gone" test ! -e "$RECORD"
"$HB/uninstall.sh" >"$W/out" 2>&1
check "uninstalling again finds nothing" has "$W/out" "no homebrew installed"

echo "Uninstalling: ~/.zprofile only had Kadomo's block"
setup zprofile
"$HB/install.sh" >/dev/null 2>&1
"$HB/uninstall.sh" >/dev/null 2>&1
check "the file Kadomo made is gone" test ! -e "$HOME/.zprofile"

echo "Command Line Tools that were here before stay"
setup clt
mkdir -p "$W/clt"
"$HB/install.sh" >/dev/null 2>&1
check "not recorded" lacks "$RECORD" "clt|"
"$HB/uninstall.sh" >/dev/null 2>&1
check "still there" test -d "$W/clt"

echo "A ~/.zprofile that sets up brew already"
setup has-shellenv
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >"$HOME/.zprofile"
"$HB/install.sh" >/dev/null 2>&1
check "gets no second block" test "$(grep -c 'brew shellenv' "$HOME/.zprofile")" -eq 1
"$HB/uninstall.sh" >/dev/null 2>&1
check "keeps its own line" has "$HOME/.zprofile" "brew shellenv"

echo "the test overrides"
stray() { env -u KADOMO_TEST_HOOKS KADOMO_HOMEBREW_INSTALL_URL=https://example.invalid/x KADOMO_HOMEBREW_UNINSTALL_URL=https://example.invalid/x KADOMO_CLT_DIR=/tmp/x \
    /bin/bash -c 'source "$0/homebrew.sh"; printf "%s %s %s" "$HOMEBREW_INSTALL_URL" "$HOMEBREW_UNINSTALL_URL" "$CLT_DIR"' "$HB"; }
check "count for nothing outside the tests" test "$(stray)" = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh /Library/Developer/CommandLineTools"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
((FAIL == 0))
