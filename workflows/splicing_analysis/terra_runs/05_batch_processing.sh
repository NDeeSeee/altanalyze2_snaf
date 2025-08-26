#!/bin/bash
# Terra Batch Processing
# Large-scale batch processing scripts for GTEx and other datasets

set -euo pipefail

echo "⚡ Terra Batch Processing Setup..."

# Configuration (source env if available)
ENV_FILE="workflows/splicing_analysis/terra_runs/env.sh"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

: "${NAMESPACE:=AltAnalyze3_SNAF}"
: "${WORKSPACE:=${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}/${WORKSPACE_NAME:-AltAnalyze3_SNAF}}"
SPLICING_METHOD_VERSION=${SPLICING_METHOD_VERSION:-1}
METHOD="${NAMESPACE}/splicing_analysis/${SPLICING_METHOD_VERSION}"
INPUT_DIR="workflows/splicing_analysis/inputs/gtex_v10_validated"

# ============================================================================
# Step 1: GTEx Tissue Processing Priorities
# ============================================================================

# Define GTEx tissues by processing priority and sample counts
# Based on validation data from docs/gtex/validation_reports/validation_summary.txt

declare -A GTEX_TISSUES
GTEX_TISSUES=(
    # High Priority (good success rates, reasonable sizes)
    ["adipose_tissue"]="1480:60.1%"      # 1480 samples, 60.1% success rate
    ["skin"]="2292:51.3%"                # 2292 samples, 51.3% success rate  
    ["esophagus"]="1831:53.9%"           # 1831 samples, 53.9% success rate
    ["cervix_uteri"]="55:62.5%"          # 55 samples, 62.5% success rate
    
    # Medium Priority (large datasets)
    ["brain"]="3737:46.5%"               # 3737 samples, 46.5% success rate
    ["muscle"]="966:41.1%"               # 966 samples, 41.1% success rate
    ["blood_vessel"]="1622:49.4%"        # 1622 samples, 49.4% success rate
    ["heart"]="1058:49.5%"               # 1058 samples, 49.5% success rate
    ["colon"]="1023:49.1%"               # 1023 samples, 49.1% success rate
    
    # Lower Priority (smaller datasets or lower success rates)
    ["thyroid"]="794:39.1%"              # 794 samples, 39.1% success rate
    ["lung"]="748:39.5%"                 # 748 samples, 39.5% success rate
    ["blood"]="1434:30.4%"               # 1434 samples, 30.4% success rate
)

# ============================================================================
# Step 2: Batch Processing Strategy Functions
# ============================================================================

estimate_costs() {
    local tissue=$1
    local sample_count=$2
    
    # Cost estimation based on pilot data: ~$0.50-1.00 per sample
    local low_estimate=$(echo "$sample_count * 0.50" | bc -l)
    local high_estimate=$(echo "$sample_count * 1.00" | bc -l)
    
    printf "%.2f-%.2f" "$low_estimate" "$high_estimate"
}

create_tissue_batch_plan() {
    echo "🧬 GTEx Tissue Processing Plan"
    echo "============================="
    echo ""
    
    # Create batch plan file
    BATCH_PLAN="workflows/splicing_analysis/terra_runs/gtex_batch_plan.txt"
    
    cat > "$BATCH_PLAN" << EOF
# GTEx Tissue Processing Plan
# Generated: $(date)
# Total validated samples: 22,970

Priority | Tissue | Samples | Success Rate | Est. Cost | Status
---------|--------|---------|--------------|-----------|-------
EOF
    
    local total_samples=0
    local total_cost_low=0
    local total_cost_high=0
    
    echo "High Priority Tissues:"
    echo "----------------------"
    
    for tissue in adipose_tissue skin esophagus cervix_uteri; do
        if [[ -v GTEX_TISSUES[$tissue] ]]; then
            local info="${GTEX_TISSUES[$tissue]}"
            local count=$(echo "$info" | cut -d: -f1)
            local success_rate=$(echo "$info" | cut -d: -f2)
            local cost_range=$(estimate_costs "$tissue" "$count")
            
            printf "%-20s %6s samples (%s) - \$%s\n" "$tissue" "$count" "$success_rate" "$cost_range"
            
            # Add to plan file
            echo "HIGH     | $tissue | $count | $success_rate | \$${cost_range} | Pending" >> "$BATCH_PLAN"
            
            total_samples=$((total_samples + count))
            total_cost_low=$(echo "$total_cost_low + $(echo "$cost_range" | cut -d- -f1)" | bc -l)
            total_cost_high=$(echo "$total_cost_high + $(echo "$cost_range" | cut -d- -f2)" | bc -l)
        fi
    done
    
    echo ""
    echo "Medium Priority Tissues:"
    echo "------------------------"
    
    for tissue in brain muscle blood_vessel heart colon; do
        if [[ -v GTEX_TISSUES[$tissue] ]]; then
            local info="${GTEX_TISSUES[$tissue]}"
            local count=$(echo "$info" | cut -d: -f1)
            local success_rate=$(echo "$info" | cut -d: -f2)
            local cost_range=$(estimate_costs "$tissue" "$count")
            
            printf "%-20s %6s samples (%s) - \$%s\n" "$tissue" "$count" "$success_rate" "$cost_range"
            
            # Add to plan file
            echo "MEDIUM   | $tissue | $count | $success_rate | \$${cost_range} | Pending" >> "$BATCH_PLAN"
            
            total_samples=$((total_samples + count))
            total_cost_low=$(echo "$total_cost_low + $(echo "$cost_range" | cut -d- -f1)" | bc -l)
            total_cost_high=$(echo "$total_cost_high + $(echo "$cost_range" | cut -d- -f2)" | bc -l)
        fi
    done
    
    echo ""
    echo "Summary:"
    echo "--------"
    printf "Total Samples: %s\n" "$total_samples"
    printf "Estimated Cost: \$%.2f - \$%.2f\n" "$total_cost_low" "$total_cost_high"
    
    # Add summary to plan file
    echo "" >> "$BATCH_PLAN"
    echo "# Summary" >> "$BATCH_PLAN"
    echo "Total Samples: $total_samples" >> "$BATCH_PLAN"
    printf "Estimated Total Cost: \$%.2f - \$%.2f\n" "$total_cost_low" "$total_cost_high" >> "$BATCH_PLAN"
    
    echo "✅ Batch plan saved to: $BATCH_PLAN"
}

