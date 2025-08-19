#!/bin/bash
set -euo pipefail

MON_DIR=${MON_DIR:-/cromwell_root/monitoring}
INTERVAL=${MONITOR_INTERVAL_SECONDS:-15}
HEAVY_INTERVAL=${MONITOR_HEAVY_INTERVAL_SECONDS:-60}
LOW_DISK_GB_WARN=${LOW_DISK_GB_WARN:-20}
LOW_DISK_GB_CRIT=${LOW_DISK_GB_CRIT:-5}
LIGHT_MODE=${MON_LIGHT:-0}
START_EPOCH=$(date +%s)
mkdir -p "$MON_DIR"
OUT_TSV="$MON_DIR/usage.tsv"
OUT_JSONL="$MON_DIR/usage.jsonl"
TOP_TXT="$MON_DIR/top.txt"
LARGEST_TXT="$MON_DIR/largest.txt"
SUMMARY_TXT="$MON_DIR/summary.txt"
SAMPLE_NAME_FILE="$MON_DIR/sample_name.txt"

rotate_if_large() {
  local file="$1" max_bytes=${2:-10485760}
  if [[ -f "$file" ]]; then
    local size
    size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
    if [[ ${size:-0} -ge $max_bytes ]]; then
      mv "$file" "${file}.1" 2>/dev/null || true
      : > "$file"
    fi
  fi
}

write_summary() {
  {
    echo "Monitoring summary at $(date -Is)"
    echo "Latest usage line:"; tail -n 1 "$OUT_TSV" 2>/dev/null || true
    echo "Top disk users (last sample):"; head -n 50 "$LARGEST_TXT" 2>/dev/null || true
  } > "$SUMMARY_TXT"
}

if [[ ! -f "$OUT_TSV" ]]; then
  echo -e "timestamp\tload1\tmem_used_mb\tmem_free_mb\tdisk_used_gb\tdisk_free_gb\tdisk_used_gb_root\tdisk_free_gb_root" > "$OUT_TSV"
fi

trap 'write_summary' EXIT

while true; do
  ts=$(date -Is)
  now_epoch=$(date +%s)
  mon_secs=$(( now_epoch - START_EPOCH ))
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
  # Detect sample name from /mnt/bam (first BAM)
  if [[ ! -s "$SAMPLE_NAME_FILE" ]]; then
    sn=$(ls -1 /mnt/bam/*.bam 2>/dev/null | head -n1 | xargs -I{} basename {} || true)
    if [[ -n "${sn:-}" ]]; then echo "$sn" > "$SAMPLE_NAME_FILE"; fi
  fi
  sample_name=$(cat "$SAMPLE_NAME_FILE" 2>/dev/null || echo "")

  # Try to capture AltAnalyze process metrics
  alt_pid=""; alt_cpu=""; alt_pmem=""; alt_rss_mb=""; alt_vsz_mb=""; alt_read_mb=""; alt_write_mb=""
  if command -v pgrep >/dev/null 2>&1; then
    pid_list=$(pgrep -f "AltAnalyze\.sh|bam_to_bed|AltAnalyze\.py" || true)
  else
    pid_list=$(ps axo pid,command | grep -E "AltAnalyze\.sh|bam_to_bed|AltAnalyze\.py" | grep -v grep | awk '{print $1}' || true)
  fi
  for p in $pid_list; do
    if [[ -d "/proc/$p" ]]; then alt_pid=$p; break; fi
  done
  if [[ -n "$alt_pid" ]]; then
    read _ alt_cpu alt_pmem alt_rss_kb alt_vsz_kb _ < <(ps -o pid,pcpu,pmem,rss,vsz,comm -p "$alt_pid" | awk 'NR==2 {print $1, $2, $3, $4, $5, $6}') || true
    alt_rss_mb=$(awk -v k="${alt_rss_kb:-0}" 'BEGIN{printf "%.1f", k/1024}')
    alt_vsz_mb=$(awk -v k="${alt_vsz_kb:-0}" 'BEGIN{printf "%.1f", k/1024}')
    if [[ -r "/proc/$alt_pid/io" ]]; then
      rb=$(awk '/read_bytes/ {print $2}' "/proc/$alt_pid/io" 2>/dev/null || echo 0)
      wb=$(awk '/write_bytes/ {print $2}' "/proc/$alt_pid/io" 2>/dev/null || echo 0)
      alt_read_mb=$(awk -v b="${rb:-0}" 'BEGIN{printf "%.1f", b/1024/1024}')
      alt_write_mb=$(awk -v b="${wb:-0}" 'BEGIN{printf "%.1f", b/1024/1024}')
    fi
  fi

  echo "{\"ts\":\"$ts\",\"mon_secs\":$mon_secs,\"sample\":\"$sample_name\",\"load1\":$load1,\"mem_used_mb\":$mem_used_mb,\"mem_free_mb\":$mem_free_mb,\"disk_used_gb\":$disk_used_gb,\"disk_free_gb\":$disk_free_gb,\"disk_used_gb_root\":$disk_used_gb_root,\"disk_free_gb_root\":$disk_free_gb_root,\"alt_pid\":\"$alt_pid\",\"alt_cpu\":\"$alt_cpu\",\"alt_pmem\":\"$alt_pmem\",\"alt_rss_mb\":\"$alt_rss_mb\",\"alt_vsz_mb\":\"$alt_vsz_mb\",\"alt_read_mb\":\"$alt_read_mb\",\"alt_write_mb\":\"$alt_write_mb\"}" >> "$OUT_JSONL"

  rotate_if_large "$OUT_TSV"
  rotate_if_large "$OUT_JSONL"
  rotate_if_large "$TOP_TXT"
  rotate_if_large "$LARGEST_TXT"

  ps -eo pid,pcpu,pmem,comm,args --sort=-pcpu | head -n 30 > "$TOP_TXT" || true

  # Heavy sampling less frequently or when low disk
  do_heavy=0
  if [[ $LIGHT_MODE -eq 0 ]]; then
    # Every HEAVY_INTERVAL seconds
    if [[ $(( $(date +%s) % HEAVY_INTERVAL )) -lt $INTERVAL ]]; then do_heavy=1; fi
    # Or when free disk below WARN threshold
    if (( ${disk_free_gb%.*} <= LOW_DISK_GB_WARN )); then do_heavy=1; fi
  fi

  if [[ $do_heavy -eq 1 ]]; then
    {
      echo "[$ts] du -sk key dirs (MB):"
      for d in /mnt/disks/cromwell_root "${TMPDIR:-/tmp}" /mnt/bam /mnt/altanalyze_output /cromwell_root; do
        du -sk "$d" 2>/dev/null | awk '{printf "%10.1f MB\t%s\n", $1/1024, $2}'
      done
      echo "[$ts] largest files under cromwell_root:"
      find /mnt/disks/cromwell_root -type f -printf '%s %p\n' 2>/dev/null | sort -nr | head -n 50 | awk '{printf "%8.1f MB %s\n", $1/1024/1024, $2}'
    } > "$LARGEST_TXT" 2>/dev/null || true
  fi

  # Adaptive sampling on low disk
  next_sleep=$INTERVAL
  if (( ${disk_free_gb%.*} <= LOW_DISK_GB_CRIT )); then
    echo "[$ts] CRITICAL: low disk ($disk_free_gb GB free)" >&2
    next_sleep=5
  elif (( ${disk_free_gb%.*} <= LOW_DISK_GB_WARN )); then
    echo "[$ts] WARNING: low disk ($disk_free_gb GB free)" >&2
    next_sleep=${INTERVAL}
  fi

  sleep "$next_sleep"
done
