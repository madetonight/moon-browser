#!/usr/bin/env python3
"""Measure actual Navigation/Paint Timing and full-resolution media in an isolated Moon profile.

Local fixtures isolate browser overhead from internet/server variability. These
numbers are not claims about every website or DRM service. No user tabs or data
are accessed. Requires ffmpeg for the generated 4K image/video fixtures.
"""
import argparse
import glob
import http.server
import json
import os
from pathlib import Path
import socket
import statistics
import subprocess
import tempfile
import threading
import time
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True)
parser.add_argument('--output', required=True)
parser.add_argument('--label', default='baseline')
parser.add_argument('--media-seconds', type=float, default=5)
args = parser.parse_args()
fixture = Path('/private/tmp/MoonNavigationMedia')
fixture.mkdir(exist_ok=True)
for name, options in [
    ('image.png', ['-f', 'lavfi', '-i', 'testsrc2=size=3840x2160:rate=1', '-frames:v', '1', '-threads', '2']),
    ('video.mp4', ['-f', 'lavfi', '-i', 'testsrc2=size=3840x2160:rate=30', '-t', '6', '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '18', '-pix_fmt', 'yuv420p', '-threads', '2', '-movflags', '+faststart']),
]:
    if not (fixture/name).exists():
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *options, str(fixture/name)], check=True)

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    arrivals = {}
    def handle(self):
        try: super().handle()
        except (BrokenPipeError, ConnectionResetError): pass
    def do_GET(self):
        self.arrivals[self.path] = time.perf_counter()
        path = self.path.split('?')[0]
        if path in ('/image.png', '/video.mp4'):
            data = (fixture/path[1:]).read_bytes()
            mime = 'image/png' if path.endswith('png') else 'video/mp4'
            start, end = 0, len(data)-1
            header = self.headers.get('Range', '')
            if header.startswith('bytes='):
                first, last = header[6:].split('-', 1)
                start, end = int(first or 0), int(last or end)
                end = min(end, len(data)-1)
                self.send_response(206)
                self.send_header('Content-Range', f'bytes {start}-{end}/{len(data)}')
            else:
                self.send_response(200)
            self.send_header('Accept-Ranges', 'bytes')
            data = data[start:end+1]
            self.send_header('Cache-Control', 'public, max-age=3600')
        else:
            rows = ''.join(f'<p>Document line {i}</p>' for i in range(500))
            data = ('<!doctype html><meta name="color-scheme" content="light dark"><title>Moon navigation fixture</title>'
                    '<style>body{font:16px system-ui;margin:32px}img,video{width:640px;max-width:100%}</style>'
                    '<h1>Full resolution media</h1><img id="photo" src="/image.png">'
                    '<video id="film" muted playsinline preload="none" controls></video>'
                    + rows).encode()
            mime = 'text/html; charset=utf-8'
            self.send_response(200)
            self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        try: self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError): pass
    def log_message(self, *_): pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
origin = f'http://127.0.0.1:{server.server_port}'
world = 'navigation-' + args.label + '-' + uuid.uuid4().hex[:8]
before = set(glob.glob(os.path.expanduser('~/Library/Containers/org.moonbrowser.Moon/Data/tmp/b-t-*.sock')))
log = open('/private/tmp/moon-' + world + '.log', 'w')
app = Path(args.app).resolve()
proc = subprocess.Popen([str(app/'Contents/MacOS/Moon'), '-bench', 'YES', '-welcomed', 'YES'],
                        env=dict(os.environ, MOON_PROBE=world, MOON_MEASURE='1'), stdout=log, stderr=log)
sockpath = None
report = {'label': args.label, 'scope': 'local HTTP/1.1 navigation with a cached 4K image; separate 4K video check; isolated profile; normal WebKit scheduling', 'loads': []}

def request(command, **kw):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(45); client.connect(sockpath)
        client.sendall((json.dumps(dict(do=command, **kw))+'\n').encode())
        data = b''
        while b'\n' not in data:
            part = client.recv(1048576)
            if not part: raise RuntimeError('Probe closed')
            data += part
        value = json.loads(data.split(b'\n')[0])
        if 'error' in value: raise RuntimeError(value['error'])
        return value

