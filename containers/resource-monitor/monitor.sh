#!/bin/bash
set -euo pipefail

#!/bin/bash
set -euo pipefail

MON_DIR=${MON_DIR:-/cromwell_root/monitoring}
INTERVAL=${MONITOR_INTERVAL_SECONDS:-15}
HEAVY_INTERVAL=${MONITOR_HEAVY_INTERVAL_SECONDS:-60}
LOW_DISK_GB_WARN=${LOW_DISK_GB_WARN:-20}
LOW_DISK_GB_CRIT=${LOW_DISK_GB_CRIT:-5}
LIGHT_MODE=${MON_LIGHT:-0}
# For testing or bounded runs; 0 means unlimited
MAX_SAMPLES=${MON_MAX_SAMPLES:-0}
START_EPOCH=$(date +%s)
mkdir -p "$MON_DIR"
OUT_TSV="$MON_DIR/usage.tsv"
OUT_JSONL="$MON_DIR/usage.jsonl"
TOP_TXT="$MON_DIR/top.txt"
LARGEST_TXT="$MON_DIR/largest.txt"
SUMMARY_TXT="$MON_DIR/summary.txt"
SAMPLE_NAME_FILE="$MON_DIR/sample_name.txt"
META_JSON="$MON_DIR/metadata.json"

# Detect cromwell root mount path (best-effort)
CR_ROOT="/mnt/disks/cromwell_root"
if ! df -k "$CR_ROOT" >/dev/null 2>&1; then
  if df -k "/cromwell_root" >/dev/null 2>&1; then CR_ROOT="/cromwell_root"; else CR_ROOT="."; fi
fi

detect_task_context() {
  local cwd
  cwd=$(pwd 2>/dev/null || echo "")
  local call shard attempt
  call=""; shard=""; attempt=""
  # Common Cromwell layout: .../call-TaskName[/shard-#/][attempt-#/]/execution
  if [[ -n "$cwd" ]]; then
    call=$(echo "$cwd" | sed -n 's#.*/call-\([^/]*\)/.*#\1#p')
    shard=$(echo "$cwd" | sed -n 's#.*/shard-\([0-9][0-9]*\)/.*#\1#p')
    attempt=$(echo "$cwd" | sed -n 's#.*/attempt-\([0-9][0-9]*\)/.*#\1#p')
  fi
  echo "$call|$shard|$attempt|$cwd"
}

read_cgroup_limits() {
  # Outputs: cpu_limit_cores|mem_limit_mb|mem_current_mb
  local cpu_limit mem_limit mem_current
  cpu_limit=""; mem_limit=""; mem_current=""
  # cgroup v2 paths
  if [[ -f /sys/fs/cgroup/cpu.max ]]; then
    local max
    max=$(cat /sys/fs/cgroup/cpu.max 2>/dev/null || echo "")
    # Format: "max" or "<quota> <period>"
    if echo "$max" | grep -qE '^[0-9]+ [0-9]+'; then
      local quota period
      quota=$(echo "$max" | awk '{print $1}')
      period=$(echo "$max" | awk '{print $2}')
      if [[ ${period:-0} -gt 0 ]]; then
        cpu_limit=$(awk -v q="$quota" -v p="$period" 'BEGIN{printf "%.2f", q/p}')
      fi
    fi
  elif [[ -f /sys/fs/cgroup/cpu/cpu.cfs_quota_us && -f /sys/fs/cgroup/cpu/cpu.cfs_period_us ]]; then
    local quota period
    quota=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null || echo -1)
    period=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us 2>/dev/null || echo 0)
    if [[ ${quota:-0} -gt 0 && ${period:-0} -gt 0 ]]; then
      cpu_limit=$(awk -v q="$quota" -v p="$period" 'BEGIN{printf "%.2f", q/p}')
    fi
  fi
  # Memory limits
  if [[ -f /sys/fs/cgroup/memory.max ]]; then
    local max current
    max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo "")
    current=$(cat /sys/fs/cgroup/memory.current 2>/dev/null || echo "")
    if [[ "$max" != "max" && -n "$max" ]]; then mem_limit=$(awk -v b="$max" 'BEGIN{printf "%.1f", b/1024/1024}'); fi
    if [[ -n "$current" ]]; then mem_current=$(awk -v b="$current" 'BEGIN{printf "%.1f", b/1024/1024}'); fi
  elif [[ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then
    local max current
    max=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo 0)
    current=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null || echo 0)
    if [[ ${max:-0} -gt 0 ]]; then mem_limit=$(awk -v b="$max" 'BEGIN{printf "%.1f", b/1024/1024}'); fi
    if [[ ${current:-0} -gt 0 ]]; then mem_current=$(awk -v b="$current" 'BEGIN{printf "%.1f", b/1024/1024}'); fi
  fi
  echo "${cpu_limit}|${mem_limit}|${mem_current}"
}

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
  echo -e "timestamp\tload1\tmem_used_mb\tmem_free_mb\tdisk_used_gb\tdisk_free_gb\tdisk_used_gb_root\tdisk_free_gb_root\tdisk_used_gb_pwd\tdisk_free_gb_pwd" > "$OUT_TSV"
