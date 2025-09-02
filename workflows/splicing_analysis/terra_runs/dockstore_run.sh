#!/bin/bash
# Dockstore/Methods-run wrapper with per-run tracking
# - Submits a Terra workflow using either a Dockstore method ID or Methods Repo reference
# - Cleans input JSON of known non-WDL keys (e.g., _validation_metadata)
# - Persists run metadata and provides per-run monitor and collect helpers
#
# Usage examples:
#   DOCKSTORE_METHOD="#workflow/github.com/NDeeSeee/altanalyze2_snaf/splicing_analysis:v1.6.39" \
#   workflows/splicing_analysis/terra_runs/dockstore_run.sh \
#     -i workflows/splicing_analysis/inputs/gtex_v10_validated/cervix_uteri_55.json \
#     -d "GTEx cervix 55 via Dockstore"
#
#   # Or fallback to Methods Repo (if DOCKSTORE_METHOD unset)
#   workflows/splicing_analysis/terra_runs/dockstore_run.sh \
#     -i workflows/splicing_analysis/inputs/gtex_v10_validated/cervix_uteri_55.json
#
set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: dockstore_run.sh -i INPUT_JSON [-d DESCRIPTION] [-b BUCKET_FOLDER] [-m METHOD] [-c CONFIG] [-p PROJECT] [-w WORKSPACE]

Options:
  -i INPUT_JSON       Path to WDL input JSON (required)
  -d DESCRIPTION      Freeform run description (default: auto)
  -b BUCKET_FOLDER    Subdirectory in workspace bucket (default: auto)
  -m METHOD           Method identifier to use:
                      - Dockstore GA4GH/TRS (e.g., #workflow/github.com/org/repo/path:version)
                      - Methods Repo (e.g., Namespace/method/1)
                      If omitted, uses $DOCKSTORE_METHOD or falls back to Methods Repo via env.
  -c CONFIG           Use existing Terra workspace configuration (e.g., altanalyze_splicing_analysis)
                      This triggers fissfc config_start instead of alto terra run
  -p PROJECT          Terra billing project/namespace (default from env)
  -w WORKSPACE        Terra workspace name (default from env)
  -h                  Show this help

Environment:
DOCKSTORE_METHOD    If set, used as default method (e.g., #workflow/github.com/NDeeSeee/altanalyze2_snaf/splicing_analysis:v1.6.39)
  WORKSPACE_PROJECT   Default project/namespace for Terra
  WORKSPACE_NAME      Default workspace name for Terra
  NAMESPACE           Default Methods Repo namespace (for fallback method)

Artifacts:
  - Creates runs/<RUN_ID>/ with metadata.json, cleaned_input.json, monitor.sh, collect.sh
  - Appends to runs/submissions.csv for consolidated tracking
EOF
}

INPUT_JSON=""
DESCRIPTION=""
BUCKET_FOLDER=""
OVERRIDE_METHOD=""
OVERRIDE_CONFIG=""
OVERRIDE_PROJECT=""
OVERRIDE_WORKSPACE=""

while getopts ":i:d:b:m:c:p:w:h" opt; do
  case $opt in
    i) INPUT_JSON="$OPTARG" ;;
    d) DESCRIPTION="$OPTARG" ;;
    b) BUCKET_FOLDER="$OPTARG" ;;
    m) OVERRIDE_METHOD="$OPTARG" ;;
    c) OVERRIDE_CONFIG="$OPTARG" ;;
    p) OVERRIDE_PROJECT="$OPTARG" ;;
    w) OVERRIDE_WORKSPACE="$OPTARG" ;;
    h) print_help; exit 0 ;;
    :) echo "Missing argument for -$OPTARG" >&2; exit 2 ;;
    \?) echo "Unknown option -$OPTARG" >&2; print_help; exit 2 ;;
  esac
done

if [[ -z "${INPUT_JSON}" ]]; then
  echo "❌ -i INPUT_JSON is required" >&2
  print_help
  exit 2
fi

# Load env (global preferred, then local)
for ENV_FILE in workflows/terra/env.sh workflows/splicing_analysis/terra_runs/env.sh; do
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    break
  fi
done

WORKSPACE_PROJECT="${OVERRIDE_PROJECT:-${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}}"
WORKSPACE_NAME="${OVERRIDE_WORKSPACE:-${WORKSPACE_NAME:-AltAnalyze3_SNAF}}"
METHOD="${OVERRIDE_METHOD:-${DOCKSTORE_METHOD:-}}"
CONFIG_NAME="${OVERRIDE_CONFIG:-}" 

