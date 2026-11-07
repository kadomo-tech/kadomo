#!/bin/bash
# Checks kadomo-omniwm's workspace keys in a throwaway HOME. OmniWM is not
# started, and no real setting is read or changed.
#
# Usage: omniwm/tests/test.sh
set -uo pipefail

OW="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kadomo-omniwm-test.XXXXXX")"
trap '[[ -n "${KEEP:-}" ]] || rm -rf "$WORK"' EXIT
PASS=0
FAIL=0

check() {
    local what="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); printf '  ✓ %s\n' "$what"
    else FAIL=$((FAIL + 1)); printf '  ✗ %s\n' "$what"; fi
}
same() { cmp -s "$1" "$2"; }
bound() { # <id> <binding>
    awk -v id="id = \"$1\"" '$0 == id { print prev; exit } { prev = $0 }' "$S" | grep -qxF "binding = \"$2\""
}

# A fresh world, with the hotkeys OmniWM writes on its first start. $2 is the
# binding of switchWorkspace.next, $3 of an unrelated hotkey.
setup() {
    W="$WORK/$1"; H="$W/home"; S="$H/.config/omniwm/settings.toml"
    rm -rf -- "$W"; mkdir -p "$H/.config/omniwm"
    cat >"$S" <<TOML
schemaVersion = 4

[general]
hotkeysEnabled = true

[[hotkeys]]
binding = "${2:-Unassigned}"
id = "switchWorkspace.next"

[[hotkeys]]
binding = "Unassigned"
id = "switchWorkspace.previous"

[[hotkeys]]
binding = "${3:-Option+Left Arrow}"
id = "focus.left"
TOML
    cp "$S" "$W/before.toml"
}
kw() { HOME="$H" XDG_CONFIG_HOME="$H/.config" KADOMO_STATE_DIR="$H/state" "$OW/bin/kadomo-omniwm" "$@"; }

echo "Setting the keys"
setup fresh
kw workspace-keys
check "next is on Ctrl+Option+Right" bound switchWorkspace.next "Control+Option+Right Arrow"
check "previous is on Ctrl+Option+Left" bound switchWorkspace.previous "Control+Option+Left Arrow"
check "other hotkeys stay" bound focus.left "Option+Left Arrow"
kw restore-workspace-keys
check "uninstalling leaves the file as it was" same "$S" "$W/before.toml"

echo "Your own choices"
setup assigned "Option+N"
kw workspace-keys
check "a hotkey you assigned stays" bound switchWorkspace.next "Option+N"
check "  and the other one is still set" bound switchWorkspace.previous "Control+Option+Left Arrow"
kw restore-workspace-keys
check "  uninstalling leaves yours alone" bound switchWorkspace.next "Option+N"

setup taken "" "Control+Option+Left Arrow"
kw workspace-keys
check "a key another hotkey uses is not taken" bound switchWorkspace.previous "Unassigned"

setup once
kw workspace-keys
sed -i '' 's/binding = "Control+Option+Right Arrow"/binding = "Unassigned"/' "$S"
kw workspace-keys
check "a key you took off stays off" bound switchWorkspace.next "Unassigned"

setup changed
kw workspace-keys
sed -i '' 's/binding = "Control+Option+Left Arrow"/binding = "Option+P"/' "$S"
kw restore-workspace-keys
check "uninstalling leaves a key you changed" bound switchWorkspace.previous "Option+P"
check "  and takes off the one you did not" bound switchWorkspace.next "Unassigned"

echo "No settings yet"
setup none
rm -f "$S"
check "nothing happens before OmniWM has written them" kw workspace-keys
check "  and it can still run later" test ! -e "$H/state/omniwm-workspace-keys.txt"

setup missing
printf 'schemaVersion = 4\n' >"$S"
kw workspace-keys 2>"$W/err"
check "a hotkey that is not there is reported" grep -q 'no switchWorkspace.next hotkey' "$W/err"
check "  and the file stays as it was" grep -qx 'schemaVersion = 4' "$S"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
((FAIL == 0))
