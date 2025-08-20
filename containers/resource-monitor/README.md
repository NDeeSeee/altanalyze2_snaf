# Resource Monitor for Terra (and beyond)

This directory provides a small, dependency-light resource monitoring script and an optional Docker image. It is designed for Terra/Cromwell runs, but also works off‑Terra.

Recommended: use Terra workspace‑level Monitoring Script with `monitor.sh`. As a portability hedge, the `altanalyze` container in this repo bundles the same `monitor.sh` at `/usr/local/bin/monitor.sh`. The WDL starts it only if no workspace monitor is active, so you can safely keep both.

## Files
- `monitor.sh`: shell monitor (fallback). If Python is available and `monitor.py` exists, `monitor.sh` defers to it automatically.
- `monitor.py`: Python monitor (preferred) using `psutil` when available for richer metrics.
- `Dockerfile`: minimal Ubuntu image with `procps` and Python; copies both monitors.
- `docker-build.sh`: helper to build and push.

## Build and push (example)
```bash
./docker-build.sh ndeeseee/resource-monitor 0.1.0
# Produces ndeeseee/resource-monitor:0.1.0
```

## Recommended usage on Terra
- **Workspace‑level monitoring (preferred):** Paste the contents of `monitor.sh` into the workspace Monitoring Script. Tune env vars at the top of that script.
- **Per‑run override:** In the submission UI, you may override the workspace script for a single run (useful for experiments).
- **WDL fallback (optional, already wired):** The WDL starts `monitor.sh` only if no monitor is already running. It first checks for `/cromwell_root/monitoring/metadata.json`, then falls back to a `pgrep` check. Disable this fallback with `ENABLE_MONITORING=0` if ever needed.

If you prefer a pinned image just for monitoring, you can use `ndeeseee/resource-monitor:<TAG>` as the workspace Monitoring Image and still paste the same `monitor.sh` script.

## Environment variables
- `MONITOR_INTERVAL_SECONDS` (default 15): base sampling interval
- `MONITOR_HEAVY_INTERVAL_SECONDS` (default 60): cadence for heavier du/find sampling
- `LOW_DISK_GB_WARN` (default 20), `LOW_DISK_GB_CRIT` (default 5): thresholds for warnings/adaptive rate
- `MON_LIGHT` (default 0): set to 1 to disable heavy sampling
- `MON_DIR` (default `/cromwell_root/monitoring`): output directory
- `MON_MAX_SAMPLES` (default 0): if >0, stop after N samples (useful for quick tests)
  
WDL fallback toggle:
- `ENABLE_MONITORING` (default 1): when set to `0`, the WDL won’t start the bundled monitor even if available.

Artifacts will be written under `/cromwell_root/monitoring/` in each task.

## What the monitor collects
- Samples and records every N seconds (default 15):
  - Load average (1-minute)
  - Memory used/free (MB)
  - Disk used/free (GB) on `/mnt/disks/cromwell_root` and `/`
  - Top 30 processes by CPU (pid, %CPU, %MEM, command)
- Heavy sampling (default every 60s, or on low disk):
  - `du -sk` of key dirs: `/mnt/disks/cromwell_root`, `$TMPDIR`, `/mnt/bam`, `/mnt/altanalyze_output`, `/cromwell_root`
  - Top 50 largest files under `/mnt/disks/cromwell_root`
- Emits both TSV (`usage.tsv`) and JSON lines (`usage.jsonl`) for easy parsing
- Low-disk warnings to stderr at <20 GB (WARN) and <5 GB (CRITICAL) with adaptive faster sampling
- Auto-rotates large logs (simple size rotation)
- On exit, writes a short `summary.txt` with latest usage and largest files

### Output files
- `usage.tsv` and `usage.jsonl`: continuous metrics stream; JSON lines include `task`, `shard`, `attempt`, and `cwd` extracted from Cromwell paths
- `top.txt`: top processes by CPU and by RSS
- `largest.txt`: largest files snapshot (heavy sampling cadence)
- `summary.txt`: brief summary written on exit
- `metadata.json`: one-time snapshot at startup with hostname, task/shard/attempt, cgroup resource limits

## Current limitations / caveats
- It cannot prevent ENOSPC; it only reports early signals so you can size disks appropriately
- Process PIDs may be container-namespaced; if Terra isolates task PIDs, `ps` output may be limited
- `du`/`find` can be expensive on extremely large trees; heavy sampling is throttled, `nice`/`ionice`-d, and can be disabled (`MON_LIGHT=1`)
- Rotation is size-based, not time-based; very long runs may produce `.1` files per log
- No external shipping of logs; artifacts remain in task outputs

## Portability and duplication
- The `altanalyze` container in this repo bundles `monitor.sh` at `/usr/local/bin/monitor.sh` so off‑Terra runs behave the same. The WDL only starts it if a workspace‑level monitor is not already running.
- Duplicate protection in WDL: checks for an existing `/cromwell_root/monitoring/metadata.json`, then `pgrep` for `monitor.sh`. If you use a differently named monitor, set `ENABLE_MONITORING=0` to force-disable the fallback.
- Keep a single source of truth for the script: update `containers/resource-monitor/monitor.sh` here; use that content for Terra workspace and for embedding into images to avoid drift.

## Local quick test
Run a short sampling session on your machine (non-Linux falls back to zeros for /proc):
```bash
MON_DIR="/tmp/mon" MONITOR_INTERVAL_SECONDS=1 MON_HEAVY_INTERVAL_SECONDS=2 MON_LIGHT=1 MON_MAX_SAMPLES=3 bash containers/resource-monitor/monitor.sh
ls -la /tmp/mon
```

## Ideas to improve (optional)
- Optional sysstat-based I/O metrics (`iostat`, `vmstat`) via a larger image variant
- Prometheus text exposition endpoint for scraping (requires a long-running sidecar)
- Push summaries to GCS mid-run if desired (needs credentials and policy)
- PID-aware tracking of specific tools (e.g., AltAnalyze) when namespaces permit