fi

trap 'write_summary' EXIT

{
  # One-time metadata snapshot for easier per-task attribution
  IFS='|' read -r task_name shard_idx attempt_idx cwd_path <<< "$(detect_task_context)"
  IFS='|' read -r cpu_limit_cores mem_limit_mb mem_current_mb <<< "$(read_cgroup_limits)"
  host=$(hostname 2>/dev/null || echo "")
  cpu_count=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo "")
  printf '{"ts":"%s","hostname":"%s","task":"%s","shard":"%s","attempt":"%s","cwd":"%s","cpu_limit_cores":%s,"mem_limit_mb":%s,"mem_current_mb":%s,"cpu_count":%s,"env_sample":"%s"}\n' \
    "$(date -Is)" "$host" "${task_name}" "${shard_idx}" "${attempt_idx}" "$cwd_path" \
    "${cpu_limit_cores:-null}" "${mem_limit_mb:-null}" "${mem_current_mb:-null}" \
    "${cpu_count:-null}" \
    "MON_DIR=$MON_DIR;INTERVAL=$INTERVAL;HEAVY_INTERVAL=$HEAVY_INTERVAL;LOW_DISK_GB_WARN=$LOW_DISK_GB_WARN;LOW_DISK_GB_CRIT=$LOW_DISK_GB_CRIT;LIGHT_MODE=$LIGHT_MODE" \
    > "$META_JSON" 2>/dev/null || true
}

