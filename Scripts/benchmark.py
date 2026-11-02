#!/usr/bin/env python3
"""Run Moon's explicit, isolated release workload and retain comparable evidence."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, default=Path(__file__).resolve().parents[1] / "build/Moon.app")
    parser.add_argument("--runs", type=int, choices=range(1, 11), default=3)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    binary = args.app.resolve() / "Contents/MacOS/Moon"
    if not binary.is_file():
        parser.error("Build Moon's release app first.")
    results = []
    for index in range(args.runs):
        directory = Path(tempfile.mkdtemp(prefix="MoonBenchmark.", dir="/private/tmp"))
        environment = dict(os.environ, MOON_TEST_DIRECTORY=str(directory))
        print(f"Controlled workload {index + 1}/{args.runs}", flush=True)
        with (directory / "process.log").open("wb") as log:
            started = time.perf_counter()
            process = subprocess.Popen([str(binary), "--performance-test"], env=environment, stdout=log, stderr=log)
            ready_ms = None
            try:
                while process.poll() is None:
                    if ready_ms is None and (directory / "window-ready").exists():
                        ready_ms = (time.perf_counter() - started) * 1000
                    if time.perf_counter() - started > 90:
                        raise RuntimeError(f"Workload timed out; details: {directory}")
                    time.sleep(0.005 if ready_ms is None else 0.1)
                report = json.loads((directory / "performance.json").read_text())
                if not report.get("passed"):
                    raise RuntimeError(f"Workload failed: {report.get('error')}; details: {directory}")
                report["launch_to_window_ready_ms"] = ready_ms
                results.append(report)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    navigation = sorted(value for run in results for value in run["local_navigation_ms"])
    queries = sorted(value for run in results for value in run["history_10k_common_query_ms"])
    summary = {
        "runs": len(results),
        "window_ready_median_ms": statistics.median(run["launch_to_window_ready_ms"] for run in results),
        "navigation_median_ms": statistics.median(navigation),
        "navigation_p95_ms": navigation[math.ceil(len(navigation) * .95) - 1],
        "query_10k_median_ms": statistics.median(queries),
        "query_10k_p95_ms": queries[math.ceil(len(queries) * .95) - 1],
        "blank_main_footprint_mib": statistics.median(run["blank"]["physical_footprint_bytes"] for run in results) / 1048576,
        "lazy_80_main_footprint_mib": statistics.median(run["lazy_80"]["physical_footprint_bytes"] for run in results) / 1048576,
        "one_loaded_main_footprint_mib": statistics.median(run["one_loaded"]["physical_footprint_bytes"] for run in results) / 1048576,
        "idle_main_cpu_percent": statistics.median(run["idle_main_cpu_percent"] for run in results),
        "all_lazy_views_zero": all(run["lazy_live_views"] == 0 for run in results),
        "all_sleep_releases_passed": all(run["sleep_released_view"] for run in results),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    artifact = {"app": binary.parent.parent.parent.name, "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(), "binary_bytes": binary.stat().st_size}
    args.output.write_text(json.dumps({"artifact": artifact, "summary": summary, "workloads": results}, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
