#!/bin/bash
# Terra Job Submission
# Submit splicing analysis jobs with various input configurations

set -euo pipefail

echo "🚀 Terra Job Submission..."

# Configuration (source env if available)
for ENV_FILE in workflows/terra/env.sh workflows/splicing_analysis/terra_runs/env.sh; do
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    break
  fi
done

: "${NAMESPACE:=AltAnalyze3_SNAF}"
: "${WORKSPACE:=${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}/${WORKSPACE_NAME:-AltAnalyze3_SNAF}}" 
SPLICING_METHOD_VERSION=${SPLICING_METHOD_VERSION:-1}
METHOD="${NAMESPACE}/splicing_analysis/${SPLICING_METHOD_VERSION}"

# ============================================================================
# Step 1: Verify Prerequisites
# ============================================================================
echo "📋 Step 1: Verifying prerequisites..."

# Check authentication
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    echo "❌ Authentication failed. Run: source 01_authentication_setup.sh"
    exit 1
fi

# Check workflow exists
if ! fissfc meth_list -n "$NAMESPACE" | grep -q "splicing_analysis"; then
    echo "❌ Splicing analysis workflow not found. Run: source 02_workflow_management.sh"
    exit 1
fi

echo "✅ Prerequisites verified"

# ============================================================================
# Step 2: Test Job Submission (Small Dataset)
# ============================================================================
echo "📋 Step 2: Test job submission with small dataset..."

# Create a minimal test input
TEST_INPUT="test_input_2samples.json"
cat > "$TEST_INPUT" << 'EOF'
{
  "SplicingAnalysis.extra_bed_files": [],
  "SplicingAnalysis.species": "Hs",
  "SplicingAnalysis.bam_to_bed_cpu_cores": 1,
  "SplicingAnalysis.bam_to_bed_memory": "8 GB",
  "SplicingAnalysis.bam_to_bed_disk_type": "HDD",
  "SplicingAnalysis.bam_to_bed_preemptible": 3,
  "SplicingAnalysis.bam_to_bed_max_retries": 2,
  "SplicingAnalysis.junction_analysis_cpu_cores": 1,
  "SplicingAnalysis.junction_analysis_memory": "8 GB",
  "SplicingAnalysis.junction_analysis_disk_type": "HDD",
  "SplicingAnalysis.junction_analysis_preemptible": 1,
  "SplicingAnalysis.junction_analysis_max_retries": 1,
  "SplicingAnalysis.docker_image": "${ALTANALYZE_DOCKER_DEFAULT:-ndeeseee/altanalyze:v1.6.39}",
  "SplicingAnalysis.bam_files": [
    "gs://fc-secure-e0503432-75b9-4674-8e6d-2597dc529c4c/GTEx_Analysis_2022-06-06_v10_RNAseq_BAM_files/GTEX-P78B-2326-SM-EZ6KO.Aligned.sortedByCoord.out.patched.md.bam",
    "gs://fc-secure-e0503432-75b9-4674-8e6d-2597dc529c4c/GTEx_Analysis_2022-06-06_v10_RNAseq_BAM_files/GTEX-PWOO-1826-SM-GPI9T.Aligned.sortedByCoord.out.patched.md.bam"
  ],
  "SplicingAnalysis.bai_files": [
    "gs://fc-secure-e0503432-75b9-4674-8e6d-2597dc529c4c/GTEx_Analysis_2022-06-06_v10_RNAseq_BAM_files/GTEX-P78B-2326-SM-EZ6KO.Aligned.sortedByCoord.out.patched.md.bam.bai",
    "gs://fc-secure-e0503432-75b9-4674-8e6d-2597dc529c4c/GTEx_Analysis_2022-06-06_v10_RNAseq_BAM_files/GTEX-PWOO-1826-SM-GPI9T.Aligned.sortedByCoord.out.patched.md.bam.bai"
  ]
}
EOF

echo "Created test input: $TEST_INPUT"

# Submit test job
BUCKET_FOLDER="cli-test-$(date +%Y%m%d-%H%M)"
echo "Submitting test job with bucket folder: $BUCKET_FOLDER"

