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

export RUN_ID

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_help() {
  cat <<'EOF'
Usage: dockstore_run.sh -i INPUT_JSON [-d DESCRIPTION] [-b BUCKET_FOLDER] [-m METHOD] [-c CONFIG] [-p PROJECT] [-w WORKSPACE] [-C MAX_COST_USD] [-R MEMORY_RETRY_MULTIPLIER] [-e ENTITY_NAME] [-E ENTITY_TYPE]

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
  -C MAX_COST_USD     Abort before submit if estimated cost exceeds this USD
  -R MEMORY_RETRY_MULTIPLIER  Terra retry memory multiplier (e.g., 1.5)
  -e ENTITY_NAME      Terra entity to run against (e.g., pancreas_samples)
  -E ENTITY_TYPE      Terra entity type (default: sample_set when -e is used)
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
MAX_COST_USD=""
MEMORY_RETRY_MULTIPLIER=""
ENTITY_NAME=""
ENTITY_TYPE=""

while getopts ":i:d:b:m:c:p:w:C:R:e:E:h" opt; do
  case $opt in
    i) INPUT_JSON="$OPTARG" ;;
    d) DESCRIPTION="$OPTARG" ;;
    b) BUCKET_FOLDER="$OPTARG" ;;
    m) OVERRIDE_METHOD="$OPTARG" ;;
    c) OVERRIDE_CONFIG="$OPTARG" ;;
    p) OVERRIDE_PROJECT="$OPTARG" ;;
    w) OVERRIDE_WORKSPACE="$OPTARG" ;;
    C) MAX_COST_USD="$OPTARG" ;;
    R) MEMORY_RETRY_MULTIPLIER="$OPTARG" ;;
    e) ENTITY_NAME="$OPTARG" ;;
    E) ENTITY_TYPE="$OPTARG" ;;
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

# If a config name is provided but no method, and DOCKSTORE_METHOD isn't set, use default method
if [[ -n "$CONFIG_NAME" && -z "$METHOD" ]]; then
  SPLICING_METHOD_VERSION="${SPLICING_METHOD_VERSION:-8}"
  NAMESPACE="${NAMESPACE:-AltAnalyze3_SNAF}"
  METHOD="${NAMESPACE}/splicing_analysis/${SPLICING_METHOD_VERSION}"
fi

# Fallback to Methods Repo reference when Dockstore method not provided
if [[ -n "$CONFIG_NAME" ]]; then
  : # config-based submit path; METHOD may be empty
elif [[ -z "$METHOD" ]]; then
  SPLICING_METHOD_VERSION="${SPLICING_METHOD_VERSION:-8}"
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

# Extract sample count robustly: try filename parsing first, fallback to actual counting
samples=$(echo "$tissue" | awk -F'_' '{print $NF}')
if ! [[ "$samples" =~ ^[0-9]+$ ]]; then
  # Filename doesn't end with numeric count, extract from input JSON
  samples=$(python3 -c "import json, sys; data=json.load(open(sys.argv[1])); print(len(data.get('SplicingAnalysis.bam_files', [])))" "$CLEAN_INPUT" 2>/dev/null || echo "unknown")
  tissue_name="$tissue"
else
  # Numeric sample count found, derive tissue name by removing trailing number
  tissue_name=$(echo "$tissue" | sed 's/_[0-9][0-9]*$//')
fi

# Default entity information for sample_set runs when not explicitly provided.
if [[ -z "$ENTITY_NAME" && -n "$tissue_name" ]]; then
  ENTITY_NAME="${tissue_name}_samples"
fi
if [[ -n "$ENTITY_NAME" && -z "$ENTITY_TYPE" ]]; then
  ENTITY_TYPE="sample_set"
fi
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