# Fallback to Methods Repo reference when Dockstore method not provided
if [[ -n "$CONFIG_NAME" ]]; then
  : # config-based submit path; METHOD may be empty
elif [[ -z "$METHOD" ]]; then
  SPLICING_METHOD_VERSION="${SPLICING_METHOD_VERSION:-1}"
  NAMESPACE="${NAMESPACE:-AltAnalyze3_SNAF}"
  METHOD="${NAMESPACE}/splicing_analysis/${SPLICING_METHOD_VERSION}"
fi

# Prepare run directory (will be renamed after we infer tissue/count)
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="workflows/splicing_analysis/terra_runs/runs/${RUN_ID}"
mkdir -p "$RUN_DIR"

# Decide input to submit: prefer original if already clean; otherwise, write a cleaned copy
CLEAN_INPUT="$INPUT_JSON"
NEED_CLEAN=$(python3 - "$INPUT_JSON" "$RUN_DIR/cleaned_input.json" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    data = json.load(f)
changed = False
for k in ["_validation_metadata", "SplicingAnalysis.bam_to_bed_disk_space", "SplicingAnalysis.junction_analysis_disk_space"]:
    if k in data:
        data.pop(k, None)
        changed = True
# Ensure optional keys exist to avoid downstream surprises
if 'SplicingAnalysis.extra_bed_files' not in data:
    data['SplicingAnalysis.extra_bed_files'] = []
    changed = True
if 'SplicingAnalysis.docker_image' not in data:
    data['SplicingAnalysis.docker_image'] = "ndeeseee/altanalyze:v1.6.39"
    changed = True
if changed:
    with open(dst, 'w') as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write('\n')
    print(dst)
PY
)
if [[ -n "$NEED_CLEAN" ]]; then
  CLEAN_INPUT="$NEED_CLEAN"
fi

# Default description and bucket folder, enriched with tissue metadata
# Also derive a human-friendly run directory suffix and rename the run dir accordingly
base=$(basename "$INPUT_JSON")
tissue=${base%.*}
samples=$(echo "$tissue" | awk -F'_' '{print $NF}')
tissue_name=$(echo "$tissue" | sed 's/_[0-9][0-9]*$//')
if [[ -z "$DESCRIPTION" ]]; then
  DESCRIPTION="GTEx v10 | ${tissue_name} | ${samples} samples | ${METHOD}"
fi
if [[ -z "$BUCKET_FOLDER" ]]; then
  BUCKET_FOLDER="gtex_v10/${tissue_name}/${samples}_samples/${RUN_ID}"
fi

# Rename run directory to include tissue and sample count (for discoverability)
safe_label=$(echo "${tissue_name}__${samples}" | tr ' /' '__' | tr -cd '[:alnum:]_.-')
NEW_RUN_DIR="workflows/splicing_analysis/terra_runs/runs/${RUN_ID}__${safe_label}"
if [[ "$RUN_DIR" != "$NEW_RUN_DIR" ]]; then
  mv "$RUN_DIR" "$NEW_RUN_DIR"
  RUN_DIR="$NEW_RUN_DIR"
fi

# Submit
WORKSPACE_REF="${WORKSPACE_PROJECT}/${WORKSPACE_NAME}"
echo "🧾 Workspace: $WORKSPACE_REF"
echo "📦 Bucket folder: $BUCKET_FOLDER"

SUBMISSION_ID=""
JOB_URL=""

if [[ -n "$CONFIG_NAME" ]]; then
  echo "🚀 Submitting Terra configuration: $CONFIG_NAME"
  set +e
  # Fire off submission using existing workspace config, with description
  CF_OUT=$(fissfc config_start -w "$WORKSPACE_NAME" -p "$WORKSPACE_PROJECT" -c "$CONFIG_NAME" -n "${NAMESPACE:-AltAnalyze3_SNAF}" -u "$DESCRIPTION" 2>&1)
  STATUS=$?
  set -e
  if [[ $STATUS -ne 0 ]]; then
    echo "❌ Config submission failed" >&2
    echo "$CF_OUT" | tee "$RUN_DIR/error.txt" >&2
    exit 1
  fi
  # Grab newest submission id
  SUBMISSION_ID=$(fissfc monitor -w "$WORKSPACE_NAME" -p "$WORKSPACE_PROJECT" 2>/dev/null | tail -n +2 | head -1 | cut -f7)
  JOB_URL="https://app.terra.bio/#workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME/job_history/$SUBMISSION_ID"
  echo "$JOB_URL" | tee "$RUN_DIR/job_url.txt"
