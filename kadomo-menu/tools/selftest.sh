#!/bin/zsh
# In-process self-test of the real launcher on a throwaway config.
set -uo pipefail
here=${0:A:h:h}
bin=${1:-$here/.build/direct/debug/KadomoMenu}
tmp=${TMPDIR:-/tmp}/kadomo-menu-selftest
rm -rf "$tmp"; mkdir -p "$tmp/config/commands"
export KADOMO_MENU_CONFIG_DIR=$tmp/config KADOMO_MENU_STATE_DIR=$tmp/state KADOMO_MENU_SOCKET=$tmp/s.sock
# A stand-in for the theme manager's theme-set: it only writes down what it
# was asked, so the self-test never restyles this Mac.
printf '#!/bin/sh\nprintf "%%s|" "$@" >> "%s/theme-set.log"\necho >> "%s/theme-set.log"\n' "$tmp" "$tmp" > "$tmp/theme-set"
chmod +x "$tmp/theme-set"
export KADOMO_MENU_THEME_SET=${KADOMO_MENU_THEME_SET-$tmp/theme-set}
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
