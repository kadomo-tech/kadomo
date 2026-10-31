#!/bin/zsh
# In-process self-test of the real launcher on a throwaway config.
set -uo pipefail
here=${0:A:h:h}
bin=${1:-$here/.build/direct/debug/KadomoMenu}
tmp=${TMPDIR:-/tmp}/kadomo-menu-selftest
rm -rf "$tmp"; mkdir -p "$tmp/config/commands"
export KADOMO_MENU_CONFIG_DIR=$tmp/config KADOMO_MENU_STATE_DIR=$tmp/state KADOMO_MENU_SOCKET=$tmp/s.sock
printf 'launch_at_login = false\n[aliases]\nzz = "sys:sleep"\n' > "$tmp/config/config.toml"
cat > "$tmp/config/commands/test.toml" <<TOML
[[command]]
id = "touch"
title = "Touch Marker"
exec = "/usr/bin/touch"
args = ["$tmp/marker"]

[[command]]
id = "fails"
title = "Always Fails"
shell = "echo nope >&2; exit 3"
TOML
KADOMO_MENU_GUI=1 KADOMO_MENU_SELFTEST=1 "$bin"
