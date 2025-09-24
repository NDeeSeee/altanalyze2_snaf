#!/bin/bash
# Rerun only failed BamToBed shards from a previous submission, reusing cache
# Usage:
#   workflows/splicing_analysis/terra_runs/rerun_failed_shards.sh \
#     -s <submission_id> \
#     -i <original_input_json> \
#     [-v <method_version (default: 1)>] \
#     [-m <bam_to_bed_memory e.g. '12 GB'>] \
#     [-C <max_cost_usd>] \
#     [-p <project>] [-w <workspace>]
set -euo pipefail

SUB_ID=""
INPUT_JSON=""
METHOD_VER="1"
BAM_MEM=""
MAX_COST_USD=""
PROJECT="${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}"
WORKSPACE="${WORKSPACE_NAME:-AltAnalyze3_SNAF}"

print_help() {
  sed -n '1,20p' "$0"
}

while getopts ":s:i:v:m:C:p:w:h" opt; do
  case $opt in
    s) SUB_ID="$OPTARG" ;;
    i) INPUT_JSON="$OPTARG" ;;
    v) METHOD_VER="$OPTARG" ;;
    m) BAM_MEM="$OPTARG" ;;
    C) MAX_COST_USD="$OPTARG" ;;
    p) PROJECT="$OPTARG" ;;
    w) WORKSPACE="$OPTARG" ;;
    h) print_help; exit 0 ;;
    :) echo "Missing argument for -$OPTARG" >&2; exit 2 ;;
    \?) echo "Unknown option -$OPTARG" >&2; print_help; exit 2 ;;
  esac
done

if [[ -z "$SUB_ID" || -z "$INPUT_JSON" ]]; then
  echo "❌ -s and -i are required" >&2
  print_help
  exit 2
fi

METHOD_REF="AltAnalyze3_SNAF/splicing_analysis/${METHOD_VER}"
BASE_DIR="workflows/splicing_analysis/terra_runs"
OUT_JSON="${INPUT_JSON%.json}_partial_rerun.json"

# Prepare partial inputs (keeps only failed BAMs, adds produced BEDs)
python3 "$BASE_DIR/prepare_partial_rerun.py" \
  --submission-id "$SUB_ID" \
  --input-json "$INPUT_JSON" \
  --out "$OUT_JSON" \
  --project "$PROJECT" \
  --workspace "$WORKSPACE"

# Optionally bump BamToBed memory for just-these-shards (global for this tiny rerun)
if [[ -n "$BAM_MEM" ]]; then
  python3 - "$OUT_JSON" "$BAM_MEM" <<'PY'
import sys, json
p, mem = sys.argv[1:3]
j = json.load(open(p))
j['SplicingAnalysis.bam_to_bed_memory'] = mem
open(p, 'w').write(json.dumps(j, indent=2) + "\n")
print(f"Set BamToBed memory -> {mem}")
PY
fi

# Submit partial rerun using exact method version to maximize cache reuse
DESC="Partial rerun for $SUB_ID | reuse cache | ${BAM_MEM:+bam_mem=$BAM_MEM}"
workflows/splicing_analysis/terra_runs/dockstore_run.sh \
  -m "$METHOD_REF" \
  -i "$OUT_JSON" \
  -d "$DESC" \
  ${MAX_COST_USD:+-C "$MAX_COST_USD"}
