#!/usr/bin/env python3
"""Exercise signed feed/archive acceptance and tamper rejection; never export keys."""
from pathlib import Path
import argparse
import json
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TOOLS = Path('/private/tmp/Moon107Build/artifacts/sparkle/Sparkle/bin')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=ROOT/'Docs/Validation/update-signature-tests.json')
    args = parser.parse_args()
    folder = Path(tempfile.mkdtemp(prefix='MoonUpdateChecks.', dir='/private/tmp'))
    checks = {}
    def run(*command):
        result = subprocess.run(list(map(str, command)), capture_output=True, text=True)
        with (folder/'tool.log').open('a') as log:
            log.write(result.stdout + result.stderr)
        return result
    public = run(TOOLS/'generate_keys', '--account', 'org.moonbrowser.Moon', '-p')
    checks['public_key_matches_app'] = public.returncode == 0 and public.stdout.strip() == (ROOT/'Support/UpdatePublicKey.txt').read_text().strip()
    archive = folder/'fixture.zip'
    with zipfile.ZipFile(archive, 'w') as z:
        z.writestr('Moon fixture.txt', 'Harmless update signature fixture')
    signed = run(TOOLS/'sign_update', '--account', 'org.moonbrowser.Moon', '-p', archive)
    if signed.returncode:
        raise SystemExit(f'Signing unavailable; evidence: {folder}')
    signature = signed.stdout.strip()
    checks['valid_archive_accepted'] = run(TOOLS/'sign_update', '--account', 'org.moonbrowser.Moon', '--verify', archive, signature).returncode == 0
    archive.write_bytes(archive.read_bytes()+b'tampered')
    checks['tampered_archive_rejected'] = run(TOOLS/'sign_update', '--account', 'org.moonbrowser.Moon', '--verify', archive, signature).returncode != 0
    feed = folder/'appcast.xml'
    feed.write_text('<?xml version="1.0" encoding="utf-8"?><rss version="2.0"><channel><title>Moon local signature fixture</title></channel></rss>')
    checks['feed_signing_succeeds'] = run(TOOLS/'sign_update', '--account', 'org.moonbrowser.Moon', feed).returncode == 0
    checks['valid_feed_accepted'] = run(TOOLS/'sign_update', '--account', 'org.moonbrowser.Moon', '--verify', feed).returncode == 0
    original = feed.read_bytes()
    feed.write_bytes(original.replace(b'Moon local signature fixture',b'Attacker changed feed'))
    checks['tampered_feed_rejected'] = run(TOOLS/'sign_update', '--account', 'org.moonbrowser.Moon', '--verify', feed).returncode != 0
    feed.write_text('<?xml version="1.0"?><rss version="2.0"><channel><title>Unsigned feed</title></channel></rss>')
    checks['unsigned_feed_rejected'] = run(TOOLS/'sign_update', '--account', 'org.moonbrowser.Moon', '--verify', feed).returncode != 0
    report = {'passed': all(checks.values()), 'checks': checks, 'evidence_directory': str(folder), 'scope':'Pinned Sparkle verification tools and configured Moon public key; no installed-app upgrade or publication claimed'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report))
    raise SystemExit(0 if report['passed'] else 1)
if __name__=='__main__': main()
