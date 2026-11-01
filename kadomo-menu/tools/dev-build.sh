#!/bin/zsh
# Builds with swiftc directly, without SwiftPM. Useful in sandboxes that block
# SwiftPM's temporary files, and a quick way to run the tests.
#
#   tools/dev-build.sh            debug app binary  -> .build/direct/KadomoMenu
#   tools/dev-build.sh release    optimized binary
#   tools/dev-build.sh test       build and run the Swift Testing suite
#   ARCH=x86_64 tools/dev-build.sh release   cross-compile for Intel Macs
#   KADOMO_OMARCHY=0 tools/dev-build.sh       build without the Omarchy integration
set -euo pipefail
here=${0:A:h:h}
cd "$here"
mode=${1:-debug}
arch=${ARCH:-$(uname -m)}
out="$here/.build/direct/$mode"
[[ $arch != $(uname -m) ]] && out="$out-$arch"
mkdir -p "$out"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/kadomo-menu-mc"

sdk=$(xcrun --show-sdk-path 2>/dev/null)
dev=$(xcode-select -p)
target="$arch-apple-macos14.0"
common=(-sdk "$sdk" -target "$target" -swift-version 6 -module-cache-path "$CLANG_MODULE_CACHE_PATH")
if [[ $mode == release ]]; then opt=(-O -wmo); else opt=(-Onone -g -enable-testing); fi

swiftc "${common[@]}" "${opt[@]}" -parse-as-library -module-name KadomoMenuCore \
  -emit-library -static -emit-module -emit-module-path "$out/KadomoMenuCore.swiftmodule" \
  -o "$out/libKadomoMenuCore.a" Sources/KadomoMenuCore/*.swift

# The optional Omarchy integration. Without it the app compiles its
# `#if canImport(KadomoOmarchy)` code out and offers Kadomo's themes only.
omarchy=()
rm -f "$out/KadomoOmarchy.swiftmodule" "$out/libKadomoOmarchy.a"
if [[ ${KADOMO_OMARCHY:-1} != 0 ]]; then
  swiftc "${common[@]}" "${opt[@]}" -parse-as-library -module-name KadomoOmarchy -I "$out" \
    -emit-library -static -emit-module -emit-module-path "$out/KadomoOmarchy.swiftmodule" \
    -o "$out/libKadomoOmarchy.a" Sources/KadomoOmarchy/*.swift
  omarchy=(-lKadomoOmarchy)
fi

if [[ $mode == test ]]; then
  frameworks="$dev/Platforms/MacOSX.platform/Developer/Library/Frameworks"
  plugins="$dev/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing"
  cat > "$out/Runner.swift" <<'EOF'
@_spi(ForToolsIntegrationOnly) import Testing
@main struct Runner {
    static func main() async {
        let status = await Testing.__swiftPMEntryPoint() as CInt
        exit(status)
    }
}
import Foundation
EOF
  swiftc "${common[@]}" -Onone -g -module-name KadomoMenuCoreTests -I "$out" -L "$out" -lKadomoMenuCore \
    -F "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" -plugin-path "$plugins" \
    -Xlinker -rpath -Xlinker "$dev/Platforms/MacOSX.platform/Developer/usr/lib" -L "$dev/Platforms/MacOSX.platform/Developer/usr/lib" \
    -o "$out/KadomoMenuCoreTests" Tests/KadomoMenuCoreTests/*.swift "$out/Runner.swift"
  rc=0
  "$out/KadomoMenuCoreTests" "${@:2}" || rc=$?
  if (( ${#omarchy} )); then
    swiftc "${common[@]}" -Onone -g -module-name KadomoOmarchyTests -I "$out" -L "$out" -lKadomoOmarchy -lKadomoMenuCore \
      -F "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" -plugin-path "$plugins" \
      -Xlinker -rpath -Xlinker "$dev/Platforms/MacOSX.platform/Developer/usr/lib" -L "$dev/Platforms/MacOSX.platform/Developer/usr/lib" \
      -o "$out/KadomoOmarchyTests" Tests/KadomoOmarchyTests/*.swift "$out/Runner.swift"
    "$out/KadomoOmarchyTests" "${@:2}" || rc=$?
  fi
  exit $rc
fi

swiftc "${common[@]}" "${opt[@]}" -module-name KadomoMenu -default-isolation MainActor -I "$out" -L "$out" "${omarchy[@]}" -lKadomoMenuCore \
  -framework Carbon -o "$out/KadomoMenu" Sources/KadomoMenu/**/*.swift
echo "$out/KadomoMenu"
