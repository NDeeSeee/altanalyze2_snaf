#!/bin/bash
# Single-cell workflow runner using established Cumulus workflow on Terra
# Uses the well-established Cumulus single-cell RNA-seq processing pipeline
#
# Usage:
#   workflows/single_cell/terra_runs/cumulus_run.sh \
#     -i workflows/single_cell/inputs/cumulus_input.json \
#     -d "Single-cell 10X Genomics analysis"
#
# Options:
#   -i INPUT_JSON       Path to Cumulus input JSON (required)
#   -d DESCRIPTION      Run description (default: auto-generated)
#   -v VERSION          Cumulus version (default: latest)
#   -p PROJECT          Terra project (default from env)
#   -w WORKSPACE        Terra workspace (default from env)
#   -C MAX_COST_USD     Maximum cost threshold (default: 50.00)
#   -h                  Show help
#
set -euo pipefail

print_help() {
  cat <<'EOF'
Usage: cumulus_run.sh -i INPUT_JSON [-d DESCRIPTION] [-v VERSION] [-p PROJECT] [-w WORKSPACE] [-C MAX_COST_USD] [-h]

Single-cell workflow runner using established Cumulus pipeline on Terra

Options:
  -i INPUT_JSON       Path to Cumulus input JSON (required)
  -d DESCRIPTION      Run description (default: auto-generated)
  -v VERSION          Cumulus version (default: latest)
  -p PROJECT          Terra project (default from env)
  -w WORKSPACE        Terra workspace (default from env)
  -C MAX_COST_USD     Maximum cost threshold (default: 50.00)
  -h                  Show this help

Examples:
  # 10X Genomics data with latest Cumulus
  cumulus_run.sh -i inputs/10x_sample.json -d "10X single-cell analysis"

  # Specific Cumulus version
  cumulus_run.sh -i inputs/cellranger_sample.json -v 1.5.0 -d "Cell Ranger analysis"

  # Custom workspace and cost limit
  cumulus_run.sh -i inputs/custom_sample.json -w "mylab/sc-analysis" -C 100.00

Cumulus Input Requirements:
  - FASTQ files (R1, R2, I1 for 10X; R1, R2 for other platforms)
  - Reference genome and transcriptome
  - Sample metadata
  - Platform-specific parameters (10X, Smart-seq2, etc.)

For input JSON templates, see:
  - workflows/single_cell/inputs/10x_template.json
  - workflows/single_cell/inputs/smartseq2_template.json
EOF
}

INPUT_JSON=""
DESCRIPTION=""
CUMULUS_VERSION="latest"
MAX_COST_USD="50.00"
OVERRIDE_PROJECT=""
OVERRIDE_WORKSPACE=""

while getopts ":i:d:v:p:w:C:h" opt; do
  case $opt in
    i) INPUT_JSON="$OPTARG" ;;
    d) DESCRIPTION="$OPTARG" ;;
    v) CUMULUS_VERSION="$OPTARG" ;;
    p) OVERRIDE_PROJECT="$OPTARG" ;;
    w) OVERRIDE_WORKSPACE="$OPTARG" ;;
    C) MAX_COST_USD="$OPTARG" ;;
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

# Load environment
for ENV_FILE in workflows/terra/env.sh workflows/single_cell/terra_runs/env.sh; do
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    break
  fi
done

# Set defaults
WORKSPACE_PROJECT="${OVERRIDE_PROJECT:-${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}}"
WORKSPACE_NAME="${OVERRIDE_WORKSPACE:-${WORKSPACE_NAME:-AltAnalyze3_SNAF}}"

# Determine Cumulus method reference
if [[ "$CUMULUS_VERSION" == "latest" ]]; then
  CUMULUS_METHOD="cumulus/cumulus"
else
  CUMULUS_METHOD="cumulus/cumulus/${CUMULUS_VERSION}"
fi