# ============================================================================
# Step 3: Automated Batch Submission Script
# ============================================================================

create_automated_batch_processor() {
    cat > workflows/splicing_analysis/terra_runs/process_gtex_batch.sh << 'EOF'
#!/bin/bash
# Automated GTEx Batch Processor
# Process GTEx tissues with automatic monitoring and error handling

set -euo pipefail

# Configuration (source env if available)
ENV_FILE="workflows/splicing_analysis/terra_runs/env.sh"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

: "${NAMESPACE:=AltAnalyze3_SNAF}"
: "${WORKSPACE:=${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}/${WORKSPACE_NAME:-AltAnalyze3_SNAF}}"
SPLICING_METHOD_VERSION=${SPLICING_METHOD_VERSION:-1}
METHOD="${NAMESPACE}/splicing_analysis/${SPLICING_METHOD_VERSION}"
INPUT_DIR="workflows/splicing_analysis/inputs/gtex_v10_validated"
BATCH_DATE=$(date +%Y%m%d-%H%M)

# Logging setup
BATCH_LOG="workflows/splicing_analysis/terra_runs/batch_${BATCH_DATE}.log"
RESULTS_DIR="workflows/splicing_analysis/terra_runs/results/$BATCH_DATE"
mkdir -p "$RESULTS_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$BATCH_LOG"
}

# Tissue processing order (high priority first)
TISSUES=(
    "cervix_uteri:55"        # Start small for testing
    "adipose_tissue:1480"    # High success rate
    "skin:2292"              # Large but good success rate
    "esophagus:1831"         # Good balance
    # Add more tissues as needed
)

log "🚀 Starting GTEx batch processing: $BATCH_DATE"
log "Tissues to process: ${#TISSUES[@]}"