def evaluate(ident, js): return request('eval', id=ident, js=js)['value']

try:
    deadline = time.monotonic()+30
    while time.monotonic() < deadline:
        paths = set(glob.glob(os.path.expanduser('~/Library/Containers/org.moonbrowser.Moon/Data/tmp/b-t-*.sock'))) - before
        if paths: sockpath = sorted(paths)[0]; break
        if proc.poll() is not None: raise RuntimeError('Moon exited; see '+log.name)
        time.sleep(.1)
    if not sockpath: raise RuntimeError('No isolated probe socket')
    first_started = time.perf_counter()
    tab = request('open', url=origin+'/page?run=0')['id']
    request('select', id=tab)
    for i in range(12):
        started = time.perf_counter() if i else first_started
        if i: request('go', id=tab, url=origin+f'/page?run={i}')
        request('wait', id=tab)
        deadline = time.monotonic()+15
        while True:
            metrics = json.loads(evaluate(tab, """JSON.stringify({
          navigation: performance.getEntriesByType('navigation').map(n=>({url:n.name,ttfb:n.responseStart,dom:n.domContentLoadedEventEnd,load:n.loadEventEnd,transfer:n.transferSize}))[0],
          fcp: performance.getEntriesByName('first-contentful-paint')[0]?.startTime || 0,
          image: {width:photo.naturalWidth,height:photo.naturalHeight,complete:photo.complete},
          video: {width:film.videoWidth,height:film.videoHeight,ready:film.readyState}
        })"""))
            if metrics.get('navigation', {}).get('url') == origin+f'/page?run={i}' and metrics['navigation']['load'] > 0:
                break
            if time.monotonic() >= deadline: raise RuntimeError('Navigation did not finish: '+str(metrics))
            time.sleep(.05)
        assert metrics['image'] == {'width': 3840, 'height': 2160, 'complete': True}, metrics
        assert metrics['navigation']['load'] > 0, metrics
        metrics['action_to_request_ms'] = round((Handler.arrivals[f'/page?run={i}']-started)*1000, 3)
        report['loads'].append(metrics)
    evaluate(tab, '''window.__frames=0; window.__lastFrame=null;
      if (film.requestVideoFrameCallback) film.requestVideoFrameCallback(function frame(now, info) {
        window.__frames++; window.__lastFrame={width:info.width,height:info.height,presented:info.presentedFrames};
        film.requestVideoFrameCallback(frame);
      }); film.src='/video.mp4'; film.play(); "started"''')
    print(json.dumps({'stage': 'playing', 'app': str(app), 'label': args.label, 'seconds': args.media_seconds}), flush=True)
    time.sleep(args.media_seconds)
    report['playback'] = json.loads(evaluate(tab, "JSON.stringify({time:film.currentTime,paused:film.paused,width:film.videoWidth,height:film.videoHeight,total:film.getVideoPlaybackQuality().totalVideoFrames,dropped:film.getVideoPlaybackQuality().droppedVideoFrames,rate:film.playbackRate,frameCallbacks:window.__frames,lastFrame:window.__lastFrame})"))
    report['playback']['quality_counters_available'] = report['playback']['total'] > 0
    assert report['playback']['width'] == 3840 and report['playback']['height'] == 2160, report['playback']
    assert not report['playback']['paused'] and report['playback']['time'] > 1, report['playback']
    for key in ('ttfb', 'dom', 'load'):
        values = [x['navigation'][key] for x in report['loads'][1:]]
        report[key+'_warm_median_ms'] = round(statistics.median(values), 2)
    report['fcp_warm_median_ms'] = round(statistics.median(x['fcp'] for x in report['loads'][1:]), 2)
    report['action_to_request_warm_median_ms'] = round(statistics.median(x['action_to_request_ms'] for x in report['loads'][1:]), 3)
finally:
    if sockpath:
        try: request('quit')
        except Exception: pass
    try: proc.wait(timeout=5)
    except subprocess.TimeoutExpired: proc.terminate(); proc.wait(timeout=5)
    server.shutdown(); log.close()
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k != 'loads'}))