# Generate description if not provided
if [[ -z "$DESCRIPTION" ]]; then
  # Try to extract sample information from input JSON
  num_samples=$(python3 -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    # Cumulus typically has sample information in different fields
    samples = data.get('cumulus.sample_names', []) or data.get('cumulus.sample_id', [])
    if isinstance(samples, list):
        print(len(samples))
    elif isinstance(samples, str):
        print(1)
    else:
        print('unknown')
except:
    print('unknown')
" "$INPUT_JSON" 2>/dev/null || echo "unknown")
  
  DESCRIPTION="Single-cell Cumulus | ${CUMULUS_VERSION} | ${num_samples} samples | ${WORKSPACE_PROJECT}/${WORKSPACE_NAME}"
fi

echo "🧬 Single-cell Cumulus workflow configuration:"
echo "   Method: $CUMULUS_METHOD"
echo "   Version: $CUMULUS_VERSION"
echo "   Workspace: $WORKSPACE_PROJECT/$WORKSPACE_NAME"
echo "   Max cost: \$$MAX_COST_USD"
echo "   Description: $DESCRIPTION"
echo

# Validate input JSON has required Cumulus fields
echo "🔍 Validating Cumulus input JSON..."
python3 - "$INPUT_JSON" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    
    # Check for common Cumulus input fields
    required_fields = [
        'cumulus.fastq_r1_files',
        'cumulus.fastq_r2_files', 
        'cumulus.reference_genome',
        'cumulus.reference_transcriptome'
    ]
    
    missing_fields = []
    for field in required_fields:
        if field not in data:
            missing_fields.append(field)
    
    if missing_fields:
        print(f"⚠️  Missing Cumulus fields: {', '.join(missing_fields)}")
        print("   Make sure your input JSON follows Cumulus requirements")
    else:
        print("✅ Input JSON appears to have required Cumulus fields")
        
    # Show available fields for debugging
    cumulus_fields = [k for k in data.keys() if k.startswith('cumulus.')]
    print(f"   Found {len(cumulus_fields)} Cumulus-specific fields")
    
except Exception as e:
    print(f"❌ Error validating input JSON: {e}")
    sys.exit(1)
PY

if [[ $? -ne 0 ]]; then
  echo "❌ Input validation failed. Please check your Cumulus input JSON."
  exit 1
fi

echo

# Use alto terra run to submit Cumulus workflow
echo "🚀 Submitting Cumulus workflow to Terra..."

# Create temporary directory for run tracking
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="workflows/single_cell/terra_runs/runs/${RUN_ID}"
mkdir -p "$RUN_DIR"

# Copy input JSON to run directory
cp "$INPUT_JSON" "$RUN_DIR/input.json"

# Submit using alto terra run
WORKSPACE_REF="${WORKSPACE_PROJECT}/${WORKSPACE_NAME}"

echo "📋 Submitting to workspace: $WORKSPACE_REF"
echo "📦 Method: $CUMULUS_METHOD"

# Use alto terra run with Cumulus method
alto terra run \
  -m "$CUMULUS_METHOD" \
  -w "$WORKSPACE_REF" \
  -i "$INPUT_JSON" \
  --bucket-folder "cumulus-runs/${RUN_ID}" \
  --no-cache \
  > "$RUN_DIR/submission_output.txt" 2>&1

SUBMISSION_STATUS=$?

if [[ $SUBMISSION_STATUS -eq 0 ]]; then
  echo "✅ Cumulus workflow submitted successfully!"
  
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
  "method": "$CUMULUS_METHOD",
  "input_json": "$(realpath "$INPUT_JSON" 2>/dev/null || echo "$INPUT_JSON")",
  "submission_id": "$SUBMISSION_ID",
  "job_url": "$JOB_URL",
  "description": "$DESCRIPTION",
  "workflow_type": "single_cell_cumulus"
}
EOF
  
  echo "📁 Run directory: $RUN_DIR"
  echo "📄 Metadata: $RUN_DIR/metadata.json"
  
else
  echo "❌ Cumulus workflow submission failed!"
  echo "📄 Error output saved to: $RUN_DIR/submission_output.txt"
  cat "$RUN_DIR/submission_output.txt"
  exit 1
fi

echo
echo "🎉 Single-cell Cumulus workflow submitted!"
echo "   Monitor progress at: $JOB_URL"
echo "   Run artifacts in: $RUN_DIR"