sample_count=0
while true; do
  ts=$(date -Is)
  now_epoch=$(date +%s)
  mon_secs=$(( now_epoch - START_EPOCH ))
  # Load average
  read load1 _ < /proc/loadavg || load1=0
  # Memory
  mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  mem_avail_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  mem_used_mb=$(( (mem_total_kb - mem_avail_kb) / 1024 ))
  mem_free_mb=$(( mem_avail_kb / 1024 ))
  # Disk cromwell_root
  df_cr=$(df -k "$CR_ROOT" 2>/dev/null | awk 'NR==2 {print $3, $4}')
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
  # Disk for current working directory mount
  df_pwd=$(df -k . 2>/dev/null | awk 'NR==2 {print $3, $4}')
  used_k_pwd=$(echo "$df_pwd" | awk '{print $1}')
  avail_k_pwd=$(echo "$df_pwd" | awk '{print $2}')
  disk_used_gb_pwd=$(awk -v u="${used_k_pwd:-0}" 'BEGIN{printf "%.1f", u/1024/1024}')
  disk_free_gb_pwd=$(awk -v a="${avail_k_pwd:-0}" 'BEGIN{printf "%.1f", a/1024/1024}')

  echo -e "$ts\t$load1\t$mem_used_mb\t$mem_free_mb\t$disk_used_gb\t$disk_free_gb\t$disk_used_gb_root\t$disk_free_gb_root\t$disk_used_gb_pwd\t$disk_free_gb_pwd" >> "$OUT_TSV"
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
  # Pick the first live PID; if multiple, prefer highest CPU
  if [[ -n "$pid_list" ]]; then
    alt_pid=$(ps -o pid,pcpu --no-headers -p $pid_list 2>/dev/null | sort -k2,2nr | head -n1 | awk '{print $1}')
  fi
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

  # Task context for each line (re-read from metadata if needed)
  IFS='|' read -r task_name shard_idx attempt_idx cwd_path <<< "$(detect_task_context)"
  # Coerce empty numeric fields to null (leave CPU/mem pct as numbers if possible)
  alt_cpu_json=$( [[ -n "$alt_cpu" ]] && echo "$alt_cpu" || echo null )
  alt_pmem_json=$( [[ -n "$alt_pmem" ]] && echo "$alt_pmem" || echo null )
  alt_rss_json=$( [[ -n "$alt_rss_mb" ]] && echo "$alt_rss_mb" || echo null )
  alt_vsz_json=$( [[ -n "$alt_vsz_mb" ]] && echo "$alt_vsz_mb" || echo null )
  alt_read_json=$( [[ -n "$alt_read_mb" ]] && echo "$alt_read_mb" || echo null )
  alt_write_json=$( [[ -n "$alt_write_mb" ]] && echo "$alt_write_mb" || echo null )
  echo "{\"ts\":\"$ts\",\"mon_secs\":$mon_secs,\"task\":\"$task_name\",\"shard\":\"$shard_idx\",\"attempt\":\"$attempt_idx\",\"cwd\":\"$cwd_path\",\"sample\":\"$sample_name\",\"load1\":$load1,\"mem_used_mb\":$mem_used_mb,\"mem_free_mb\":$mem_free_mb,\"disk_used_gb\":$disk_used_gb,\"disk_free_gb\":$disk_free_gb,\"disk_used_gb_root\":$disk_used_gb_root,\"disk_free_gb_root\":$disk_free_gb_root,\"disk_used_gb_pwd\":$disk_used_gb_pwd,\"disk_free_gb_pwd\":$disk_free_gb_pwd,\"alt_pid\":\"$alt_pid\",\"alt_cpu\":$alt_cpu_json,\"alt_pmem\":$alt_pmem_json,\"alt_rss_mb\":$alt_rss_json,\"alt_vsz_mb\":$alt_vsz_json,\"alt_read_mb\":$alt_read_json,\"alt_write_mb\":$alt_write_json}" >> "$OUT_JSONL"

  rotate_if_large "$OUT_TSV"
  rotate_if_large "$OUT_JSONL"
  rotate_if_large "$TOP_TXT"
  rotate_if_large "$LARGEST_TXT"

  {
    echo "[$ts] top by CPU:";
    ps -eo pid,pcpu,pmem,comm,args --sort=-pcpu 2>/dev/null | head -n 30 || true;
    echo ""; echo "[$ts] top by RSS:";
    ps -eo pid,rss,pcpu,pmem,comm,args --sort=-rss 2>/dev/null | head -n 30 || true;
  } > "$TOP_TXT" 2>/dev/null || true

  # Heavy sampling less frequently or when low disk
  do_heavy=0
  if [[ $LIGHT_MODE -eq 0 ]]; then
    # Every HEAVY_INTERVAL seconds
    if [[ $(( $(date +%s) % HEAVY_INTERVAL )) -lt $INTERVAL ]]; then do_heavy=1; fi
    # Or when free disk below WARN threshold
    if (( ${disk_free_gb%.*} <= LOW_DISK_GB_WARN )); then do_heavy=1; fi
  fi

  if [[ $do_heavy -eq 1 ]]; then
    IONICE_PREFIX=""; if command -v ionice >/dev/null 2>&1; then IONICE_PREFIX="ionice -c3"; fi
    {
      echo "[$ts] du -sk key dirs (MB):"
      for d in /mnt/disks/cromwell_root "${TMPDIR:-/tmp}" /mnt/bam /mnt/altanalyze_output /cromwell_root; do
        nice -n 19 $IONICE_PREFIX du -sk "$d" 2>/dev/null | awk '{printf "%10.1f MB\t%s\n", $1/1024, $2}'
      done
      echo "[$ts] largest files under $CR_ROOT:"
      nice -n 19 $IONICE_PREFIX find "$CR_ROOT" -xdev -type f -printf '%s %p\n' 2>/dev/null | sort -nr | head -n 50 | awk '{printf "%8.1f MB %s\n", $1/1024/1024, $2}'
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

  sample_count=$(( sample_count + 1 ))
  if (( MAX_SAMPLES > 0 && sample_count >= MAX_SAMPLES )); then
    write_summary
    exit 0
  fi
  sleep "$next_sleep"
done