# Process each tissue
for tissue_info in "${TISSUES[@]}"; do
    tissue=$(echo "$tissue_info" | cut -d: -f1)
    expected_count=$(echo "$tissue_info" | cut -d: -f2)
    
    log "📊 Processing $tissue (expected $expected_count samples)..."
    
    # Check if input file exists
    INPUT_FILE="$INPUT_DIR/${tissue}.json"
    if [ ! -f "$INPUT_FILE" ]; then
        log "❌ Input file not found: $INPUT_FILE"
        continue
    fi
    
    # Verify sample count in input file
    actual_count=$(python3 -c "
import json
with open('$INPUT_FILE') as f:
    data = json.load(f)
print(len(data.get('SplicingAnalysis.bam_files', [])))
" 2>/dev/null || echo "0")
    
    if [ "$actual_count" != "$expected_count" ]; then
        log "⚠️ Sample count mismatch for $tissue: expected $expected_count, found $actual_count"
    fi
    
    # Submit job
    BUCKET_FOLDER="gtex-production-$BATCH_DATE/$tissue"
    log "🚀 Submitting $tissue to folder: $BUCKET_FOLDER"
    
    if JOB_URL=$(alto terra run \
        -m "$METHOD" \
        -w "$WORKSPACE" \
        -i "$INPUT_FILE" \
        --bucket-folder "$BUCKET_FOLDER" 2>&1); then
        
        # Extract submission ID
        SUBMISSION_ID=$(echo "$JOB_URL" | grep -o 'job_history/[^[:space:]]*' | cut -d/ -f2)
        
        log "✅ $tissue submitted successfully"
        log "   URL: $JOB_URL"
        log "   ID: $SUBMISSION_ID"
        
        # Record submission
        echo "$tissue,$actual_count,$SUBMISSION_ID,$JOB_URL,$(date),Submitted,\$0.00" >> \
            "workflows/splicing_analysis/terra_runs/batch_submissions_${BATCH_DATE}.csv"
        
        # Wait between submissions to avoid overwhelming Terra
        log "   Waiting 60 seconds before next submission..."
        sleep 60
        
    else
        log "❌ Failed to submit $tissue"
        log "   Error: $JOB_URL"
        
        # Record failure
        echo "$tissue,$actual_count,FAILED,FAILED,$(date),Failed,\$0.00" >> \
            "workflows/splicing_analysis/terra_runs/batch_submissions_${BATCH_DATE}.csv"
    fi
    
    log "---"
done

log "🎉 Batch submission complete!"
log "Results tracking file: batch_submissions_${BATCH_DATE}.csv"
log "Monitor progress with: ./workflows/splicing_analysis/terra_runs/check_batch_status.sh"

# Create monitoring reminder
cat > "$RESULTS_DIR/monitoring_commands.txt" << MONITOR_EOF
# Monitoring Commands for Batch $BATCH_DATE

# Check all job status
./workflows/splicing_analysis/terra_runs/check_batch_status.sh

# Monitor specific job (replace SUBMISSION_ID)
source workflows/splicing_analysis/terra_runs/04_monitoring_commands.sh

# Real-time monitoring
./workflows/splicing_analysis/terra_runs/monitor_jobs.sh

# Check costs
alto terra storage_estimate --output costs_${BATCH_DATE}.tsv --access owner

# Batch log file
tail -f workflows/splicing_analysis/terra_runs/batch_${BATCH_DATE}.log
MONITOR_EOF

log "📋 Monitoring commands saved to: $RESULTS_DIR/monitoring_commands.txt"
EOF
    
    chmod +x workflows/splicing_analysis/terra_runs/process_gtex_batch.sh
    echo "✅ Automated batch processor created: workflows/splicing_analysis/terra_runs/process_gtex_batch.sh"
}

# ============================================================================
# Step 4: Result Collection Script
# ============================================================================

create_result_collector() {
    cat > workflows/splicing_analysis/terra_runs/collect_batch_results.sh << 'EOF'
#!/bin/bash
# Batch Result Collector
# Download and organize results from completed batch jobs

set -euo pipefail

BATCH_CSV="workflows/splicing_analysis/terra_runs/batch_submissions.csv"
RESULTS_BASE_DIR="./batch_results"

# Configuration (source env if available)
ENV_FILE="workflows/splicing_analysis/terra_runs/env.sh"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

WORKSPACE_BUCKET="${WORKSPACE_BUCKET:-fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f}"

if [ ! -f "$BATCH_CSV" ]; then
    echo "❌ Batch submissions file not found: $BATCH_CSV"
    exit 1
fi

echo "📥 GTEx Batch Result Collector"
echo "=============================="

# Create results directory
mkdir -p "$RESULTS_BASE_DIR"

# Process each completed job
while IFS=, read -r tissue sample_count submission_id job_url submission_date status cost; do
    # Skip header
    if [ "$tissue" = "tissue" ]; then
        continue
    fi
    
    # Skip failed jobs
    if [ "$submission_id" = "FAILED" ]; then
        echo "⏭️  Skipping failed job: $tissue"
        continue
    fi
    
    echo ""
    echo "🔍 Checking $tissue ($submission_id)..."
    
    # Check job status
    JOB_STATUS=$(curl -s -X GET \
        "https://api.firecloud.org/api/workspaces/AltAnalyze3_SNAF/AltAnalyze3_SNAF/submissions/$submission_id" \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" | \
        python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['workflows'][0]['status'])
except:
    print('ERROR')
" 2>/dev/null)
    
    case $JOB_STATUS in
        "Succeeded")
            echo "✅ $tissue completed successfully - downloading results..."
            
            # Create tissue-specific results directory
            TISSUE_DIR="$RESULTS_BASE_DIR/$tissue"
            mkdir -p "$TISSUE_DIR"
            
            # Download workflow logs
            echo "   Downloading logs..."
            gsutil -m cp -r \
                "gs://$WORKSPACE_BUCKET/submissions/$submission_id/workflow.logs/" \
                "$TISSUE_DIR/" 2>/dev/null || {
                echo "   ⚠️ Failed to download logs"
            }
            
            # Download task outputs (main results)
            echo "   Downloading task outputs..."
            gsutil -m cp -r \
                "gs://$WORKSPACE_BUCKET/submissions/$submission_id/SplicingAnalysis/" \
                "$TISSUE_DIR/" 2>/dev/null || {
                echo "   ⚠️ Failed to download task outputs"
            }
            
            # Download final results archive if available
            echo "   Looking for final results archive..."
            RESULTS_ARCHIVE=$(gsutil ls "gs://$WORKSPACE_BUCKET/submissions/$submission_id/SplicingAnalysis/*/call-RunJunctions/altanalyze_output.tar.gz" 2>/dev/null | head -1)
            
            if [ -n "$RESULTS_ARCHIVE" ]; then
                gsutil cp "$RESULTS_ARCHIVE" "$TISSUE_DIR/${tissue}_results.tar.gz" && {
                    echo "   ✅ Results archive downloaded: ${tissue}_results.tar.gz"
                    
                    # Extract archive
                    cd "$TISSUE_DIR"
                    tar -xzf "${tissue}_results.tar.gz" 2>/dev/null && {
                        echo "   ✅ Results extracted"
                    } || echo "   ⚠️ Failed to extract results"
                    cd - >/dev/null
                } || echo "   ⚠️ Failed to download results archive"
            else
                echo "   ⚠️ No results archive found"
            fi
            
            # Create summary file
            cat > "$TISSUE_DIR/processing_summary.txt" << SUMMARY_EOF
Tissue: $tissue
Sample Count: $sample_count
Submission ID: $submission_id
Job URL: $job_url
Submitted: $submission_date
Status: $JOB_STATUS
Cost: $cost
Downloaded: $(date)
SUMMARY_EOF
            
            echo "   📄 Summary saved: $TISSUE_DIR/processing_summary.txt"
            ;;
            
        "Running")
            echo "🔄 $tissue still running..."
            ;;
            
        "Failed")
            echo "❌ $tissue failed - collecting error logs..."
            
            # Create failed job directory
            FAILED_DIR="$RESULTS_BASE_DIR/failed/$tissue"
            mkdir -p "$FAILED_DIR"
            
            # Download logs for debugging
            gsutil -m cp -r \
                "gs://$WORKSPACE_BUCKET/submissions/$submission_id/workflow.logs/" \
                "$FAILED_DIR/" 2>/dev/null || {
                echo "   ⚠️ Failed to download error logs"
            }
            ;;
            
        *)
            echo "⚠️  $tissue status: $JOB_STATUS"
            ;;
    esac
    
