#!/bin/zsh
# Builds Kadomo Menu, installs ~/Applications/KadomoMenu.app, and links the
# CLI at ~/.local/bin/kadomo-menu. Build products live outside the repo.
#
# Usage: ./build.sh             release build, install
#        ./build.sh --debug     debug build, install
#        ./build.sh --open      install, restart the running copy
#        ./build.sh --direct    build with swiftc (tools/dev-build.sh) instead of SwiftPM
#        ./build.sh --universal one binary for Apple silicon and Intel (implies --direct)
#        ./build.sh --package   also zip the app into dist/ and release/, and update install.sh's checksum
#                               (use with --universal; run it after any change that should ship)
#        PREFIX=/Applications ./build.sh   install somewhere else
set -euo pipefail
here=${0:A:h}
name="KadomoMenu"
version=$(grep -m1 'static let version' "$here/Sources/KadomoMenu/App/Launcher.swift" | sed -E 's/.*"(.*)".*/\1/')
config=release
[[ " $* " == *" --debug "* ]] && config=debug

if [[ " $* " == *" --universal "* ]]; then
  arm=$(ARCH=arm64 "$here/tools/dev-build.sh" $config | tail -1)
  intel=$(ARCH=x86_64 "$here/tools/dev-build.sh" $config | tail -1)
  bin="$here/.build/direct/$name-universal"
  lipo -create -output "$bin" "$arm" "$intel"
  echo "universal binary: $(lipo -archs "$bin")"
elif [[ " $* " == *" --direct "* ]]; then
  bin=$("$here/tools/dev-build.sh" $config | tail -1)
else
  scratch="${SCRATCH:-$HOME/Library/Developer/$name/build}"
  swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error|warning: |Compiling|Build complete" | grep -v "^\[" || true
  bin="$scratch/$config/$name"
  [[ -x "$bin" ]] || { echo "build failed"; exit 1; }
  # swift build can report success while an edited file failed to compile.
  stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
  if [[ -n "$stale" ]]; then
    echo "build failed: binary is older than $stale"
    swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error" | head -20
    exit 1
  fi
fi

# Sign with your Apple Development certificate when there is one, else ad hoc.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)
fi
[[ -n "$identity" ]] || identity=-

prefix="${PREFIX:-$HOME/Applications}"
app="$prefix/$name.app"
mkdir -p "$prefix"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" -e "s/__VERSION__/$version/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
xattr -cr "$app"
codesign --force --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
echo "installed $app (signed: $identity)"

mkdir -p "$HOME/.local/bin"
ln -sf "$app/Contents/MacOS/$name" "$HOME/.local/bin/kadomo-menu"
echo "linked $HOME/.local/bin/kadomo-menu"
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || echo "note: add ~/.local/bin to PATH in ~/.zshrc to run kadomo-menu"

if [[ " $* " == *" --package "* ]]; then
  mkdir -p "$here/dist"
  archs=$(lipo -archs "$app/Contents/MacOS/$name" | tr ' ' '-')
  zip="$here/dist/KadomoMenu-$version-$archs.zip"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  echo "packaged $zip"
  # install.sh ships release/, so refresh it and its checksum together or installs get the old build.
  mkdir -p "$here/release"
  rm -f "$here"/release/KadomoMenu-*.zip
  cp "$zip" "$here/release/"
  sum=$(shasum -a 256 "$zip" | cut -d' ' -f1)
  sed -i '' -e "s/^RELEASE_VERSION=.*/RELEASE_VERSION=\"$version\"/" -e "s/^RELEASE_SHA256=.*/RELEASE_SHA256=\"$sum\"/" "$here/install.sh"
  echo "updated release/ and install.sh ($sum)"
fi

if [[ " $* " == *" --open "* ]]; then
  "$HOME/.local/bin/kadomo-menu" quit 2>/dev/null || true
  sleep 0.5
  open "$app"
fi
