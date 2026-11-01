#!/bin/zsh
# End-to-end check of the CLI against a headless copy of the app, using a
# throwaway config. Prints PASS or the first failing step.
#   tools/check-cli.sh [path/to/KadomoMenu]
set -uo pipefail
here=${0:A:h:h}
bin=${1:-$here/.build/direct/debug/KadomoMenu}
tmp=${TMPDIR:-/tmp}/kadomo-menu-cli
rm -rf "$tmp"; mkdir -p "$tmp/config/commands"
export KADOMO_MENU_THEME_SET= KADOMO_MENU_CONFIG_DIR=$tmp/config KADOMO_MENU_STATE_DIR=$tmp/state KADOMO_MENU_SOCKET=$tmp/s.sock
cat > "$tmp/config/config.toml" <<'EOF'
launch_at_login = false
[aliases]
zz = "sys:sleep"
EOF
cat > "$tmp/config/commands/test.toml" <<'EOF'
[[command]]
id = "touch"
title = "Touch Marker"
exec = "/usr/bin/touch"
args = ["MARKER"]

[[command]]
id = "fails"
title = "Always Fails"
shell = "echo nope >&2; exit 3"
EOF
sed -i '' "s#MARKER#$tmp/marker#" "$tmp/config/commands/test.toml"

KADOMO_MENU_GUI=1 KADOMO_MENU_HEADLESS=1 "$bin" >"$tmp/app.log" 2>&1 &
app=$!
trap 'kill $app 2>/dev/null' EXIT
for _ in {1..50}; do [[ -S $tmp/s.sock ]] && break; sleep 0.1; done
cli() { "$bin" "$@"; }
fail() { echo "FAIL: $1"; exit 1; }

cli status | grep -q "Kadomo Menu" || fail "status"
cli theme list | grep -q "kadomo-terminal" || fail "theme list"
cli theme set kadomo-terminal >/dev/null || fail "theme set"
[[ $(cli theme current) == kadomo-terminal ]] || fail "theme current"
grep -q 'theme = "kadomo-terminal"' "$tmp/config/config.toml" || fail "theme persisted to config.toml"
cli theme set nope >/dev/null 2>&1 && fail "unknown theme should fail"
cli commands list | grep -q "cmd:touch" || fail "user command listed"
cli commands list --json | grep -q '"id" : "sys:sleep"' || fail "json list"
cli commands run cmd:touch || fail "run exec command"
for _ in {1..20}; do [[ -f $tmp/marker ]] && break; sleep 0.1; done
[[ -f $tmp/marker ]] || fail "exec command ran"
out=$(cli commands run cmd:fails 2>&1); [[ $? -ne 0 && $out == *"status 3"*"nope"* ]] || fail "failure reported: $out"
cli commands run sys:nope >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "unknown id exits 2"

# Hot reload: a new command file appears without a restart.
printf '[[command]]\nid = "late"\ntitle = "Added Later"\nurl = "https://example.com"\n' > "$tmp/config/commands/late.toml"
cli reload >/dev/null
cli commands list | grep -q "cmd:late" || fail "reload picks up new command"

# A broken config keeps the last good one and reports the error.
echo 'theme = ' >> "$tmp/config/config.toml"
cli reload >/dev/null 2>&1; [[ $? -eq 1 ]] || fail "broken config reload exits 1"
[[ $(cli theme current) == kadomo-terminal ]] || fail "kept previous config"
cli config check >/dev/null 2>&1; [[ $? -eq 1 ]] || fail "config check fails on broken config"

cli bogus >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "unknown command exits 2"
echo "PASS agent CLI"
