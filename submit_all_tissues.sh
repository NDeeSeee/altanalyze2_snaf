#!/bin/bash
# Batch submit all GTEx tissues using entity-based JSONs
# Usage: ./submit_all_tissues.sh [--delay SECONDS]

set -e

# Configuration
TERRA_RUNS_DIR="workflows/splicing_analysis/terra_runs"
INPUT_DIR="workflows/splicing_analysis/inputs/gtex_entity_based"
METHOD="AltAnalyze3_SNAF/splicing_analysis/1"
DELAY=0  # Default: no delay between submissions

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --delay)
            DELAY="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--delay SECONDS]"
            exit 1
            ;;
    esac
done

echo "======================================================================"
echo "🚀 Batch Submit All GTEx Tissues"
echo "======================================================================"
echo ""
echo "Method: $METHOD"
echo "Delay between submissions: ${DELAY}s"
echo ""

# Check if input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    echo "❌ Input directory not found: $INPUT_DIR"
    echo "Run ./run_all.sh first to generate entity-based JSONs"
    exit 1
fi

# Check if terra_runs directory exists
if [ ! -d "$TERRA_RUNS_DIR" ]; then
    echo "❌ Terra runs directory not found: $TERRA_RUNS_DIR"
    exit 1
fi

# Find all entity JSON files, sorted by sample count (smallest first)
mapfile -t entity_files < <(python3 - "$INPUT_DIR" <<'PY'
import sys, pathlib, re
root = pathlib.Path(sys.argv[1])
if not root.exists():
    sys.exit(0)
files = []
pattern = re.compile(r'_(\d+)_entity\.json$')
for path in root.glob('*_entity.json'):
    match = pattern.search(path.name)
    if match:
        files.append((int(match.group(1)), path.name))
    else:
        files.append((float('inf'), path.name))
for _, name in sorted(files, key=lambda x: (x[0], x[1].lower())):
    print(name)
PY
)

if [ ${#entity_files[@]} -eq 0 ]; then
    echo "❌ No entity JSON files found in $INPUT_DIR"
    echo "Run ./run_all.sh first to generate them"
    exit 1
fi

echo "📋 Found ${#entity_files[@]} tissues to submit:"
for file in "${entity_files[@]}"; do
    tissue=$(echo "$file" | sed 's/_entity.json$//' | sed 's/_[0-9]*$//')
    count=$(echo "$file" | sed 's/.*_\([0-9]*\)_entity.json/\1/')
    echo "   • $tissue ($count samples)"
done
echo ""

# Confirm before proceeding
read -p "Continue with batch submission? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "======================================================================"
echo "🚀 Starting Submissions"
echo "======================================================================"
echo ""

# Track results
declare -a successful
declare -a failed

# Submit each tissue
counter=1
total=${#entity_files[@]}

for file in "${entity_files[@]}"; do
    tissue=$(echo "$file" | sed 's/_entity.json$//' | sed 's/_[0-9]*$//')
    count=$(echo "$file" | sed 's/.*_\([0-9]*\)_entity.json/\1/')
    entity_name="${tissue}_samples"
    
    echo "[$counter/$total] Submitting: $tissue ($count samples)"
    echo "----------------------------------------"
    
    cd "$TERRA_RUNS_DIR"
    
    if ./dockstore_run.sh \
        -m "$METHOD" \
        -i "../inputs/gtex_entity_based/$file" \
        -d "GTEx $tissue - $count samples via data tables" \
        -e "$entity_name" \
        -E sample_set; then
        
        echo "✅ $tissue submitted successfully"
        successful+=("$tissue ($count)")
        
    else
        echo "❌ $tissue submission failed"
        failed+=("$tissue ($count)")
    fi
    
    cd - > /dev/null
    echo ""
    
    # Delay before next submission (if specified)
    if [ $DELAY -gt 0 ] && [ $counter -lt $total ]; then
        echo "⏳ Waiting ${DELAY}s before next submission..."
        sleep $DELAY
        echo ""
    fi
    
    ((counter++))
done

# Print summary
echo "======================================================================"
echo "📊 BATCH SUBMISSION SUMMARY"
echo "======================================================================"
echo ""
echo "✅ Successful: ${#successful[@]}"
if [ ${#successful[@]} -gt 0 ]; then
    for tissue in "${successful[@]}"; do
        echo "   • $tissue"
    done
fi
echo ""

echo "❌ Failed: ${#failed[@]}"
if [ ${#failed[@]} -gt 0 ]; then
    for tissue in "${failed[@]}"; do
        echo "   • $tissue"
    done
fi
echo ""

echo "======================================================================"
echo "🔗 Monitor your submissions:"
echo "   https://app.terra.bio/#workspaces/SNAF_AltAnalyze2_GTEx/SNAF_AltAnalyze2_GTEx/job_history"
echo "======================================================================"