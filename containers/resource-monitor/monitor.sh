#!/bin/bash
set -euo pipefail

MON_DIR=${MON_DIR:-/cromwell_root/monitoring}
INTERVAL=${MONITOR_INTERVAL_SECONDS:-15}
mkdir -p "$MON_DIR"
OUT_TSV="$MON_DIR/usage.tsv"
TOP_TXT="$MON_DIR/top.txt"

if [[ ! -f "$OUT_TSV" ]]; then
  echo -e "timestamp\tload1\tmem_used_mb\tmem_free_mb\tdisk_used_gb\tdisk_free_gb\tdisk_used_gb_root\tdisk_free_gb_root" > "$OUT_TSV"
fi

while true; do
  ts=$(date -Is)
  # Load average
  read load1 _ < /proc/loadavg || load1=0
  # Memory
  mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo || echo 0)
  mem_avail_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo || echo 0)
  mem_used_mb=$(( (mem_total_kb - mem_avail_kb) / 1024 ))
  mem_free_mb=$(( mem_avail_kb / 1024 ))
  # Disk cromwell_root
  df_cr=$(df -k /mnt/disks/cromwell_root 2>/dev/null | awk 'NR==2 {print $3, $4}')
  used_k=$(echo "$df_cr" | awk '{print $1}')
  avail_k=$(echo "$df_cr" | awk '{print $2}')
  disk_used_gb=$(awk -v u="${used_k:-0}" 'BEGIN{printf "%.1f", u/1024/1024}')
  disk_free_gb=$(awk -v a="${avail_k:-0}" 'BEGIN{printf "%.1f", a/1024/1024}')
  # Disk root (/)
  df_root=$(df -k / 2>/dev/null | awk 'NR==2 {print $3, $4}')
  used_k_root=$(echo "$df_root" | awk '{print $1}')
  avail_k_root=$(echo "$df_root" | awk '{print $2}')
  disk_used_gb_root=$(awk -v u="${used_k_root:-0}" 'BEGIN{printf "%.1f", u/1024/1024}')
  disk_free_gb_root=$(awk -v a="${avail_k_root:-0}" 'BEGIN{printf "%.1f", a/1024/1024}')

  echo -e "$ts\t$load1\t$mem_used_mb\t$mem_free_mb\t$disk_used_gb\t$disk_free_gb\t$disk_used_gb_root\t$disk_free_gb_root" >> "$OUT_TSV"
  ps -eo pid,pcpu,pmem,comm,args --sort=-pcpu | head -n 30 > "$TOP_TXT" || true
  sleep "$INTERVAL"
done
