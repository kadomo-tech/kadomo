#!/usr/bin/env bash
# Click on the theme name: switch to another theme, picked at random.
source "$CONFIG_DIR/colors.sh"

CURRENT="$(theme-current --name 2>/dev/null)"
NEXT="$(theme-list --names 2>/dev/null | grep -vxF -- "$CURRENT" | awk 'BEGIN { srand() } rand() * NR < 1 { pick = $0 } END { print pick }')"
[ -n "$NEXT" ] && theme-set "$NEXT"