echo "Command being executed:"
echo "alto terra run -m \"$METHOD\" -w \"$WORKSPACE\" -i \"$TEST_INPUT\" --bucket-folder \"$BUCKET_FOLDER\""

if JOB_URL=$(alto terra run -m "$METHOD" -w "$WORKSPACE" -i "$TEST_INPUT" --bucket-folder "$BUCKET_FOLDER"); then
    echo "✅ Test job submitted successfully!"
    echo "Job URL: $JOB_URL"
    
    # Extract submission ID
    SUBMISSION_ID=$(echo "$JOB_URL" | sed 's/.*job_history\///')
    echo "Submission ID: $SUBMISSION_ID"
    
    # Save job info
    echo "Test job: $JOB_URL" >> workflows/splicing_analysis/terra_runs/job_history.txt
    echo "Submission ID: $SUBMISSION_ID" >> workflows/splicing_analysis/terra_runs/job_history.txt
    echo "Date: $(date)" >> workflows/splicing_analysis/terra_runs/job_history.txt
    echo "---" >> workflows/splicing_analysis/terra_runs/job_history.txt
    
else
    echo "❌ Test job submission failed"
    exit 1
fi

# Clean up test input
rm -f "$TEST_INPUT"

# ============================================================================
# Step 3: GTEx Production Job Examples
# ============================================================================
echo "📋 Step 3: GTEx production job examples..."

echo ""
echo "🧬 GTEx Production Job Commands:"
echo "==============================="

echo ""
echo "Small Cervix dataset (2 samples - for testing):"
echo "alto terra run \\"
echo "  -m \"$METHOD\" \\"
echo "  -w \"$WORKSPACE\" \\"
echo "  -i \"test_input_2samples.json\" \\"
echo "  --bucket-folder \"cli-gtex-test-\$(date +%Y%m%d-%H%M)\""

echo ""
echo "Full Cervix Uteri dataset (55 samples):"
echo "alto terra run \\"
echo "  -m \"$METHOD\" \\"
echo "  -w \"$WORKSPACE\" \\"
echo "  -i \"workflows/splicing_analysis/inputs/gtex_v10_validated/cervix_uteri_55.json\" \\"
echo "  --bucket-folder \"cli-gtex-cervix-\$(date +%Y%m%d-%H%M)\""

echo ""
echo "Adipose Tissue dataset (~1,300 samples):"
echo "alto terra run \\"
echo "  -m \"$METHOD\" \\"
echo "  -w \"$WORKSPACE\" \\"
echo "  -i \"workflows/splicing_analysis/inputs/gtex_v10_validated/adipose_tissue_1480.json\" \\"
echo "  --bucket-folder \"cli-gtex-adipose-\$(date +%Y%m%d-%H%M)\""

# ============================================================================
# Step 4: Batch Submission Script
# ============================================================================
echo "📋 Step 4: Ensuring batch submission script present..."

if [ ! -f workflows/splicing_analysis/terra_runs/submit_gtex_batch.sh ]; then
cat > workflows/splicing_analysis/terra_runs/submit_gtex_batch.sh << 'EOF'
#!/bin/bash
# GTEx Batch Submission Script
# Submit multiple GTEx tissues for processing

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

# Available GTEx datasets (update based on available files)
TISSUES=(
    "cervix_uteri_55:55"
    "adipose_tissue_1480:1480"  
    "skin_2292:2292"
    "esophagus_1831:1831"
)

echo "🧬 GTEx Batch Processing..."
echo "Available tissues:"
for tissue_info in "${TISSUES[@]}"; do
    tissue=$(echo "$tissue_info" | cut -d: -f1)
    count=$(echo "$tissue_info" | cut -d: -f2)
    echo "  - $tissue ($count samples)"
done

# Interactive tissue selection
echo ""
echo "Select tissues to process (space-separated numbers, or 'all'):"
select tissue_info in "${TISSUES[@]}" "all"; do
    case $tissue_info in
        "all")
            SELECTED_TISSUES=("${TISSUES[@]}")
            break
            ;;
        *:*)
            SELECTED_TISSUES=("$tissue_info")
            break
            ;;
        *)
            echo "Invalid selection"
            ;;
    esac
done

