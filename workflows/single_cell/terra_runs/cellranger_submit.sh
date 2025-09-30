#!/bin/bash
# Single-cell Cell Ranger submission script
# Uses terra_rawls_submit.sh but tracks runs in single_cell/terra_runs/runs/
#
# Usage:
#   workflows/single_cell/terra_runs/cellranger_submit.sh \
#     -i workflows/single_cell/inputs/cellranger_count_sample1.json \
#     -m cumulus/cellranger_count/10 \
#     -d "Cell Ranger count sample1"

set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: cellranger_submit.sh -i INPUT_JSON -m METHOD_REF -d DESCRIPTION

Single-cell Cell Ranger submission with proper run tracking

Options:
  -i INPUT_JSON       Path to Cell Ranger input JSON (required)
  -m METHOD_REF       Terra method reference (required, e.g., cumulus/cellranger_count/10)
  -d DESCRIPTION       Run description (required)
  -p PROJECT          Terra project (default from env)
  -w WORKSPACE         Terra workspace (default from env)
  -h                   Show help

Examples:
  cellranger_submit.sh -i inputs/cellranger_count_sample1.json -m cumulus/cellranger_count/10 -d "Sample 1"
  cellranger_submit.sh -i inputs/cellranger_count_sample2.json -m cumulus/cellranger_count/10 -d "Sample 2"
EOF
}

INPUT_JSON=""
METHOD_REF=""
DESCRIPTION=""
OVERRIDE_PROJECT=""
OVERRIDE_WORKSPACE=""

while getopts ":i:m:d:p:w:h" opt; do
  case $opt in
    i) INPUT_JSON="$OPTARG" ;;
    m) METHOD_REF="$OPTARG" ;;
    d) DESCRIPTION="$OPTARG" ;;
    p) OVERRIDE_PROJECT="$OPTARG" ;;
    w) OVERRIDE_WORKSPACE="$OPTARG" ;;
    h) print_help; exit 0 ;;
    :) echo "Missing argument for -$OPTARG" >&2; exit 2 ;;
    \?) echo "Unknown option -$OPTARG" >&2; print_help; exit 2 ;;
  esac
done

if [[ -z "$INPUT_JSON" || -z "$METHOD_REF" || -z "$DESCRIPTION" ]]; then
  echo "❌ -i, -m, and -d are required" >&2
  print_help
  exit 2
fi

# Load environment
for ENV_FILE in workflows/terra/env.sh; do
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    break
  fi
done

WORKSPACE_PROJECT="${OVERRIDE_PROJECT:-${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}}"
WORKSPACE_NAME="${OVERRIDE_WORKSPACE:-${WORKSPACE_NAME:-AltAnalyze3_SNAF}}"

# Create run tracking directory
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="workflows/single_cell/terra_runs/runs/${RUN_ID}"
mkdir -p "$RUN_DIR"

# Copy input JSON to run directory
cp "$INPUT_JSON" "$RUN_DIR/input.json"

echo "🚀 Submitting Cell Ranger workflow..."
echo "   Method: $METHOD_REF"
echo "   Workspace: $WORKSPACE_PROJECT/$WORKSPACE_NAME"
echo "   Run ID: $RUN_ID"
echo "   Run directory: $RUN_DIR"

# Submit using terra_rawls_submit.sh
workflows/splicing_analysis/terra_runs/terra_rawls_submit.sh \
  -i "$INPUT_JSON" \
  -m "$METHOD_REF" \
  -d "$DESCRIPTION" \
  -p "$WORKSPACE_PROJECT" \
  -w "$WORKSPACE_NAME" \
  > "$RUN_DIR/submission_output.txt" 2>&1

SUBMISSION_STATUS=$?

if [[ $SUBMISSION_STATUS -eq 0 ]]; then
  echo "✅ Cell Ranger workflow submitted successfully!"
  
  # Extract submission ID from output
  SUBMISSION_ID=$(grep -o 'submission-[a-f0-9-]*' "$RUN_DIR/submission_output.txt" | head -1 || echo "unknown")
  JOB_URL="https://app.terra.bio/#workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME/job_history/$SUBMISSION_ID"
  
  echo "📊 Submission ID: $SUBMISSION_ID"
  echo "🔗 Job URL: $JOB_URL"
  
  # Save metadata
  cat > "$RUN_DIR/metadata.json" <<EOF
{
  "run_id": "$RUN_ID",
  "submitted_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "workspace_project": "$WORKSPACE_PROJECT",
  "workspace_name": "$WORKSPACE_NAME",
  "method": "$METHOD_REF",
  "input_json": "$(realpath "$INPUT_JSON" 2>/dev/null || echo "$INPUT_JSON")",
  "submission_id": "$SUBMISSION_ID",
  "job_url": "$JOB_URL",
  "description": "$DESCRIPTION",
  "workflow_type": "single_cell_cellranger"
}
EOF
  
  echo "📁 Run directory: $RUN_DIR"
  echo "📄 Metadata: $RUN_DIR/metadata.json"
  
else
  echo "❌ Cell Ranger workflow submission failed!"
  echo "📄 Error output saved to: $RUN_DIR/submission_output.txt"
  cat "$RUN_DIR/submission_output.txt"
  exit 1
fi

echo
echo "🎉 Single-cell Cell Ranger workflow submitted!"
echo "   Monitor progress at: $JOB_URL"
echo "   Run artifacts in: $RUN_DIR"