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