else
  echo "🚀 Submitting method: $METHOD"
  # Prefer Rawls submit to attach user comment and toggles
  RAWLS_OUT=$(workflows/splicing_analysis/terra_runs/terra_rawls_submit.sh \
    -i "$CLEAN_INPUT" \
    -m "$METHOD" \
    -d "$DESCRIPTION" \
    -p "$WORKSPACE_PROJECT" \
    -w "$WORKSPACE_NAME" 2>&1) || {
      echo "❌ Rawls submission failed" >&2
      echo "$RAWLS_OUT" | tee "$RUN_DIR/error.txt" >&2
      exit 1
    }
  echo "$RAWLS_OUT" | tee "$RUN_DIR/job_url.txt"
  JOB_URL=$(echo "$RAWLS_OUT" | grep -o "https://app.terra.bio/#workspaces/[^"]*")
  SUBMISSION_ID=$(echo "$JOB_URL" | sed 's/.*job_history\///')
fi

# Persist run metadata
cat > "$RUN_DIR/metadata.json" <<'EOF'
{
  "run_id": "$RUN_ID",
  "submitted_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "workspace_project": "$WORKSPACE_PROJECT",
  "workspace_name": "$WORKSPACE_NAME",
  "method": "${CONFIG_NAME:+terra_config:${NAMESPACE:-AltAnalyze3_SNAF}/$CONFIG_NAME}${CONFIG_NAME:+}${CONFIG_NAME:++}${CONFIG_NAME:="$METHOD"}",
  "input_json": "$(realpath "$INPUT_JSON" 2>/dev/null || echo "$INPUT_JSON")",
  "cleaned_input": "$(realpath "$CLEAN_INPUT" 2>/dev/null || echo "$CLEAN_INPUT")",
  "bucket_folder": "$BUCKET_FOLDER",
  "submission_id": "$SUBMISSION_ID",
  "job_url": "$JOB_URL",
  "description": "$DESCRIPTION",
  "tissue": "${tissue_name}",
  "num_samples": ${samples}
}
EOF

# Append submissions CSV
CSV="workflows/splicing_analysis/terra_runs/runs/submissions.csv"
if [[ ! -f "$CSV" ]]; then
  echo "timestamp,run_id,method,workspace,submission_id,job_url,input_json,bucket_folder,description" > "$CSV"
fi
printf "%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RUN_ID" "$METHOD" "$WORKSPACE_REF" "$SUBMISSION_ID" "$JOB_URL" \
  "${INPUT_JSON}" "$BUCKET_FOLDER" "${DESCRIPTION//,/;}" >> "$CSV"

# Create per-run monitor helper (polls every 10s)
cat > "$RUN_DIR/monitor.sh" <<'MON'
#!/bin/bash
set -euo pipefail
RUN_DIR="$(cd "$(dirname "$0")" && pwd)"
META="$RUN_DIR/metadata.json"
SUB_ID=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["submission_id"])' "$META")
WP=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["workspace_project"])' "$META")
WN=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["workspace_name"])' "$META")
LOG="$RUN_DIR/status.log"

while true; do
  printf "[%s] " "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$LOG"
  curl -s -X GET "https://api.firecloud.org/api/workspaces/$WP/$WN/submissions/$SUB_ID" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" | \
    python3 - <<'PY' | tee -a "$LOG"
import sys,json
j=json.load(sys.stdin)
w=j.get('workflows',[{}])[0]
status=w.get('status','UNKNOWN')
cost=w.get('cost','$0.00')
submitted=j.get('submissionDate','?')
print("status=%s cost=%s submitted=%s" % (status, cost, submitted))
PY
  echo "" >> "$LOG"
  sleep 10
  clear
  tail -n 10 "$LOG" || true
  printf '%s\n' '(Ctrl+C to stop)'
  sleep 0
  # Next loop
  sleep 10
done
MON
chmod +x "$RUN_DIR/monitor.sh"

