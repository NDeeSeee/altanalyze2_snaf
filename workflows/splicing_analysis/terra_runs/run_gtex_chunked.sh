#!/bin/bash
# Run all GTEx tissues in ascending sample-count chunks using Methods path
# - Submits CHUNK_SIZE tissues at a time (lowest sample sizes first)
# - Waits for the whole chunk to finish; stops on any failure
# - Uses dockstore_run.sh (Methods path default) to ensure per-run tracking
# - Saves a ledger CSV for this campaign
#
# Usage:
#   CHUNK_SIZE=10 PAUSE_SECONDS=30 \ 
#   workflows/splicing_analysis/terra_runs/run_gtex_chunked.sh
#
set -euo pipefail

# Load env (global preferred, then local)
for ENV_FILE in workflows/terra/env.sh workflows/splicing_analysis/terra_runs/env.sh; do
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    break
  fi
done

INPUT_DIR="workflows/splicing_analysis/inputs/gtex_v10_validated"
CHUNK_SIZE=${CHUNK_SIZE:-10}
PAUSE_SECONDS=${PAUSE_SECONDS:-20}
WORKSPACE_PROJECT="${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}"
WORKSPACE_NAME="${WORKSPACE_NAME:-AltAnalyze3_SNAF}"
BUCKET_PREFIX=${BUCKET_PREFIX:-gtex-production-$(date +%Y%m%d-%H%M)}
LEDGER="workflows/splicing_analysis/terra_runs/gtex_chunked_runs_$(date +%Y%m%d-%H%M).csv"

mkdir -p workflows/splicing_analysis/terra_runs
if [[ ! -f "$LEDGER" ]]; then
  echo "timestamp,tissue,sample_count,submission_id,job_url,status,cost,run_dir" > "$LEDGER"
fi

# Build sorted list of tissues by sample count (parse *_<count>.json stem)
mapfile -t TISSUES < <(ls -1 "$INPUT_DIR"/*.json | while read -r p; do 
  base=$(basename "$p" .json)
  cnt=${base##*_}
  printf "%08d\t%s\t%s\n" "$cnt" "$base" "$p"
done | sort -n | awk -F'\t' '{print $2"\t"$1"\t"$3}')

echo "Found ${#TISSUES[@]} tissues in $INPUT_DIR"

start_idx=0
while (( start_idx < ${#TISSUES[@]} )); do
  end_idx=$(( start_idx + CHUNK_SIZE ))
  if (( end_idx > ${#TISSUES[@]} )); then end_idx=${#TISSUES[@]}; fi
  echo "\n📦 Submitting chunk ${start_idx}-${end_idx} (of ${#TISSUES[@]})"

  # Submit this chunk
  declare -a SUB_IDS=()
  declare -a TISSUE_NAMES=()
  declare -a SAMPLE_COUNTS=()
  declare -a RUN_DIRS=()

  for ((i=start_idx; i<end_idx; i++)); do
    IFS=$'\t' read -r tissue_name sample_count json_path <<< "${TISSUES[$i]}"
    desc="GTEx ${tissue_name} (${sample_count}) chunked"
    bucket_folder="${BUCKET_PREFIX}/${tissue_name}"
    echo "🚀 Submitting $tissue_name with $sample_count samples -> $bucket_folder"

    # Run wrapper and capture output
    out=$(DOCKSTORE_METHOD="" workflows/splicing_analysis/terra_runs/dockstore_run.sh \
      -i "$json_path" -d "$desc" -b "$bucket_folder" 2>&1)

    # Extract run dir and submission id
    run_dir=$(echo "$out" | awk '/^- Run dir:/ {print $4}')
    job_url=$(echo "$out" | awk '/^- Job URL:/ {print $4}')
    sub_id=$(echo "$job_url" | sed 's#.*/job_history/##')

    if [[ -z "$sub_id" ]]; then
      echo "❌ Could not determine submission ID for $tissue_name" >&2
      echo "Output:\n$out" >&2
      exit 1
    fi

    SUB_IDS+=("$sub_id")
    TISSUE_NAMES+=("$tissue_name")
    SAMPLE_COUNTS+=("$sample_count")
    RUN_DIRS+=("$run_dir")

    # Initial ledger entry
    printf "%s,%s,%s,%s,%s,%s,%s,%s\n" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tissue_name" "$sample_count" "$sub_id" "$job_url" "Submitted" "0.00" "$run_dir" \
      >> "$LEDGER"

    sleep 2
  done

  echo "⏳ Waiting for chunk to finish..."
  # Poll until all submissions in the chunk are terminal
  while true; do
    all_done=1
    for ((k=0; k<${#SUB_IDS[@]}; k++)); do
      sid=${SUB_IDS[$k]}
      tname=${TISSUE_NAMES[$k]}
      scount=${SAMPLE_COUNTS[$k]}
      status_json=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        "https://api.firecloud.org/api/workspaces/${WORKSPACE_PROJECT}/${WORKSPACE_NAME}/submissions/$sid")
      wstatus=$(echo "$status_json" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
w=j.get('workflows',[{}])[0]
print(w.get('status','UNKNOWN'))
PY
)
      wcost=$(echo "$status_json" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
w=j.get('workflows',[{}])[0]
print(w.get('cost',0))
PY
)
      case "$wstatus" in
        Succeeded|Failed|Aborted)
          # Update ledger line (append a new line reflecting terminal state)
          job_url="https://app.terra.bio/#workspaces/${WORKSPACE_PROJECT}/${WORKSPACE_NAME}/job_history/${sid}"
          printf "%s,%s,%s,%s,%s,%s,%s,%s\n" \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tname" "$scount" "$sid" "$job_url" "$wstatus" "$wcost" "${RUN_DIRS[$k]}" \
            >> "$LEDGER"
          : ;;
        *)
          all_done=0 ;;
      esac
    done
    if (( all_done == 1 )); then break; fi
    echo "... still running; sleeping $PAUSE_SECONDS s"
    sleep "$PAUSE_SECONDS"
  done

  # Stop on any failure to avoid overpay
  any_failed=0
  for sid in "${SUB_IDS[@]}"; do
    st=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
      "https://api.firecloud.org/api/workspaces/${WORKSPACE_PROJECT}/${WORKSPACE_NAME}/submissions/$sid" |
      python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
w=j.get('workflows',[{}])[0]
print(w.get('status','UNKNOWN'))
PY
)
    if [[ "$st" == "Failed" || "$st" == "Aborted" ]]; then any_failed=1; fi
  done
  if (( any_failed == 1 )); then
    echo "❌ A submission in chunk ${start_idx}-${end_idx} failed. Stopping to avoid overpay. See $LEDGER."
    exit 1
  fi

  echo "✅ Chunk ${start_idx}-${end_idx} finished successfully. Proceeding to next."
  start_idx=$end_idx

done

echo "🎉 All tissues submitted in chunks. Ledger: $LEDGER"
