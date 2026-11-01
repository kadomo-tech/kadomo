#!/bin/zsh
# Checks the Omarchy adapter against what upstream publishes today: every
# official theme's colors.toml and shell.toml at the default branch, and the
# community catalog. Downloads with curl into a throwaway folder, then runs the
# LiveUpstream tests on it. Run it after Omarchy releases, or when a theme
# fails to install.
#   tools/omarchy-compat.sh [folder]
set -euo pipefail
here=${0:A:h:h}
dir=${1:-${TMPDIR:-/tmp}/omarchy-upstream}
rm -rf "$dir"; mkdir -p "$dir/official"
api=https://api.github.com/repos/omacom/omarchy
branch=$(curl -fsS "$api" | /usr/bin/python3 -I -c 'import json,sys; print(json.load(sys.stdin)["default_branch"])')
sha=$(curl -fsS "$api/commits/$branch" | /usr/bin/python3 -I -c 'import json,sys; print(json.load(sys.stdin)["sha"])')
names=$(curl -fsS "$api/contents/themes?ref=$sha" | /usr/bin/python3 -I -c 'import json,sys; print("\n".join(e["name"] for e in json.load(sys.stdin) if e["type"]=="dir"))')
echo "omarchy $branch @ ${sha:0:7}: $(echo $names | wc -l | tr -d ' ') themes"
for name in ${(f)names}; do
  [[ $name =~ '^[a-z0-9_][a-z0-9._+-]*$' ]] || continue
  mkdir -p "$dir/official/$name"
  for file in colors.toml shell.toml light.mode; do
    curl -fsS "https://raw.githubusercontent.com/omacom/omarchy/$sha/themes/$name/$file" -o "$dir/official/$name/$file" 2>/dev/null || true
  done
done
curl -fsS https://omarchytheme.com/api/v1/themes.json -o "$dir/community.json" || echo "community catalog unavailable"
"$here/tools/dev-build.sh" test >/dev/null 2>&1 || true
OMARCHY_FIXTURES=$dir "$here/.build/direct/test/KadomoOmarchyTests" --filter LiveUpstream