# Optional pre-submit cost gate based on historical cost-per-sample
EST_JSON=$(python3 - <<'PY' "$CLEAN_INPUT"
import sys, json, glob, re, statistics, pathlib
input_path=sys.argv[1]
data=json.load(open(input_path))
num_samples=len(data.get('SplicingAnalysis.bam_files') or [])
run_dir=pathlib.Path('workflows/splicing_analysis/terra_runs/runs')
cps=[]
for p in run_dir.glob('*/metadata.json'):
    try:
        m=json.load(open(p))
        cost=m.get('workflow_cost')
        n=m.get('num_samples') or 0
        if not cost or not n:
            continue
        if isinstance(cost, str):
            cost=float(re.sub(r'[^0-9\.]','', cost) or 0.0)
        else:
            cost=float(cost)
        # Defensive parsing: handle both numeric and string values for num_samples
        if isinstance(n, str):
            if n.isdigit():
                n=int(n)
            else:
                continue  # Skip non-numeric string values
        else:
            n=int(n)
        if n>0 and cost>0:
            cps.append(cost/n)
    except (ValueError, TypeError, KeyError) as e:
        # Skip metadata files with invalid or corrupted data
        continue
    except Exception:
        # Catch-all for other unexpected errors
        pass
default_cps=0.03
per_sample = (statistics.median(cps) if cps else default_cps)
base_overhead=0.10
est=base_overhead + per_sample*num_samples
print(json.dumps({
  'num_samples': num_samples,
  'per_sample_usd': round(per_sample, 4),
  'base_overhead_usd': round(base_overhead, 2),
  'estimated_usd': round(est, 2)
}))
PY
)
echo "$EST_JSON" > "$RUN_DIR/cost_estimate.json"
if [[ -n "$MAX_COST_USD" ]]; then
  EXCEEDS=$(python3 - <<'PY' "$EST_JSON" "$MAX_COST_USD"
import sys, json
j=json.loads(sys.argv[1]); mx=float(sys.argv[2])
print(1 if float(j.get('estimated_usd', 0))>mx else 0)
PY
)
  if [[ "$EXCEEDS" == "1" ]]; then
    EST_COST=$(python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["estimated_usd"])' <<< "$EST_JSON")
    echo "❌ Estimated cost $EST_COST exceeds threshold $MAX_COST_USD. Aborting submit." >&2
    echo "Adjust with -C to override, or reduce inputs. See $RUN_DIR/cost_estimate.json"
    exit 3
  fi
fi

# Submit
WORKSPACE_REF="${WORKSPACE_PROJECT}/${WORKSPACE_NAME}"
echo "🧾 Workspace: $WORKSPACE_REF"
echo "📦 Bucket folder: $BUCKET_FOLDER"

SUBMISSION_ID=""
JOB_URL=""

if [[ -n "$CONFIG_NAME" ]]; then
  echo "🚀 Submitting method: $METHOD (config: $CONFIG_NAME)"
  RAWLS_OUT=$("${SCRIPT_DIR}/terra_rawls_submit.sh" \
    -i "$CLEAN_INPUT" \
    -m "$METHOD" \
    -d "$DESCRIPTION" \
    -n "$CONFIG_NAME" \
    -p "$WORKSPACE_PROJECT" \
    -w "$WORKSPACE_NAME" \
    ${ENTITY_NAME:+-e "$ENTITY_NAME"} \
    ${ENTITY_TYPE:+-E "$ENTITY_TYPE"} \
    ${MAX_COST_USD:+-C "$MAX_COST_USD"} \
    ${MEMORY_RETRY_MULTIPLIER:+-R "$MEMORY_RETRY_MULTIPLIER"} 2>&1) || {
      echo "❌ Rawls submission failed" >&2
      echo "$RAWLS_OUT" | tee "$RUN_DIR/error.txt" >&2
      exit 1
    }
else
  echo "🚀 Submitting method: $METHOD"
  # Prefer Rawls submit to attach user comment and toggles
RAWLS_OUT=$("${SCRIPT_DIR}/terra_rawls_submit.sh" \
    -i "$CLEAN_INPUT" \
    -m "$METHOD" \
    -d "$DESCRIPTION" \
    -p "$WORKSPACE_PROJECT" \
    -w "$WORKSPACE_NAME" \
    ${ENTITY_NAME:+-e "$ENTITY_NAME"} \
    ${ENTITY_TYPE:+-E "$ENTITY_TYPE"} \
    ${MAX_COST_USD:+-C "$MAX_COST_USD"} \
    ${MEMORY_RETRY_MULTIPLIER:+-R "$MEMORY_RETRY_MULTIPLIER"} 2>&1) || {
      echo "❌ Rawls submission failed" >&2
      echo "$RAWLS_OUT" | tee "$RUN_DIR/error.txt" >&2
      exit 1
    }
  echo "$RAWLS_OUT" | tee "$RUN_DIR/job_url.txt"
  JOB_URL=$(echo "$RAWLS_OUT" | grep -o 'https://app.terra.bio/#workspaces/[^" ]*')
  SUBMISSION_ID=$(echo "$JOB_URL" | sed 's/.*job_history\///')
fi

