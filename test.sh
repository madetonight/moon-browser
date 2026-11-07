#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
scratch="$PWD/.build"
[[ ! -L "$scratch" && ( ! -e "$scratch" || -O "$scratch" ) ]] || {
  print -u2 "The SwiftPM build directory must be owned by you and cannot be a symbolic link."
  exit 2
}
export CLANG_MODULE_CACHE_PATH="$scratch/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$scratch/ModuleCache"
MOON_PROBE="unit-$$" swift test -c release --scratch-path "$scratch" --cache-path "$scratch/Cache" --disable-sandbox
MOON_ASSEMBLE_ONLY=1 MOON_APP_NAME=MoonSecurityTest.app MOON_BUNDLE_ID=org.moonbrowser.Moon.SecurityTest ./build.sh release
python3 Scripts/test-native.py --app "$PWD/build/MoonSecurityTest.app" --sandbox-security --output "$PWD/Docs/Validation/sandbox-native.json"
