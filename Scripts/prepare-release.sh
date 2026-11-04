#!/bin/bash
set -Eeuo pipefail
python3 "$(dirname "$0")/check-release-notes.py"
[[ "${MOON_ALLOW_SIGNING:-0}" == 1 ]] || { printf '%s\n' 'Release signing is paused. Set MOON_ALLOW_SIGNING=1 only when ready to authorize private-key access.' >&2; exit 2; }
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${MOON_SIGNING_IDENTITY:?Set a Developer ID Application signing identity}"
: "${MOON_RELEASE_TEAM:?Set the ten-character Apple Developer team ID}"
: "${MOON_NOTARY_PROFILE:?Set an existing notarytool Keychain profile}"
: "${MOON_DOWNLOAD_URL_PREFIX:?Set the intended HTTPS release download directory}"
[[ "$MOON_SIGNING_IDENTITY" == 'Developer ID Application: '* ]] || { printf '%s\n' 'Public releases require Developer ID Application signing.' >&2; exit 2; }
python3 - "$MOON_RELEASE_TEAM" "$MOON_DOWNLOAD_URL_PREFIX" <<'PY'
import re,sys
from urllib.parse import urlsplit
assert re.fullmatch(r'[A-Z0-9]{10}',sys.argv[1]), 'Invalid team ID'
u=urlsplit(sys.argv[2]);assert u.scheme=='https' and u.hostname and not u.username and not u.password and not u.query and not u.fragment, 'Use an HTTPS download directory without credentials/query/fragment'
PY
sparkle=/private/tmp/Moon107Build/artifacts/sparkle/Sparkle/bin
# Building resolves the pinned dependency. This flag marks a release candidate,
# not proof that its feed/archive has been published.
MOON_UPDATE_FEED_READY=1 ./build.sh release
public_key="$("$sparkle/generate_keys" --account org.moonbrowser.Moon -p)"
[[ "$public_key" == "$(cat Support/UpdatePublicKey.txt)" ]] || { printf '%s\n' 'Update key does not match the bundled public key.' >&2; exit 1; }
release_dir="$(mktemp -d "$PWD/dist-release.XXXXXX")"
trap 'printf "Release evidence retained at %s\n" "$release_dir"' EXIT
archive="$release_dir/Moon.zip"
ditto -c -k --sequesterRsrc --keepParent build/Moon.app "$release_dir/notarize.zip"
xcrun notarytool submit "$release_dir/notarize.zip" --keychain-profile "$MOON_NOTARY_PROFILE" --wait
xcrun stapler staple build/Moon.app
xcrun stapler validate build/Moon.app
codesign --verify --deep --strict build/Moon.app
spctl --assess --type execute --verbose=2 build/Moon.app
rm "$release_dir/notarize.zip"
ditto -c -k --sequesterRsrc --keepParent build/Moon.app "$archive"
"$sparkle/generate_appcast" --account org.moonbrowser.Moon --download-url-prefix "${MOON_DOWNLOAD_URL_PREFIX%/}/" --maximum-deltas 0 "$release_dir"
"$sparkle/sign_update" --account org.moonbrowser.Moon --verify "$release_dir/appcast.xml"
shasum -a 256 "$archive" > "$release_dir/SHA256.txt"
printf '%s\n' 'Signed, notarized release candidate prepared locally. Review and publish Moon.zip and appcast.xml together, then test an installed old-to-new upgrade. This script does not publish.'
