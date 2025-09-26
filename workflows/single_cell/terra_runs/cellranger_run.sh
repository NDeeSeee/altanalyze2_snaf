#!/bin/bash
# Cell Ranger preprocessing on Terra (Cumulus cellranger_workflow) via Altocumulus
# - Submits Broad Methods Repo workflow: cumulus/cellranger_workflow
# - Accepts a *simple* inputs JSON (unprefixed keys) or an already-prefixed one
# - Optionally takes a local sample sheet CSV; lets `alto` upload it
#
# Example:
#   workflows/single_cell/terra_runs/cellranger_run.sh \
#     -i workflows/single_cell/inputs/cellranger_inputs.json \
#     -m cumulus/cellranger_workflow/1.4.0 \
#     -W cellranger_workflow \
#     -d "10x PBMC cellranger count (introns=false)"

set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: cellranger_run.sh -i INPUTS_JSON [-S SAMPLE_SHEET_CSV] [-m METHOD_REF] [-W WORKFLOW_NAME] [-p PROJECT] [-w WORKSPACE] [-d DESCRIPTION]

Options:
  -i INPUTS_JSON       Path to inputs JSON. Accepts either:
                       (A) simple keys (input_csv_file, output_directory, run_mkfastq, …), or
                       (B) fully prefixed keys (cellranger_workflow.input_csv_file, …). (required)
  -S SAMPLE_SHEET_CSV  Optional local CSV; script will point input_csv_file to this local path
                       (Altocumulus will upload it and rewrite paths)
  -m METHOD_REF        Terra method, default: cumulus/cellranger_workflow
                       (pin snapshot as: cumulus/cellranger_workflow/<version>)
  -W WORKFLOW_NAME     Input prefix for WDL, default: cellranger_workflow
  -p PROJECT           Terra billing project/namespace (default from env)
  -w WORKSPACE         Terra workspace name (default from env)
  -d DESCRIPTION       Freeform run description (default: auto)
  -h                   Help

Notes / gotchas:
- Use `cellranger_workflow` for both the method and the JSON input prefix.  # required by Cumulus/Terra
- FASTQ-only mode: Flowcell=gs://<bucket>/<flowcell_fastq_folder>; one subfolder per Sample; Lane/Index not required; set run_mkfastq=false.
- Do NOT silently force include_introns; explicitly set it if desired.

EOF
}

INPUTS_JSON=""
SAMPLE_SHEET_CSV=""
METHOD_REF="cumulus/cellranger_workflow"
WORKFLOW_NAME="cellranger_workflow"
OVERRIDE_PROJECT=""
OVERRIDE_WORKSPACE=""
DESCRIPTION=""

while getopts ":i:S:m:W:p:w:d:h" opt; do
  case $opt in
    i) INPUTS_JSON="$OPTARG" ;;
    S) SAMPLE_SHEET_CSV="$OPTARG" ;;
    m) METHOD_REF="$OPTARG" ;;
    W) WORKFLOW_NAME="$OPTARG" ;;
    p) OVERRIDE_PROJECT="$OPTARG" ;;
    w) OVERRIDE_WORKSPACE="$OPTARG" ;;
    d) DESCRIPTION="$OPTARG" ;;
    h) print_help; exit 0 ;;
    :) echo "Missing argument for -$OPTARG" >&2; exit 2 ;;
    \?) echo "Unknown option -$OPTARG" >&2; print_help; exit 2 ;;
  esac
done

if [[ -z "$INPUTS_JSON" ]]; then
  echo "❌ -i INPUTS_JSON is required" >&2; print_help; exit 2
fi

command -v alto >/dev/null 2>&1 || { echo "❌ 'alto' not found in PATH. pip install altocumulus" >&2; exit 2; }

# Load env if present
for ENV_FILE in workflows/terra/env.sh workflows/single_cell/terra_runs/env.sh; do
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"; break
  fi
done

WORKSPACE_PROJECT="${OVERRIDE_PROJECT:-${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}}"
WORKSPACE_NAME="${OVERRIDE_WORKSPACE:-${WORKSPACE_NAME:-AltAnalyze3_SNAF}}"
WORKSPACE_REF="$WORKSPACE_PROJECT/$WORKSPACE_NAME"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="workflows/single_cell/terra_runs/runs/${RUN_ID}"
mkdir -p "$RUN_DIR"

