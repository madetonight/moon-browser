#!/usr/bin/env python3
"""Run Moon's native WebKit fixtures in a disposable, isolated profile."""
import argparse
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import plistlib
import ssl
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]

class Handler(http.server.BaseHTTPRequestHandler):
    agents = []
    def do_GET(self):
        self.agents.append(self.headers.get('User-Agent', ''))
        title = 'Moon clean fixture' if self.path.startswith('/clean') else 'Moon 1.0.7 fixture'
        body = f'<!doctype html><html><head><title>{title}</title><meta name="color-scheme" content="light dark"></head><body><h1 id="modern">Modern WebKit</h1><textarea id="draft"></textarea><iframe src="/frame"></iframe></body></html>'
        if self.path.startswith('/login'):
            body = '<!doctype html><title>Moon login fixture</title><form><input id="username" autocomplete="username"><input id="password" type="password" autocomplete="current-password"><button>Sign in</button></form>'
        if self.path.startswith('/frame'):
            body = '<!doctype html><textarea id="frame-draft"></textarea>'
        data = body.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *args):
        pass

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, default=ROOT / 'build/Moon.app')
    parser.add_argument('--sandbox-security', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT / 'Docs/Validation/search107-native.json')
    args = parser.parse_args()
    evidence = Path(tempfile.mkdtemp(prefix='MoonNativeSecurity.', dir='/private/tmp'))
    tls_server = None
    canary = None
    if args.sandbox_security:
        info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
        bundle_id = info['CFBundleIdentifier']
        if bundle_id == 'org.moonbrowser.Moon':
            raise SystemExit('Use a separately identified test app; never sandbox-test the normal profile.')
        env = dict(os.environ, MOON_PROBE='security-bootstrap')
        with (evidence / 'bootstrap.log').open('w') as log:
            bootstrap = subprocess.Popen([str(args.app / 'Contents/MacOS/Moon'), '-welcomed', 'YES'], env=env, stdout=log, stderr=log)
            time.sleep(3)
            if bootstrap.poll() is not None:
                raise SystemExit(f'Bootstrap failed; see {evidence}')
            bootstrap.terminate()
            bootstrap.wait(timeout=10)
        support = Path.home() / 'Library/Containers' / bundle_id / 'Data/Library/Application Support'
        folder = support / ('Moon security ' + uuid.uuid4().hex)
        folder.mkdir(parents=True)
        canary = evidence / 'outside-canary.txt'
        canary.write_text('untouched')
        cert, key = evidence / 'tls-cert.pem', evidence / 'tls-key.pem'
        subprocess.run(['/usr/bin/openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(key), '-out', str(cert), '-days', '1', '-subj', '/CN=localhost'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        tls_server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(str(cert), str(key))
        tls_server.socket = context.wrap_socket(tls_server.socket, server_side=True)
        threading.Thread(target=tls_server.serve_forever, daemon=True).start()
    else:
        folder = evidence
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    origin = f'http://127.0.0.1:{server.server_port}/'
    fixture_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab'
    extension = folder / 'Extensions' / fixture_id
    extension.mkdir(parents=True)
    (extension / 'manifest.json').write_text(json.dumps({
        'manifest_version': 3, 'name': 'Moon local MV3 fixture', 'version': '1.0',
        'permissions': ['storage', 'tabs'], 'host_permissions': ['http://127.0.0.1/*'],
        'background': {'service_worker': 'worker.js'},
        'content_scripts': [{'matches': ['http://127.0.0.1/*'], 'js': ['content.js']}]
    }))
    (extension / 'worker.js').write_text('''
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  (async () => {
    await chrome.storage.local.set({moonFixture: 'ready'});
    const stored = await chrome.storage.local.get('moonFixture');
    const tabs = await chrome.tabs.query({});
    reply({value: stored.moonFixture, tabs: tabs.length});
  })(); return true;
});
''')
    (extension / 'content.js').write_text('''
chrome.runtime.sendMessage({probe: true}).then(reply => {
  if(reply.value === 'ready' && reply.tabs > 0) document.documentElement.dataset.moonExtension = 'ready';
}).catch(() => {});
''')
    (folder / 'Extensions/installed.json').write_text(json.dumps([{
        'id': fixture_id, 'name': 'Moon local MV3 fixture', 'version': '1.0',
        'enabled': True, 'fromStore': False, 'permissions': ['storage', 'tabs', 'http://127.0.0.1/*']
    }]))
    env = dict(os.environ, MOON_TEST_DIRECTORY=str(folder), MOON_FIXTURE_ORIGIN=origin)
    if args.sandbox_security:
        env.update(MOON_SECURITY_FIXTURE='1', MOON_OUTSIDE_CANARY=str(canary), MOON_TLS_FIXTURE=f'https://127.0.0.1:{tls_server.server_port}/untrusted')
    with (folder / 'process.log').open('w') as log:
        process = subprocess.Popen([str(args.app / 'Contents/MacOS/Moon'), '--smoke-test'], env=env, stdout=log, stderr=log)
        try:
            process.wait(timeout=100)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=10)
    server.shutdown()
    if tls_server:
        tls_server.shutdown()
    report_file = folder / 'report.json'
    if not report_file.exists():
        raise SystemExit(f'No native report. Evidence retained at {folder}')
    report = json.loads(report_file.read_text())
    report['checks']['http_requests_send_safari_identity'] = any('Version/' in agent and 'Safari/605.1.15' in agent for agent in Handler.agents)
    if canary:
        report['checks']['outside_canary_unchanged'] = canary.read_text() == 'untouched'
        report['fixture_directory'] = str(evidence)
    report['passed'] = all(report['checks'].values())
    report['failures'] = [name for name, passed in report['checks'].items() if not passed]
    report['evidence_directory'] = str(folder)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'passed': report['passed'], 'checks': len(report['checks']), 'failures': report['failures'], 'evidence': str(folder)}))
    raise SystemExit(0 if report['passed'] else 1)

if __name__ == '__main__':
    main()
