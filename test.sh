#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH=/private/tmp/Moon107Build/ModuleCache
export SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/Moon107Build/ModuleCache
MOON_PROBE="unit-$$" swift test -c release --scratch-path /private/tmp/Moon107Build --cache-path /private/tmp/Moon107Build/Cache --disable-sandbox
MOON_ASSEMBLE_ONLY=1 MOON_APP_NAME=MoonSecurityTest.app MOON_BUNDLE_ID=org.moonbrowser.Moon.SecurityTest ./build.sh release
python3 Scripts/test-native.py --app "$PWD/build/MoonSecurityTest.app" --sandbox-security --output "$PWD/Docs/Validation/sandbox-native.json"
