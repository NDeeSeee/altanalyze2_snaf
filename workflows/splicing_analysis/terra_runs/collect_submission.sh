#!/bin/bash
# Collect Terra logs and outputs for a given submission ID into the run dir
# Usage:
#   workflows/splicing_analysis/terra_runs/collect_submission.sh -s SUBMISSION_ID [-o OUT_DIR] [-p PROJECT] [-w WORKSPACE]
# If OUT_DIR not provided, it will resolve from runs/submissions.csv by matching SUBMISSION_ID,
# falling back to runs/<SUBMISSION_ID>
set -euo pipefail

SUB_ID=""
OUT_DIR=""
OVERRIDE_PROJECT=""
OVERRIDE_WORKSPACE=""

print_help() {
  cat <<'EOF'
Usage: collect_submission.sh -s SUBMISSION_ID [-o OUT_DIR] [-p PROJECT] [-w WORKSPACE]

Options:
  -s SUBMISSION_ID  Terra submission ID (required)
  -o OUT_DIR        Output directory (default: resolve from runs/submissions.csv)
  -p PROJECT        Terra billing project/namespace (default: from CSV or env)
  -w WORKSPACE      Terra workspace name (default: from CSV or env)
  -h                Show help
EOF
}

while getopts ":s:o:p:w:h" opt; do
  case $opt in
    s) SUB_ID="$OPTARG" ;;
    o) OUT_DIR="$OPTARG" ;;
    p) OVERRIDE_PROJECT="$OPTARG" ;;
    w) OVERRIDE_WORKSPACE="$OPTARG" ;;
    h) print_help; exit 0 ;;
    :) echo "Missing argument for -$OPTARG" >&2; exit 2 ;;
    \?) echo "Unknown option -$OPTARG" >&2; print_help; exit 2 ;;
  esac
done

if [[ -z "$SUB_ID" ]]; then
  echo "❌ -s SUBMISSION_ID is required" >&2
  exit 2
fi

CSV="workflows/splicing_analysis/terra_runs/runs/submissions.csv"
RUN_ID=""
WORKSPACE_REF=""
if [[ -f "$CSV" ]]; then
  # Extract run_id and workspace for this submission id
  read -r RUN_ID WORKSPACE_REF < <(python3 - <<PY "$CSV" "$SUB_ID"
import csv, sys
csv_path, sub = sys.argv[1:3]
run_id = ""
ws = ""
with open(csv_path, newline='') as f:
    r = csv.DictReader(f)
    for row in r:
        if row.get('submission_id','').strip() == sub.strip():
            run_id = row.get('run_id','').strip()
            ws = row.get('workspace','').strip()
            break
print(run_id or "", ws or "")
PY
  )
fi

# Resolve workspace project/name
if [[ -n "$WORKSPACE_REF" ]]; then
  WORKSPACE_PROJECT="${OVERRIDE_PROJECT:-${WORKSPACE_REF%%/*}}"
  WORKSPACE_NAME="${OVERRIDE_WORKSPACE:-${WORKSPACE_REF##*/}}"
else
  # Fall back to env or defaults
  source workflows/terra/env.sh 2>/dev/null || true
  WORKSPACE_PROJECT="${OVERRIDE_PROJECT:-${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}}"
  WORKSPACE_NAME="${OVERRIDE_WORKSPACE:-${WORKSPACE_NAME:-AltAnalyze3_SNAF}}"
fi

# Resolve OUT_DIR
if [[ -z "$OUT_DIR" ]]; then
  if [[ -n "$RUN_ID" ]]; then
    OUT_DIR="workflows/splicing_analysis/terra_runs/runs/$RUN_ID/artifacts"
  else
    OUT_DIR="workflows/splicing_analysis/terra_runs/runs/$SUB_ID/artifacts"
  fi
fi
mkdir -p "$OUT_DIR"

# Determine workspace bucket using the submission root (most reliable)
TOKEN=$(gcloud auth print-access-token)
SUB_JSON=$(curl -s -X GET "https://api.firecloud.org/api/workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME/submissions/$SUB_ID" \
  -H "Authorization: Bearer $TOKEN")
WORKSPACE_BUCKET="${WORKSPACE_BUCKET:-}"
if [[ -z "$WORKSPACE_BUCKET" ]]; then
  # Prefer submissionRoot from the submission object
  SUBMISSION_ROOT=$(echo "$SUB_JSON" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("submissionRoot",""))')
  if [[ -n "$SUBMISSION_ROOT" ]]; then
    # Extract bucket from gs://bucket/path
    WORKSPACE_BUCKET=$(python3 - <<'PY' "$SUBMISSION_ROOT"
import sys, urllib.parse
root = sys.argv[1]
if root.startswith('gs://'):
    bucket = root.split('/',3)[2]
    print(bucket)
else:
    print("")
PY
    )
  fi
fi
if [[ -z "$WORKSPACE_BUCKET" ]]; then
  # Fallback to workspace metadata
  WORKSPACE_BUCKET=$(curl -s -X GET "https://api.firecloud.org/api/workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME" \
    -H "Authorization: Bearer $TOKEN" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("workspace",{}).get("bucketName",""))')
fi
if [[ -z "$WORKSPACE_BUCKET" || "$WORKSPACE_BUCKET" == "SNAF" ]]; then
  echo "❌ Could not determine valid workspace bucket (got '$WORKSPACE_BUCKET')" >&2
  exit 1
fi

# Copy logs and outputs
echo "📥 Downloading workflow logs and outputs from gs://$WORKSPACE_BUCKET/submissions/$SUB_ID ..."
(
  gsutil -m cp -r "gs://$WORKSPACE_BUCKET/submissions/$SUB_ID/workflow.logs/" "$OUT_DIR/" 2>/dev/null || \
  gsutil cp -r "gs://$WORKSPACE_BUCKET/submissions/$SUB_ID/workflow.logs/" "$OUT_DIR/" 2>/dev/null || true
)
(
  gsutil -m cp -r "gs://$WORKSPACE_BUCKET/submissions/$SUB_ID/SplicingAnalysis/" "$OUT_DIR/" 2>/dev/null || \
  gsutil cp -r "gs://$WORKSPACE_BUCKET/submissions/$SUB_ID/SplicingAnalysis/" "$OUT_DIR/" 2>/dev/null || true
)

# Write metadata
JOB_URL="https://app.terra.bio/#workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME/job_history/$SUB_ID"
cat > "${OUT_DIR%/}/../metadata.json" <<EOF
{
  "submission_id": "$SUB_ID",
  "workspace_project": "$WORKSPACE_PROJECT",
  "workspace_name": "$WORKSPACE_NAME",
  "workspace_bucket": "$WORKSPACE_BUCKET",
  "job_url": "$JOB_URL"
}
EOF

echo "$JOB_URL" > "${OUT_DIR%/}/../job_url.txt"

echo "✅ Collected to $OUT_DIR"
