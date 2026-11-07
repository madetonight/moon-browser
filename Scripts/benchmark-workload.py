#!/usr/bin/env python3
"""Controlled 38-tab benchmark. Uses a disposable Moon profile, never user tabs.

Reports RSS and CPU for Moon and processes macOS attributes to it, including
WebKit XPC workers. RSS sums may count shared pages more than once. CPU 100%
means one core. Local fixtures make comparisons repeatable, not representative
of every website. Run outside the command sandbox for process accounting.
"""
import argparse
import ctypes
import glob
import http.server
import json
import os
from pathlib import Path
import socket
import subprocess
import threading
import time
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', default='build/Moon.app')
parser.add_argument('--output', required=True)
parser.add_argument('--label', default='baseline')
parser.add_argument('--settle-seconds', type=int, default=30)
parser.add_argument('--sample-seconds', type=int, default=30)
parser.add_argument('--windows', type=int, default=3)
parser.add_argument('--include-sleep', action='store_true', help='Optional separate diagnostic; never included in live-tab results')
parser.add_argument('--visible', action='store_true', help='Explicit opt-in to a foreground disposable test window')
parser.add_argument('--static', action='store_true', help='Separate truly idle workload, without the 250ms page-content timer')
args = parser.parse_args()
if min(args.settle_seconds, args.sample_seconds, args.windows) < 1:
    parser.error('Durations and window count must be positive')
lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
class Timebase(ctypes.Structure):
    _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]

timebase = Timebase()
if lib.mach_timebase_info(ctypes.byref(timebase)) != 0 or not timebase.denom:
    raise RuntimeError('Cannot convert macOS CPU counters to seconds')
cpu_seconds_per_tick = timebase.numer / timebase.denom / 1e9
responsible = lib.responsibility_get_pid_responsible_for_pid
responsible.argtypes = [ctypes.c_int]
responsible.restype = ctypes.c_int


class Usage(ctypes.Structure):
    _fields_ = [('uuid', ctypes.c_uint8 * 16)] + [(key, ctypes.c_uint64) for key in (
        'user', 'system', 'idle_wakeups', 'interrupt_wakeups', 'pageins',
        'wired', 'resident', 'footprint', 'start', 'exit')]


def usage(pid):
    usage = Usage()
    if lib.proc_pid_rusage(pid, 0, ctypes.byref(usage)) != 0:
        return None
    return usage


class Fixture(http.server.BaseHTTPRequestHandler):
    document_requests = []
    def do_GET(self):
        if not self.path.split('?')[0].strip('/').isdigit() and self.path != '/':
            self.send_error(404)
            return
        page = int(self.path.split('?')[0].strip('/') or '0')
        self.document_requests.append(page)
        rows = ''.join(f'<tr><td>{i}</td><td>Document {page}, entry {i}</td>'
                       f'<td>{i * 17}</td></tr>' for i in range(1800))
        clock = '' if args.static else '<script>setInterval(()=>{document.getElementById("clock").textContent=Date.now()},250)</script>'
        body = (f'<!doctype html><title>Workload {page:02}</title>'
                '<style>body{font:15px system-ui;margin:40px;background:#f6f7fa}'
                'table{width:100%;border-collapse:collapse}td{padding:6px;border-bottom:1px solid #ddd}</style>'
                f'<h1>Moon workload {page:02}</h1><p id="clock"></p><table>{rows}</table>'
                + clock).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
threading.Thread(target=server.serve_forever, daemon=True).start()
app = Path(args.app).resolve()
world = 'workload-' + args.label + '-' + uuid.uuid4().hex[:8]
world_key = ''.join(c for c in world.lower() if c.isascii() and (c.isalnum() or c == '-'))
world_hash = 2_166_136_261
for byte in world_key.encode():
    world_hash = ((world_hash ^ byte) * 16_777_619) & 0xffffffff
socket_name = f'b-t-5E4C{world_hash:08X}.sock'
log = open('/private/tmp/moon-' + world + '.log', 'w')
before = set(glob.glob(os.path.expanduser('~/Library/Containers/org.moonbrowser.Moon/Data/tmp/b-t-*.sock')))
env = dict(os.environ, MOON_PROBE=world, MOON_MEASURE='1')
if args.visible:
    env['MOON_MEASURE_VISIBLE'] = '1'
