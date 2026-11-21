#!/bin/bash
# Checks kadomo-omniwm's workspace keys and theme colors in a throwaway HOME. OmniWM is not
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

echo "The theme's colors"
# settings.toml and shell.toml as OmniWM writes them. $2 goes at the end of
# shell.toml: a text color set before Kadomo, or nothing.
colors_setup() {
    W="$WORK/$1"; H="$W/home"; S="$H/.config/omniwm/settings.toml"; SH="$H/.config/omniwm/shell/shell.toml"
    rm -rf -- "$W"; mkdir -p "$H/.config/omniwm/shell" "$H/kadomo/current/theme"
    cat >"$S" <<TOML
schemaVersion = 5

[borders]
enabled = true
width = 2.0

[borders.color]
alpha = 1.0
blue = 0.1
green = 0.1
red = 0.1

[workspaceBar]
height = 24.0
TOML
    cat >"$SH" <<TOML
[profiles]

[profiles.default]
leading = ["workspaces"]

[profiles.default.workspaceBar]
fullWidth = true
TOML
    [[ -z "$2" ]] || printf '%s\n' "$2" >>"$SH"
    cp "$S" "$W/settings-before.toml"; cp "$SH" "$W/shell-before.toml"
    cat >"$H/kadomo/current/theme/omniwm.toml" <<TOML
# A theme.
[borders.color]
alpha = 1.0000
blue = 0.9000
green = 0.9000
red = 0.9000

[workspaceBar.textColor]
alpha = 1.0000
blue = 0.6784
green = 0.8078
red = 1.0000
TOML
}
kc() { KADOMO_CONFIG_DIR="$H/kadomo" kw "$@"; }
in_table() { # <file> <table> <line>: the line is in that table
    awk -v t="[$2]" '$0 == t { on = 1; next } /^\[/ { on = 0 } on' "$1" | grep -qxF "$3"
}
TEXT=profiles.default.workspaceBar.textColor

colors_setup fresh ""
kc theme
check "the bar text gets the theme's color" in_table "$SH" "$TEXT" "red = 1.0000"
check "  in the default shell profile only" bash -c "! grep -q textColor '$S'"
check "  and the border still gets its color" in_table "$S" borders.color "red = 0.9000"
check "  and the profile's other settings stay" in_table "$SH" profiles.default.workspaceBar "fullWidth = true"
kc theme
check "a second switch keeps one text color" test "$(grep -c "^\[$TEXT\]$" "$SH")" = 1
kc restore-borders
check "uninstalling turns Custom Text Color off again" same "$SH" "$W/shell-before.toml"
check "  and puts the border back" same "$S" "$W/settings-before.toml"

colors_setup yours $'\n[profiles.default.workspaceBar.textColor]\nalpha = 1.0\nblue = 1.0\ngreen = 0.2\nred = 0.1'
kc theme
check "a text color you set gives way to the theme's" in_table "$SH" "$TEXT" "green = 0.8078"
kc restore-borders
check "  and comes back on uninstall" in_table "$SH" "$TEXT" "green = 0.2"
check "  as the only one" test "$(grep -c "^\[$TEXT\]$" "$SH")" = 1

colors_setup noshell ""
rm -f "$SH"
check "no shell.toml yet: the border still changes" kc theme
check "  and none is made" test ! -e "$SH"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
((FAIL == 0))