# Process selected tissues
BATCH_DATE=$(date +%Y%m%d-%H%M)
echo "Processing batch: $BATCH_DATE"

for tissue_info in "${SELECTED_TISSUES[@]}"; do
    tissue=$(echo "$tissue_info" | cut -d: -f1)
    count=$(echo "$tissue_info" | cut -d: -f2)
    
    INPUT_FILE="$INPUT_DIR/${tissue}.json"
    
    if [ ! -f "$INPUT_FILE" ]; then
        echo "⚠️ Input file not found: $INPUT_FILE"
        continue
    fi
    
    echo ""
    echo "🚀 Processing $tissue ($count samples)..."
    
    # Submit job
    BUCKET_FOLDER="gtex-batch-$BATCH_DATE/$tissue"
    
    if JOB_URL=$(alto terra run -m "$METHOD" -w "$WORKSPACE" -i "$INPUT_FILE" --bucket-folder "$BUCKET_FOLDER"); then
        echo "✅ $tissue submitted successfully"
        echo "   URL: $JOB_URL"
        
        # Extract submission ID
        SUBMISSION_ID=$(echo "$JOB_URL" | sed 's/.*job_history\///')
        
        # Log submission
        echo "$tissue,$count,$SUBMISSION_ID,$JOB_URL,$(date)" >> workflows/splicing_analysis/terra_runs/batch_submissions.csv
        
        # Wait between submissions (optional)
        echo "   Waiting 30 seconds before next submission..."
        sleep 30
    else
        echo "❌ Failed to submit $tissue"
    fi
done

echo ""
echo "🎉 Batch submission complete!"
echo "Monitor progress with: source 04_monitoring_commands.sh"
EOF

chmod +x workflows/splicing_analysis/terra_runs/submit_gtex_batch.sh
echo "✅ Batch submission script created: workflows/splicing_analysis/terra_runs/submit_gtex_batch.sh"
else
  echo "ℹ️ Batch submission script already exists; skipping creation."
fi

# ============================================================================
# Step 5: Create Job History Tracking
# ============================================================================
echo "📋 Step 5: Setting up job history tracking..."

# Create headers if file doesn't exist
if [ ! -f workflows/splicing_analysis/terra_runs/job_history.txt ]; then
    echo "# Terra Job History" > workflows/splicing_analysis/terra_runs/job_history.txt
    echo "# Format: Description, Job URL, Submission ID, Date" >> workflows/splicing_analysis/terra_runs/job_history.txt
    echo "---" >> workflows/splicing_analysis/terra_runs/job_history.txt
fi

# Create CSV header if file doesn't exist
if [ ! -f workflows/splicing_analysis/terra_runs/batch_submissions.csv ]; then
    echo "tissue,sample_count,submission_id,job_url,submission_date" > workflows/splicing_analysis/terra_runs/batch_submissions.csv
fi

echo "✅ Job tracking files initialized"

# ============================================================================
# Step 6: Current Job Status
# ============================================================================
echo "📋 Step 6: Current job status..."

echo ""
echo "📊 Current Jobs:"
echo "==============="

# Show recent submissions
if fissfc monitor -w "$WORKSPACE_NAME" -p "$WORKSPACE_PROJECT" 2>/dev/null | head -5; then
    echo "✅ Job monitoring accessible"
else
    echo "⚠️ Job monitoring may have issues"
fi

echo ""
echo "🎉 Job submission setup complete!"
echo ""
echo "Next steps:"
echo "1. Monitor jobs: source 04_monitoring_commands.sh"
echo "2. Batch processing: ./workflows/splicing_analysis/terra_runs/submit_gtex_batch.sh"
echo "3. Check results and costs regularly"

echo ""
echo "📋 Quick Commands:"
echo "=================="
echo "Monitor active jobs:"
echo "  fissfc monitor -w $WORKSPACE_NAME -p $WORKSPACE_PROJECT | head -5"
echo ""
echo "Check costs:"
echo "  alto terra storage_estimate --output current_costs.tsv --access owner"
echo ""
echo "Submit single job:"
echo "  alto terra run -m \"$METHOD\" -w \"$WORKSPACE\" -i \"input.json\" --bucket-folder \"folder-name\""
echo "=================="