preexisting_pids = {int(p) for p in subprocess.check_output(['/bin/ps', '-axo', 'pid='], text=True).split()}
proc = subprocess.Popen([str(app/'Contents/MacOS/Moon'), '-bench', 'YES', '-welcomed', 'YES'], env=env, stdout=log, stderr=log)
launch_owner = responsible(proc.pid)
sockpath = None


def request(command, **kwargs):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(45)
        client.connect(sockpath)
        client.sendall((json.dumps(dict(do=command, **kwargs)) + '\n').encode())
        data = b''
        while b'\n' not in data:
            part = client.recv(1048576)
            if not part:
                raise RuntimeError('Moon closed the connection')
            data += part
        value = json.loads(data.split(b'\n')[0])
        if 'error' in value:
            raise RuntimeError(value['error'])
        return value


def processes():
    rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,ppid=,rss=,time=,comm='], text=True)
    entries = {}
    for row in rows.splitlines():
        fields = row.split(None, 4)
        if len(fields) != 5:
            continue
        pid, ppid, rss = map(int, fields[:3])
        clock = fields[3].replace('-', ':').split(':')
        seconds = 0.0
        for part in clock:
            seconds = seconds * 60 + float(part)
        entries[pid] = dict(pid=pid, parent=ppid, rss_bytes=rss*1024,
                            cpu_seconds=seconds, name=fields[4])
    owned = {proc.pid}
    for pid in entries:
        owner = responsible(pid)
        # A CLI-launched app inherits the launcher responsibility. Exclude
        # all preexisting workers and require WebKit's executable identity.
        inherited_worker = (owner == launch_owner and pid not in preexisting_pids
                            and '/WebKit.framework/' in entries[pid]['name'])
        if owner == proc.pid or inherited_worker:
            owned.add(pid)
    while True:
        children = {pid for pid, row in entries.items() if row['parent'] in owned}
        if children <= owned:
            break
        owned |= children
    result = {pid: entries[pid] for pid in owned if pid in entries}
    for pid, row in result.items():
        counters = usage(pid)
        row['physical_footprint_bytes'] = counters.footprint if counters else None
        if counters:
            row['cpu_seconds'] = (counters.user + counters.system) * cpu_seconds_per_tick
    return result


def sample(label, duration=15):
    before_state = request('tabs').get('measurement')
    initial = processes()
    start = time.monotonic()
    samples = []
    for _ in range(duration):
        time.sleep(1)
        samples.append(processes())
    last = samples[-1]
    elapsed = time.monotonic()-start
    for pid, row in last.items():
        row['sample_cpu_percent_one_core'] = max(0, row['cpu_seconds'] - initial.get(pid, {}).get('cpu_seconds', row['cpu_seconds'])) / elapsed * 100
    cpu = sum(row['sample_cpu_percent_one_core'] for row in last.values())
    after_tabs = request('tabs')
    result = dict(stage=label, cpu_percent_one_core=round(cpu, 4),
                  cpu_at_or_below_0_1=cpu <= 0.1,
                  rss_mean_mb=round(sum(sum(r['rss_bytes'] for r in s.values()) for s in samples)/len(samples)/1e6, 2),
                  rss_peak_mb=round(max(sum(r['rss_bytes'] for r in s.values()) for s in samples)/1e6, 2),
                  process_count_min=min(len(s) for s in samples),
                  process_count_max=max(len(s) for s in samples),
                  measurement_before=before_state, measurement_after=after_tabs.get('measurement'),
                  processes=list(last.values()), tabs=after_tabs['tabs'])
    if all(r['physical_footprint_bytes'] is not None for s in samples for r in s.values()):
        result['physical_footprint_mean_mb'] = round(sum(sum(r['physical_footprint_bytes'] for r in s.values()) for s in samples)/len(samples)/1e6, 2)
    print(json.dumps({k:v for k,v in result.items() if k not in ('processes','tabs')}), flush=True)
    return result


report = dict(label=args.label, tab_count=38, workload='38 documents, each 1800 table rows' + ('; static idle' if args.static else ' and a 250ms DOM timer'),
              visibility='foreground requested' if args.visible else 'background',
              accounting='Physical footprint and CPU from proc_pid_rusage across responsible process family; CPU 100%=one core',
              cpu_timebase=dict(numer=timebase.numer, denom=timebase.denom),
              settle_seconds=args.settle_seconds, sample_seconds=args.sample_seconds, stages=[])