# Persist run metadata
python3 - <<'PY' "$RUN_DIR/metadata.json" "$RUN_ID" "$WORKSPACE_PROJECT" "$WORKSPACE_NAME" "$CONFIG_NAME" "$METHOD" "$INPUT_JSON" "$CLEAN_INPUT" "$BUCKET_FOLDER" "$SUBMISSION_ID" "$JOB_URL" "$DESCRIPTION" "$tissue_name" "$samples" "$ENTITY_TYPE" "$ENTITY_NAME"
import datetime, json, pathlib, sys, os
(
    meta_path,
    run_id,
    workspace_project,
    workspace_name,
    config_name,
    method,
    input_json,
    cleaned_input,
    bucket_folder,
    submission_id,
    job_url,
    description,
    tissue_name,
    samples,
    entity_type,
    entity_name,
) = sys.argv[1:17]

def real_or_orig(path):
    try:
        return os.path.realpath(path)
    except OSError:
        return path

record = {
    "run_id": run_id,
    "submitted_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "workspace_project": workspace_project,
    "workspace_name": workspace_name,
    "method": f"terra_config:{os.environ.get('NAMESPACE', 'AltAnalyze3_SNAF')}/{config_name}" if config_name else method,
    "input_json": real_or_orig(input_json),
    "cleaned_input": real_or_orig(cleaned_input),
    "bucket_folder": bucket_folder,
    "submission_id": submission_id,
    "job_url": job_url,
    "description": description,
    "tissue": tissue_name,
    "num_samples": int(samples) if samples.isdigit() else samples,
}

if entity_name:
    record["entity"] = {
        "entity_type": entity_type or "sample_set",
        "entity_name": entity_name,
    }

pathlib.Path(meta_path).write_text(json.dumps(record, indent=2) + "\n")
PY

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
tac "$CSV" | column -s, -t | less -S
LIST
  chmod +x "$LIST_HELPER"
fi

# Echo final pointers (expand variables)
echo
echo "🎉 Submission created"
echo "- Run dir: $RUN_DIR"
echo "- Job URL: $JOB_URL"
echo "- Monitor: $RUN_DIR/monitor.sh"
echo "- Collect: $RUN_DIR/collect.sh"
echo "- Watch logs: $RUN_DIR/watch_logs.sh"
echo "- All runs: workflows/splicing_analysis/terra_runs/runs/submissions.csv"
if [[ -n "$MAX_COST_USD" ]]; then
  # Create an optional guard to auto-abort if cost exceeds threshold
  cat > "$RUN_DIR/abort_on_cost.sh" <<'ABORT'
#!/bin/bash
set -euo pipefail
if [[ $# -lt 1 ]]; then echo "Usage: $0 MAX_COST_USD" >&2; exit 2; fi
RUN_DIR="$(cd "$(dirname "$0")" && pwd)"
META="$RUN_DIR/metadata.json"
SUB_ID=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["submission_id"])' "$META")
WP=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["workspace_project"])' "$META")
WN=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["workspace_name"])' "$META")
MAX="$1"
echo "Guarding submission $SUB_ID up to $MAX USD"
while true; do
  COST=$(curl -s -X GET "https://api.firecloud.org/api/workspaces/$WP/$WN/submissions/$SUB_ID" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" | \
    python3 - <<'PY'
import sys, json, re
j=json.load(sys.stdin)
w=j.get('workflows',[{}])[0]
c=str(w.get('cost', '0'))
import re
print(re.sub(r'[^0-9\.]', '', c) or '0')
PY
  )
  python3 - "$COST" "$MAX" <<'PY'
import sys, time, subprocess
cur=float(sys.argv[1] or 0.0); mx=float(sys.argv[2])
if cur>mx:
    print(f"Aborting: current cost {cur} exceeds {mx}")
    sys.exit(42)
else:
    sys.exit(0)
PY
  status=$?
  if [[ $status -eq 42 ]]; then
    curl -s -X POST "https://api.firecloud.org/api/workspaces/$WP/$WN/submissions/$SUB_ID/abort" \
      -H "Authorization: Bearer $(gcloud auth print-access-token)" >/dev/null || true
    echo "Abort requested. Exiting guard."
    exit 0
  fi
  sleep 30
done
ABORT
  chmod +x "$RUN_DIR/abort_on_cost.sh"
  echo "- Abort-on-cost guard: $RUN_DIR/abort_on_cost.sh $MAX_COST_USD"
fi