# Create per-run collector helper
cat > "$RUN_DIR/collect.sh" <<'COL'
#!/bin/bash
set -euo pipefail
RUN_DIR="$(cd "$(dirname "$0")" && pwd)"
META="$RUN_DIR/metadata.json"
SUB_ID=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["submission_id"])' "$META")
WP=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["workspace_project"])' "$META")
WN=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["workspace_name"])' "$META")
WB=$(fissfc space_info -w "$WN" -p "$WP" 2>/dev/null | awk '/bucketName/ {print $2}' || true)
WB=${WB:-$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("workspace_bucket",""))' "$META" 2>/dev/null || echo "")}
OUT="$RUN_DIR/artifacts"
mkdir -p "$OUT"

if [[ -z "$WB" ]]; then
  echo "⚠️ Could not detect workspace bucket; set WORKSPACE_BUCKET in env and re-run." >&2
  exit 1
fi

echo "📥 Downloading logs and outputs to $OUT ..."
(gsutil -m cp -r "gs://$WB/submissions/$SUB_ID/workflow.logs/" "$OUT/" || true)
(gsutil -m cp -r "gs://$WB/submissions/$SUB_ID/SplicingAnalysis/" "$OUT/" || true)

# Optional: aggregate monitoring metrics if available
if [[ -d "$OUT/SplicingAnalysis" ]]; then
  echo "🧮 Aggregating monitoring metrics..."
  AGG="$RUN_DIR/monitoring_summaries"
  mkdir -p "$AGG"
  # Find all monitoring dirs under tasks and aggregate per-dir
  python3 - <<'PY' "$OUT" "$AGG"
import sys, subprocess, pathlib
base, out = map(pathlib.Path, sys.argv[1:3])
mons = sorted(base.glob('SplicingAnalysis/**/monitoring'))
for m in mons:
    try:
        dest = out / m.parent.name
        dest.mkdir(parents=True, exist_ok=True)
        subprocess.run(['python3','containers/resource-monitor/aggregate.py', str(m), '--out', str(dest)], check=False)
    except Exception:
        pass
print("Aggregated %d monitoring dirs -> %s" % (len(mons), out))
PY
fi

echo "✅ Done"
COL
chmod +x "$RUN_DIR/collect.sh"

# Create per-run log watcher (polls workflow.log every 10s)
cat > "$RUN_DIR/watch_logs.sh" <<'WATCH'
#!/bin/bash
set -euo pipefail
RUN_DIR="$(cd "$(dirname "$0")" && pwd)"
META="$RUN_DIR/metadata.json"
SUB_ID=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["submission_id"])' "$META")
WP=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["workspace_project"])' "$META")
WN=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["workspace_name"])' "$META")
WB=$(fissfc space_info -w "$WN" -p "$WP" 2>/dev/null | awk '/bucketName/ {print $2}' || true)
if [[ -z "$WB" ]]; then echo "Cannot detect workspace bucket" >&2; exit 1; fi
echo "Watching workflow logs for submission: $SUB_ID"
while true; do
  LOG=$(gsutil ls "gs://$WB/submissions/$SUB_ID/workflow.logs/workflow.*.log" 2>/dev/null | head -1)
  if [[ -n "$LOG" ]]; then
    echo "===== $(date -u +%H:%M:%S) $LOG ====="
    gsutil cat "$LOG" 2>/dev/null | tail -n 40 || true
  else
    printf '%s\n' '(log not yet available)'
  fi
  sleep 10
  clear
done
WATCH
chmod +x "$RUN_DIR/watch_logs.sh"

# Create top-level helper for listing submissions
LIST_HELPER="workflows/splicing_analysis/terra_runs/list_runs.sh"
if [[ ! -f "$LIST_HELPER" ]]; then
cat > "$LIST_HELPER" <<'LIST'
#!/bin/bash
set -euo pipefail
CSV="workflows/splicing_analysis/terra_runs/runs/submissions.csv"
if [[ ! -f "$CSV" ]]; then
  echo "No runs recorded yet."; exit 0
fi
column -s, -t "$CSV" | less -S
LIST
  chmod +x "$LIST_HELPER"
fi

# Echo final pointers
cat <<'END'

🎉 Submission created
- Run dir: $RUN_DIR
- Job URL: $JOB_URL
- Monitor: $RUN_DIR/monitor.sh
- Collect: $RUN_DIR/collect.sh
- Watch logs: $RUN_DIR/watch_logs.sh
- All runs: workflows/splicing_analysis/terra_runs/runs/submissions.csv
END