def checkpoint():
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(json.dumps(report, indent=2)+'\n')

try:
    launched_at = time.monotonic()
    report['startup_process_samples'] = []
    deadline = time.monotonic()+30
    while time.monotonic() < deadline:
        report['startup_process_samples'].append(dict(elapsed_ms=round((time.monotonic()-launched_at)*1000, 1),
                                                       count=len(processes())))
        # Match this exact disposable world, rather than whichever new test
        # socket happens to appear first while another test is running.
        paths = set(glob.glob(os.path.expanduser('~/Library/Containers/org.moonbrowser.Moon/Data/tmp/' + socket_name))) - before
        if paths:
            sockpath = sorted(paths)[0]
            break
        if proc.poll() is not None:
            raise RuntimeError('Moon exited; inspect '+log.name)
        time.sleep(.2)
    if not sockpath:
        raise RuntimeError('No probe socket; inspect '+log.name)
    report['pid'] = proc.pid
    report['startup_process_peak'] = max(row['count'] for row in report['startup_process_samples'])
    report['socket'] = sockpath
    report['stages'].append(sample('startup_empty', 5))
    report['startup_process_peak'] = max(report['startup_process_peak'], report['stages'][0]['process_count_max'])
    checkpoint()
    initial_tabs = request('tabs')['tabs']
    ids = []
    loads = []
    for i in range(38):
        start = time.monotonic()
        opened = request('split', action='open', url=f'http://127.0.0.1:{server.server_port}/{i}', foreground=True)
        ident = opened['resultID']
        ready = request('wait', id=ident)
        if ready.get('failure') or ready.get('timeout') or ready['title'] != f'Workload {i:02}':
            raise RuntimeError(f'Fixture {i} failed to load: {ready}')
        loads.append(round((time.monotonic()-start)*1000, 2))
        ids.append(ident)
        if i == 0:
            for tab in initial_tabs:
                if not tab['url']:
                    request('split', action='close', id=tab['id'])
    report['load_ms'] = loads
    report['load_timing_note'] = 'Navigation plus benchmark wait, which adds a fixed 250ms settle delay; not network-only page-load time.'
    time.sleep(5)
    report['stages'].append(sample('38_loaded_early', 15))
    checkpoint()
    time.sleep(args.settle_seconds)
    for window in range(args.windows):
        report['stages'].append(sample(f'38_loaded_settled_{window+1}', args.sample_seconds))
        checkpoint()
    for stage in report['stages'][1:]:
        if len(stage['tabs']) != 38 or any(tab['asleep'] for tab in stage['tabs']):
            raise RuntimeError('Live-tab measurements require exactly 38 awake tabs')
    # Switching among live tabs must retain the document, not reload it.
    switch_times = []
    for ident in [ids[0], ids[len(ids)//2], ids[-1]]:
        marker = 'state-' + uuid.uuid4().hex
        request('eval', id=ident, js=f'window.__moonWorkloadState = {json.dumps(marker)}; window.__moonWorkloadState')
        start = time.monotonic()
        request('select', id=ident)
        switch_times.append((time.monotonic()-start)*1000)
        check = request('eval', id=ident, js='window.__moonWorkloadState')
        if check.get('value') != marker:
            raise RuntimeError('Live tab lost its document state when selected')
        report.setdefault('live_state_checks', []).append(dict(id=ident, marker=marker, response=check))
    report['live_select_command_ms'] = switch_times
    report['document_requests_after_live_switches'] = list(Fixture.document_requests)
    if args.include_sleep:
        for ident in ids[:-1]:
            request('sleep', id=ident)
            # Let each snapshot finish before asking for another.
            deadline = time.monotonic()+5
            while time.monotonic() < deadline:
                if next(t for t in request('tabs')['tabs'] if t['id']==ident)['asleep']:
                    break
                time.sleep(.05)
        time.sleep(5)
        report['stages'].append(sample('37_sleeping_one_active'))
        start = time.monotonic()
        request('select', id=ids[0])
        request('wait', id=ids[0])
        report['wake_ms'] = round((time.monotonic()-start)*1000, 2)
finally:
    checkpoint()
    if sockpath:
        try:
            request('quit')
        except Exception:
            pass
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.terminate()
    server.shutdown()
    log.close()
