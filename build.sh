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
configuration="${1:-debug}"
[[ "$configuration" == debug || "$configuration" == release ]] || { print -u2 "Usage: ./build.sh [debug|release]"; exit 2; }
app_name="${MOON_APP_NAME:-Moon.app}"
bundle_id="${MOON_BUNDLE_ID:-org.moonbrowser.Moon}"
[[ "$app_name" == *.app && "$app_name" != */* ]] || { print -u2 "Invalid app name"; exit 2; }
python3 -c 'import re,sys; sys.exit(0 if re.fullmatch(r"[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*",sys.argv[1]) else 2)' "$bundle_id"
# Never invoke a private signing key just because someone builds or tests.
[[ "${MOON_ALLOW_SIGNING:-0}" == 1 ]] || {
  print -u2 "Signing is paused. The existing app is unchanged. When you are ready to authorize signing, run MOON_ALLOW_SIGNING=1 ./build.sh $configuration."
  exit 2
}
if [[ "${MOON_ASSEMBLE_ONLY:-0}" != 1 ]]; then
  swift build -c "$configuration" --scratch-path "$scratch" --cache-path "$scratch/Cache" --disable-sandbox
fi
binary_dir="$(swift build -c "$configuration" --scratch-path "$scratch" --show-bin-path --disable-sandbox)"
framework_source="$scratch/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$framework_source" ]] || { print -u2 "Pinned Sparkle framework is missing"; exit 1; }
mkdir -p "$PWD/build"
final_app="$PWD/build/$app_name"
staging="$(mktemp -d "$PWD/build/.Moon-build.XXXXXX")"
app="$staging/$app_name"
entitlements=""
previous=""
cleanup() {
  if [[ -n "$previous" && -d "$previous" && ! -e "$final_app" ]]; then mv "$previous" "$final_app"; fi
  [[ -z "$entitlements" ]] || rm -f "$entitlements"
  rm -rf "$staging"
}
trap cleanup EXIT
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binary_dir/Moon" "$app/Contents/MacOS/Moon"
strip -u -r "$app/Contents/MacOS/Moon"
for resource in Search-1.0.7-LICENSE Sparkle-LICENSE Moon.sdef; do cp "Support/$resource" "$app/Contents/Resources/$resource"; done
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
# Sparkle removes quarantine after extraction. A read-only copied license
# prevents that operation even when the app and archive signatures are valid.
chmod 644 "$app/Contents/Resources/"{Search-1.0.7-LICENSE,Sparkle-LICENSE,Moon.sdef,LICENSE,THIRD_PARTY_NOTICES.md}
cp Support/Info.plist "$app/Contents/Info.plist"
if [[ "$bundle_id" == org.moonbrowser.Moon ]]; then
  cp Support/container-migration.plist "$app/Contents/Resources/container-migration.plist"
else
  rm -f "$app/Contents/Resources/container-migration.plist"
fi
if [[ ! -f build/Moon.icns || Support/MakeIcon.swift -nt build/Moon.icns || Support/MoonIconArtwork.png -nt build/Moon.icns || Scripts/optimize-icon.swift -nt build/Moon.icns ]]; then
  swift Support/MakeIcon.swift "$scratch/Moon.iconset"
  iconutil -c icns "$scratch/Moon.iconset" -o build/Moon.icns
  swift Scripts/optimize-icon.swift build/Moon.icns
fi
cp build/Moon.icns "$app/Contents/Resources/Moon.icns"
ditto "$framework_source" "$app/Contents/Frameworks/Sparkle.framework"
entitlements="$(mktemp /private/tmp/Moon-entitlements.XXXXXX)"

python3 - "$app" "$bundle_id" "$entitlements" <<'PY'
from pathlib import Path
import base64,os,plistlib,sys
app,bundle_id,entitlements=sys.argv[1:]
p=Path(app)/'Contents/Info.plist';info=plistlib.loads(p.read_bytes())
info['CFBundleIdentifier']=bundle_id
public_key=Path('Support/UpdatePublicKey.txt').read_text().strip()
assert len(base64.b64decode(public_key,validate=True))==32, 'Invalid update public key'
info['SUPublicEDKey']=public_key
info['MoonUpdateFeedReady']=os.environ.get('MOON_UPDATE_FEED_READY')=='1'
if os.environ.get('MOON_RELEASE_TEAM'):info['MoonReleaseTeam']=os.environ['MOON_RELEASE_TEAM']
p.write_bytes(plistlib.dumps(info,sort_keys=False))
e=plistlib.loads(Path('Support/Moon.entitlements').read_bytes())
e['com.apple.security.temporary-exception.mach-lookup.global-name']=[bundle_id+'-spks',bundle_id+'-spki']
Path(entitlements).write_bytes(plistlib.dumps(e))
PY
identity="${MOON_SIGNING_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(python3 - <<'PYIDENTITY'
import re,subprocess
text=subprocess.check_output(['/usr/bin/security','find-identity','-v','-p','codesigning'],text=True)
for line in text.splitlines():
 m=re.search(r'([A-F0-9]{40}) "Apple Development:',line)
 if m:
  print(m.group(1));break
PYIDENTITY
)"
fi
[[ -n "$identity" && "$identity" != - ]] || { print -u2 "A code-signing identity is required for embedded Sparkle with library validation. Add an Apple Development identity in Xcode for local builds, or set MOON_SIGNING_IDENTITY for distribution."; exit 1; }
sign_args=(--force --sign "$identity" --options runtime)
if [[ "$identity" != - ]]; then sign_args+=(--timestamp); fi
framework="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
# Cache only identical dependency bytes signed by the same certificate.
# Verification and certificate extraction never request private-key access.
framework_key="$(python3 Scripts/signing-cache-key.py "$framework_source" "$identity")"
framework_cache="$PWD/build/.signed-frameworks/$framework_key/Sparkle.framework"
reuse_framework=0
if [[ "$identity" =~ '^[A-Fa-f0-9]{40}$' && -d "$framework_cache" ]] \
    && codesign --verify --deep --strict "$framework_cache" \
    && codesign --display --extract-certificates="$staging/cache-cert-" "$framework_cache"; then
  cached_identity="$(shasum -a 1 "$staging/cache-cert-0" | cut -d ' ' -f 1)"
  if [[ "${(U)cached_identity}" == "${(U)identity}" ]]; then reuse_framework=1; fi
fi
if [[ "$reuse_framework" == 1 ]]; then
  rm -rf "$app/Contents/Frameworks/Sparkle.framework"
  ditto "$framework_cache" "$app/Contents/Frameworks/Sparkle.framework"
else
  [[ "${MOON_REQUIRE_SIGNED_HELPER_CACHE:-0}" != 1 ]] || {
    print -u2 "The verified helper cache is unavailable. Stopping before private-key access; no helper will be signed repeatedly."
    exit 2
  }
  # Sign from the innermost helper outward. Never use --deep for signing.
  codesign "${sign_args[@]}" "$framework/XPCServices/Installer.xpc"
  codesign "${sign_args[@]}" --preserve-metadata=entitlements "$framework/XPCServices/Downloader.xpc"
  codesign "${sign_args[@]}" "$framework/Autoupdate"
  codesign "${sign_args[@]}" "$framework/Updater.app"
  codesign "${sign_args[@]}" "$app/Contents/Frameworks/Sparkle.framework"
  codesign --verify --deep --strict "$app/Contents/Frameworks/Sparkle.framework"
  if [[ "$identity" =~ '^[A-Fa-f0-9]{40}$' ]]; then
    mkdir -p "${framework_cache:h}"
    rm -rf "$framework_cache"
    ditto "$app/Contents/Frameworks/Sparkle.framework" "$framework_cache"
  fi
fi
# The app is arm64. Thin cached, already signed helpers without invoking a
# private key: Mach-O slices retain their own signatures. Verify before signing
# the outer bundle so an SDK/toolchain change cannot silently invalidate them.
python3 - "$app/Contents/Frameworks/Sparkle.framework" <<'PY'
from pathlib import Path
import subprocess,sys
for binary in Path(sys.argv[1]).rglob('*'):
    if not binary.is_file() or binary.is_symlink(): continue
    info=subprocess.run(['lipo','-info',str(binary)],capture_output=True,text=True)
    if info.returncode == 0 and 'x86_64' in info.stdout:
        output=Path(str(binary)+'.thin')
        subprocess.run(['lipo',str(binary),'-thin','arm64','-output',str(output)],check=True)
        output.chmod(binary.stat().st_mode)
        output.replace(binary)
PY
# The optional local Codex launcher is signed separately and starts on demand.
helper="$app/Contents/Helpers/MoonCodexBridge.app"
mkdir -p "$helper/Contents/MacOS"
cp "$binary_dir/MoonCodexBridge" "$helper/Contents/MacOS/MoonCodexBridge"
strip -u -r "$helper/Contents/MacOS/MoonCodexBridge"
python3 - "$helper" "$bundle_id" <<'PYCHELPER'
from pathlib import Path
import plistlib,sys
folder=Path(sys.argv[1]);owner=sys.argv[2]
(folder/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':owner+'.CodexBridge','CFBundleExecutable':'MoonCodexBridge','CFBundleName':'Moon Codex Engine','CFBundlePackageType':'APPL','CFBundleVersion':'1','LSUIElement':True,'CFBundleDocumentTypes':[{'CFBundleTypeName':'Moon connection folder','CFBundleTypeRole':'Editor','LSHandlerRank':'None','LSItemContentTypes':['public.folder']}],'MoonOwnerBundleID':owner}))
PYCHELPER
helper_key="$(python3 - "$helper" "$identity" <<'PYCHASH'
from pathlib import Path
import hashlib,sys
p=Path(sys.argv[1]);h=hashlib.sha256(sys.argv[2].encode())
for name in ['Contents/Info.plist','Contents/MacOS/MoonCodexBridge']:h.update((p/name).read_bytes())
print(h.hexdigest())
PYCHASH
)"
helper_cache="$PWD/build/.signed-codex-bridges/$helper_key/MoonCodexBridge.app"
if [[ -d "$helper_cache" ]] && codesign --verify --deep --strict "$helper_cache"; then
  rm -rf "$helper"
  ditto "$helper_cache" "$helper"
else
  codesign "${sign_args[@]}" "$helper"
  codesign --verify --deep --strict "$helper"
  mkdir -p "${helper_cache:h}"
  ditto "$helper" "$helper_cache"
fi
codesign --verify --deep --strict "$app/Contents/Frameworks/Sparkle.framework"
codesign "${sign_args[@]}" --entitlements "$entitlements" "$app"
codesign --verify --deep --strict "$app"
if [[ -e "$final_app" ]]; then
  previous="$staging/previous.app"
  mv "$final_app" "$previous"
fi
mv "$app" "$final_app"
print "Built $final_app"