# If a local sample sheet is provided, point inputs to it (let alto upload it)
if [[ -n "$SAMPLE_SHEET_CSV" ]]; then
  python3 - "$INPUTS_JSON" "$RUN_DIR/input_simple.json" "$SAMPLE_SHEET_CSV" <<'PY'
import json, sys, os
src, dst, csv_local = sys.argv[1:4]
with open(src) as f:
    d=json.load(f)
# Prefer local CSV path; alto will upload & rewrite
d['input_csv_file']=os.path.abspath(csv_local)
# If run_mkfastq is not specified, default to False for FASTQ-only case
d.setdefault('run_mkfastq', False)
with open(dst,'w') as f:
    json.dump(d,f,indent=2)
PY
  INPUTS_JSON="$RUN_DIR/input_simple.json"
fi

# Build a prefixed WDL inputs JSON *unless* already prefixed
PREFIXED_JSON="$RUN_DIR/prefixed_inputs.json"
python3 - "$INPUTS_JSON" "$WORKFLOW_NAME" "$PREFIXED_JSON" <<'PY'
import json, sys, os
src, wf, dst = sys.argv[1:4]
with open(src) as f:
    d=json.load(f)

# Minimal validation
required_simple = {'input_csv_file','output_directory'}
if not any('.' in k for k in d):
    # Simple form: ensure minimal keys exist
    missing = [k for k in ['input_csv_file','output_directory'] if k not in d]
    if missing:
        raise SystemExit(f"Inputs JSON missing required key(s): {missing}")
    d.setdefault('run_mkfastq', False)  # safe default for FASTQ-only runs
    # DO NOT override include_introns; pass through if present

    out = {f"{wf}.{k}": v for k, v in d.items()}
else:
    # Already-prefixed form: pass through as-is
    out = d

with open(dst,'w') as f:
    json.dump(out,f,indent=2)
print(dst)
PY

# Description (count samples if we can)
if [[ -z "$DESCRIPTION" ]]; then
  if [[ -n "$SAMPLE_SHEET_CSV" && -f "$SAMPLE_SHEET_CSV" ]]; then
    NSAMPLES=$(awk 'NR>1 && $0!~(/^#|^$/){c++} END{print c+0}' "$SAMPLE_SHEET_CSV")
  else
    NSAMPLES="unknown"
  fi
  DESCRIPTION="Cell Ranger preprocessing | ${METHOD_REF} | samples=${NSAMPLES}"
fi

echo "🚀 Submitting $METHOD_REF to Terra workspace $WORKSPACE_REF"
set -x
alto terra run \
  -m "$METHOD_REF" \
  -w "$WORKSPACE_REF" \
  -i "$PREFIXED_JSON" \
  --bucket-folder "cellranger/${RUN_ID}" \
  -o "$RUN_DIR/inputs_updated.json" \
  > "$RUN_DIR/submission_output.txt" 2>&1
set +x

STATUS=$?
if [[ $STATUS -ne 0 ]]; then
  echo "❌ Submission failed; see $RUN_DIR/submission_output.txt" >&2
  exit 1
fi

JOB_URL=$(grep -Eo 'https://app\.terra\.bio/[^[:space:]]+' "$RUN_DIR/submission_output.txt" | head -1 || true)
cat > "$RUN_DIR/metadata.json" <<EOF
{
  "run_id": "$RUN_ID",
  "submitted_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "workspace_project": "$WORKSPACE_PROJECT",
  "workspace_name": "$WORKSPACE_NAME",
  "method": "$METHOD_REF",
  "workflow_name": "$WORKFLOW_NAME",
  "inputs_source": "$(realpath "$INPUTS_JSON" 2>/dev/null || echo "$INPUTS_JSON")",
  "inputs_prefixed": "$(realpath "$PREFIXED_JSON" 2>/dev/null || echo "$PREFIXED_JSON")",
  "inputs_updated": "$(realpath "$RUN_DIR/inputs_updated.json" 2>/dev/null || echo "$RUN_DIR/inputs_updated.json")",
  "job_url": "$JOB_URL",
  "description": "$DESCRIPTION"
}
EOF

echo "✅ Submitted. Metadata: $RUN_DIR/metadata.json"
[ -n "$JOB_URL" ] && echo "🔗 $JOB_URL" | tee "$RUN_DIR/job_url.txt" || true