# Resource Monitor for Terra (Optional)

This directory provides an optional, reproducible Docker image and script for Terra/Cromwell Resource Monitoring.

Note: You do NOT need a custom image. A simple setup works:
- Image: `ubuntu:22.04`
- Image script:
  ```bash
  #!/bin/bash
  true
  ```
- Script: copy/paste contents of `monitor.sh`

Use this image only if you prefer to pin and version your monitoring environment.

## Files
- `monitor.sh`: sampling loop that logs CPU load, memory, and disk usage to `/cromwell_root/monitoring`.
- `Dockerfile`: minimal Ubuntu image with `procps` installed for `ps`.
- `docker-build.sh`: helper to build and push.

## Build and push (example)
```bash
./docker-build.sh ndeeseee/resource-monitor 0.1.0
# Produces ndeeseee/resource-monitor:0.1.0
```

## Terra configuration (if using this image)
- Image: `ndeeseee/resource-monitor:<TAG>`
- Image script:
  ```bash
  #!/bin/bash
  true
  ```
- Script: paste `monitor.sh` (you can tune env vars below)

## Environment variables
- `MONITOR_INTERVAL_SECONDS` (default 15): base sampling interval
- `MONITOR_HEAVY_INTERVAL_SECONDS` (default 60): cadence for heavier du/find sampling
- `LOW_DISK_GB_WARN` (default 20), `LOW_DISK_GB_CRIT` (default 5): thresholds for warnings/adaptive rate
- `MON_LIGHT` (default 0): set to 1 to disable heavy sampling
- `MON_DIR` (default `/cromwell_root/monitoring`): output directory

Artifacts will be written under `/cromwell_root/monitoring/` in each task.

## What the script does
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
- `usage.tsv` and `usage.jsonl`: continuous metrics stream
- `top.txt`: current top processes by CPU
- `largest.txt`: largest files snapshot (heavy sampling cadence)
- `summary.txt`: brief summary written on exit

## Current limitations / caveats
- It cannot prevent ENOSPC; it only reports early signals so you can size disks appropriately
- Process PIDs may be container-namespaced; if Terra isolates task PIDs, `ps` output may be limited
- `du`/`find` can be expensive on extremely large trees; heavy sampling is throttled and can be disabled (`MON_LIGHT=1`)
- Rotation is size-based, not time-based; very long runs may produce `.1` files per log
- No external shipping of logs; artifacts remain in task outputs

## Ideas to improve (optional)
- Optional sysstat-based I/O metrics (`iostat`, `vmstat`) via a larger image variant
- Prometheus text exposition endpoint for scraping (requires a long-running sidecar)
- Push summaries to GCS mid-run if desired (needs credentials and policy)
- PID-aware tracking of specific tools (e.g., AltAnalyze) when namespaces permit