done < "$BATCH_CSV"

echo ""
echo "🎉 Result collection complete!"
echo "Results directory: $RESULTS_BASE_DIR"

# Create results summary
echo ""
echo "📊 Results Summary:"
echo "==================="
find "$RESULTS_BASE_DIR" -name "processing_summary.txt" -exec head -2 {} \; -exec echo "" \;

echo ""
echo "Next steps:"
echo "1. Review results in: $RESULTS_BASE_DIR"
echo "2. Check failed jobs in: $RESULTS_BASE_DIR/failed/"
echo "3. Re-run failed jobs if needed"
EOF
    
    chmod +x workflows/splicing_analysis/terra_runs/collect_batch_results.sh
    echo "✅ Result collector created: workflows/splicing_analysis/terra_runs/collect_batch_results.sh"
}

# ============================================================================
# Step 5: Execute Setup Functions
# ============================================================================

echo "📋 Creating batch processing plan..."
create_tissue_batch_plan

echo ""
echo "📋 Creating automated batch processor..."
create_automated_batch_processor

echo ""
echo "📋 Creating result collector..."
create_result_collector

# ============================================================================
# Step 6: Batch Processing Summary
# ============================================================================

echo ""
echo "🎉 Batch Processing Setup Complete!"
echo "===================================="
echo ""
echo "Available batch processing tools:"
echo "1. 📊 Batch Plan: workflows/splicing_analysis/terra_runs/gtex_batch_plan.txt"
echo "2. 🚀 Automated Processor: workflows/splicing_analysis/terra_runs/process_gtex_batch.sh"
echo "3. 📥 Result Collector: workflows/splicing_analysis/terra_runs/collect_batch_results.sh"
echo ""
echo "Execution order:"
echo "1. Review the batch plan file"
echo "2. Run: ./workflows/splicing_analysis/terra_runs/process_gtex_batch.sh"
echo "3. Monitor with: ./workflows/splicing_analysis/terra_runs/monitor_jobs.sh" 
echo "4. Collect results: ./workflows/splicing_analysis/terra_runs/collect_batch_results.sh"
echo ""
echo "Cost estimates (conservative, per-sample $0.50–$1.00):"
echo "- Small tissues (50-100 samples): $25–100"
echo "- Medium tissues (500-1000 samples): $250–1,000" 
echo "- Large tissues (1500+ samples): $750–1,500+"
echo "- Full GTEx dataset (22,970 samples): $11,000–23,000"