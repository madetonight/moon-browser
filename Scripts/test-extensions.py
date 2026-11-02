#!/usr/bin/env python3
"""Exercise Chrome APIs in Moon's native WebKit host using a disposable profile."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading


class Fixture(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/forbidden':
            self.server.forbidden_requests += 1
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', f'http://localhost:{self.server.server_port}/forbidden')
            self.end_headers()
            return
        if self.path == '/oversized':
            self.send_response(200)
            self.end_headers()  # Unknown size: Moon must enforce the received-byte limit.
            try:
                self.wfile.write(b'x' * 8192)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        page = b'<!doctype html><html><head><title>Moon Extension Fixture</title></head><body><h1>Controlled extension fixture</h1></body></html>'
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(page)))
        self.end_headers()
        self.wfile.write(page)

    def log_message(self, *args):
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--download-store-package', action='store_true', help='Download and verify the current public uBlock Origin Lite CRX without installing it.')
    parser.add_argument('--store-package', type=Path, help='Optional uBlock Origin Lite CRX3 to verify and unpack, without installing it.')
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    root = Path(tempfile.mkdtemp(prefix='MoonExtensionTest.', dir='/private/tmp'))
    server = ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    server.forbidden_requests = 0
    threading.Thread(target=server.serve_forever, daemon=True).start()
    environment = dict(os.environ, MOON_TEST_DIRECTORY=str(root), MOON_EXTENSION_FIXTURE_URL=f'http://127.0.0.1:{server.server_port}/fixture.html')
    if args.store_package:
        environment['MOON_TEST_CRX_PATH'] = str(args.store_package.resolve())
    if args.download_store_package:
        environment['MOON_TEST_CRX_PATH'] = 'download'
    try:
        with (root / 'process.log').open('wb') as log:
            subprocess.run([str(project / 'build/Moon.app/Contents/MacOS/Moon'), '--extension-test'], env=environment, stdout=log, stderr=log, timeout=90, check=True)
        report = json.loads((root / 'extensions.json').read_text())
        report['checks']['redirect_target_never_contacted'] = server.forbidden_requests == 0
        report['passed'] = report['passed'] and server.forbidden_requests == 0
        (root / 'extensions.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))
        print(f'Fixture logs: {root}')
        output = project / 'Docs/Validation/extensions.json'
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / 'extensions.json', output)
        if not report.get('passed'):
            raise SystemExit(1)
    finally:
        server.shutdown()


if __name__ == '__main__':
    main()
