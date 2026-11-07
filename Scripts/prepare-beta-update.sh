#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
python3 Scripts/check-release-notes.py

mode="${1:-}"
[[ -z "$mode" || "$mode" == --plan ]] || { printf '%s\n' 'Usage: prepare-beta-update.sh [--plan]' >&2; exit 2; }
plan="$(python3 - <<'PY'
from pathlib import Path
import json,os,plistlib,re,sys
from urllib.parse import urlsplit
i=plistlib.loads(Path('Support/Info.plist').read_bytes())
version=i['CFBundleShortVersionString']; build=i['CFBundleVersion']
if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}',version) or not re.fullmatch(r'[0-9]+',build):
    raise SystemExit('Invalid release version/build')
prefix=os.environ.get('MOON_DOWNLOAD_URL_PREFIX',f'https://github.com/madetonight/moon-browser/releases/download/v{version}-beta/')
u=urlsplit(prefix)
if u.scheme!='https' or not u.hostname or u.username is not None or u.password is not None or u.query or u.fragment or not prefix.endswith('/'):
    raise SystemExit('Use a public HTTPS download directory ending in /, without credentials, query or fragment')
print(json.dumps({'channel':'beta','version':version,'build':build,'archive':f'Moon-{version}-arm64.dmg','download_prefix':prefix,'feed':i['SUFeedURL'],'candidate':'build/MoonReleaseCandidate.app','normal_app_untouched':True,'notarization_required':False,'signed_feed_required':True}))
PY
)"
if [[ "$mode" == --plan ]]; then printf '%s\n' "$plan"; exit 0; fi
[[ "${MOON_ALLOW_SIGNING:-0}" == 1 ]] || { printf '%s\n' 'Beta preparation is paused. Review --plan, then explicitly allow signing with MOON_ALLOW_SIGNING=1. The normal app is unchanged.' >&2; exit 2; }
version="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["version"])' "$plan")"
prefix="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["download_prefix"])' "$plan")"
sparkle="$PWD/.build/artifacts/sparkle/Sparkle/bin"

# Uses the same installed development certificate as local builds. The existing
# signed helper cache avoids repeated developer-key signing for Sparkle helpers.
MOON_REQUIRE_SIGNED_HELPER_CACHE=1 MOON_APP_NAME=MoonReleaseCandidate.app MOON_UPDATE_FEED_READY=1 ./build.sh release
candidate="$PWD/build/MoonReleaseCandidate.app"
codesign --verify --deep --strict "$candidate"
public_key="$("$sparkle/generate_keys" --account org.moonbrowser.Moon -p)"
[[ "$public_key" == "$(cat Support/UpdatePublicKey.txt)" ]] || { printf '%s\n' 'The update key does not match Moon.' >&2; exit 1; }

release_dir="$(mktemp -d "$PWD/dist-release.XXXXXX")"
trap 'printf "Beta evidence retained at %s\n" "$release_dir"' EXIT
# The one DMG serves both manual installation and Sparkle updates.
archive="$release_dir/Moon-$version-arm64.dmg"
disk_root="$(mktemp -d /private/tmp/Moon-dmg.XXXXXX)"
cleanup() {
  rm -rf "$disk_root"
  printf 'Beta evidence retained at %s\n' "$release_dir"
}
trap cleanup EXIT
ditto "$candidate" "$disk_root/Moon.app"
ln -s /Applications "$disk_root/Applications"
cp Support/Beta-Install-ReadMe.txt "$disk_root/Read Me.txt"
hdiutil create -volname "Moon $version" -srcfolder "$disk_root" -format UDZO \
  -imagekey zlib-level=9 "$release_dir/Moon-$version-arm64.dmg"
hdiutil verify "$release_dir/Moon-$version-arm64.dmg"
cp Support/Beta-Release-Notes.md "$release_dir/Moon-$version-arm64.md"
"$sparkle/generate_appcast" --account org.moonbrowser.Moon \
  --download-url-prefix "$prefix" --maximum-deltas 0 --maximum-versions 1 \
  --embed-release-notes --link "https://github.com/madetonight/moon-browser/releases/tag/v$version-beta" "$release_dir"
"$sparkle/sign_update" --account org.moonbrowser.Moon --verify "$release_dir/appcast.xml"
xcrun swift Scripts/verify-update.swift "$archive" "$release_dir/appcast.xml" "$candidate/Contents/Info.plist" "$prefix"
python3 - "$release_dir" "$plan" <<'PY'
from pathlib import Path
import hashlib,json,sys
folder=Path(sys.argv[1]); plan=json.loads(sys.argv[2])
names=[plan['archive'],'appcast.xml']
checksums={name:hashlib.sha256((folder/name).read_bytes()).hexdigest() for name in names}
(folder/'SHA256SUMS.txt').write_text(''.join(f'{digest}  {name}\n' for name,digest in checksums.items()))
plan['checksums']=checksums;plan['published']=False
(folder/'release-plan.json').write_text(json.dumps(plan,indent=2)+'\n')
PY
printf '%s\n' 'Verified beta prepared locally; nothing was uploaded. Publish the one DMG installer, then the signed appcast in the repository. Source remains in GitHub. Bootstrap the connected candidate manually, then test a real later in-app upgrade.'
