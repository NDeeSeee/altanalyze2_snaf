#!/bin/bash
# Terra Monitoring Commands
# Monitor workflows, costs, results, and troubleshoot issues

set -euo pipefail

echo "📊 Terra Monitoring Commands..."

# Configuration (source env if available)
for ENV_FILE in workflows/terra/env.sh workflows/splicing_analysis/terra_runs/env.sh; do
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    break
  fi
done

: "${NAMESPACE:=${NAMESPACE:-AltAnalyze3_SNAF}}"
: "${WORKSPACE:=${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}/${WORKSPACE_NAME:-AltAnalyze3_SNAF}}"
: "${WORKSPACE_BUCKET:=${WORKSPACE_BUCKET:-fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f}}"

# ============================================================================
# Step 1: Active Job Monitoring
# ============================================================================
echo "📋 Step 1: Active job monitoring..."

echo "Current workspace submissions:"
if fissfc monitor -w "$WORKSPACE_NAME" -p "$WORKSPACE_PROJECT" 2>/dev/null | head -10; then
    echo "✅ Monitoring data retrieved"
else
    echo "❌ Failed to get monitoring data"
fi

# Get most recent submission ID for detailed monitoring
RECENT_SUBMISSION=$(fissfc monitor -w "$WORKSPACE_NAME" -p "$WORKSPACE_PROJECT" 2>/dev/null | tail -n +2 | head -1 | awk '{print $7}')

if [ -n "$RECENT_SUBMISSION" ]; then
    echo ""
    echo "🔍 Most recent submission: $RECENT_SUBMISSION"
    echo "Job URL: https://app.terra.bio/#workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME/job_history/$RECENT_SUBMISSION"
fi

# ============================================================================
# Step 2: Detailed Job Status Function
# ============================================================================

check_job_status() {
    local submission_id=$1
    
    echo "📊 Checking status for submission: $submission_id"
    
    # Get detailed status via API
    STATUS_DATA=$(curl -s -X GET \
        "https://api.firecloud.org/api/workspaces/${WORKSPACE_PROJECT}/${WORKSPACE_NAME}/submissions/${submission_id}" \
        -H "Authorization: Bearer $(gcloud auth print-access-token)")
    
    # Parse status information
    if echo "$STATUS_DATA" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    workflow = data['workflows'][0]
    print(f'Status: {workflow[\"status\"]}')
    print(f'Cost: \${workflow[\"cost\"]}')
    print(f'Started: {data[\"submissionDate\"]}')
    if 'statusLastChangedDate' in workflow:
        print(f'Last Updated: {workflow[\"statusLastChangedDate\"]}')
except:
    print('Error parsing status data')
    sys.exit(1)
"; then
        echo "✅ Status retrieved successfully"
    else
        echo "❌ Failed to parse status data"
        return 1
    fi
}

# ============================================================================
# Step 3: Cost Monitoring
# ============================================================================
echo "📋 Step 3: Cost monitoring..."

echo "Getting workspace storage costs..."
if alto terra storage_estimate --output current_workspace_costs.tsv --access owner; then
    if [ -f current_workspace_costs.tsv ]; then
        echo "✅ Cost data saved to: current_workspace_costs.tsv"
        echo "Current workspace costs:"
        cat current_workspace_costs.tsv
    fi
else
    echo "⚠️ Cost monitoring may be unavailable"
fi

# ============================================================================
# Step 4: Log Access Functions
# ============================================================================

get_workflow_logs() {
    local submission_id=$1
    
    echo "📄 Getting workflow logs for: $submission_id"
    
    # List log files
    echo "Available log files:"
    gsutil ls "gs://${WORKSPACE_BUCKET}/submissions/${submission_id}/workflow.logs/" 2>/dev/null || {
        echo "❌ No workflow logs found"
        return 1
    }
    
    # Get the main workflow log
    WORKFLOW_LOG=$(gsutil ls "gs://${WORKSPACE_BUCKET}/submissions/${submission_id}/workflow.logs/workflow.*.log" 2>/dev/null | head -1)
    
    if [ -n "$WORKFLOW_LOG" ]; then
        echo "Main workflow log:"
        gsutil cat "$WORKFLOW_LOG" | tail -20
    else
        echo "❌ Main workflow log not found"
    fi
}

get_task_outputs() {
    local submission_id=$1
    local workflow_name=${2:-"SplicingAnalysis"}
    
    echo "📁 Getting task outputs for: $submission_id"
    
    # List workflow execution directory
    echo "Execution directory structure:"
    gsutil ls "gs://${WORKSPACE_BUCKET}/submissions/${submission_id}/${workflow_name}/" 2>/dev/null || {
        echo "❌ No execution directory found"
        return 1
    }
    
    # List individual task directories
    echo "Task directories:"
    gsutil ls -r "gs://${WORKSPACE_BUCKET}/submissions/${submission_id}/${workflow_name}/" | head -20
}

download_results() {
    local submission_id=$1
    local output_dir=${2:-"./results/$submission_id"}
    
    echo "📥 Downloading results for: $submission_id"
    echo "Output directory: $output_dir"
    
    mkdir -p "$output_dir"
    
    # Download workflow logs
    echo "Downloading logs..."
    gsutil -m cp -r "gs://${WORKSPACE_BUCKET}/submissions/${submission_id}/workflow.logs/" "$output_dir/" 2>/dev/null || {
        echo "⚠️ Failed to download logs"
    }
    
    # Download task outputs
    echo "Downloading task outputs..."
    gsutil -m cp -r "gs://${WORKSPACE_BUCKET}/submissions/${submission_id}/SplicingAnalysis/" "$output_dir/" 2>/dev/null || {
        echo "⚠️ Failed to download task outputs"
    }
    
    echo "✅ Results download complete: $output_dir"
}

# ============================================================================
# Step 5: Real-time Monitoring Script
# ============================================================================

create_monitoring_script() {
    cat > workflows/splicing_analysis/terra_runs/monitor_jobs.sh << 'EOF'
#!/bin/bash
# Real-time job monitoring script

set -euo pipefail

# Configuration (source env if available)
ENV_FILE="workflows/splicing_analysis/terra_runs/env.sh"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

WORKSPACE_NAME="${WORKSPACE_NAME:-AltAnalyze3_SNAF}"
PROJECT="${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}"

echo "🔄 Starting real-time job monitoring..."
echo "Press Ctrl+C to stop"
echo ""

while true; do
    clear
    echo "════════════════════════════════════════"
    echo "Terra Job Monitor - $(date)"
    echo "Workspace: $PROJECT/$WORKSPACE_NAME"
    echo "════════════════════════════════════════"
    
    # Get recent submissions
    echo "Recent Submissions:"
    echo "-------------------"
    fissfc monitor -w "$WORKSPACE_NAME" -p "$PROJECT" 2>/dev/null | head -5 || {
        echo "❌ Monitoring unavailable"
    }
    
    echo ""
    echo "Storage Costs:"
    echo "--------------"
    alto terra storage_estimate --output /tmp/live_costs.tsv --access owner >/dev/null 2>&1 && {
        cat /tmp/live_costs.tsv 2>/dev/null || echo "No cost data"
    }
    
    echo ""
    echo "Next update in 30 seconds... (Ctrl+C to stop)"
    sleep 30
done
EOF
    
    chmod +x workflows/splicing_analysis/terra_runs/monitor_jobs.sh
    echo "✅ Real-time monitoring script created: workflows/splicing_analysis/terra_runs/monitor_jobs.sh"
}

# ============================================================================
# Step 6: Batch Status Checker
# ============================================================================

create_batch_status_checker() {
    cat > workflows/splicing_analysis/terra_runs/check_batch_status.sh << 'EOF'
#!/bin/bash
# Check status of multiple batch jobs

set -euo pipefail

BATCH_CSV="workflows/splicing_analysis/terra_runs/batch_submissions.csv"

# Configuration (source env if available)
ENV_FILE="workflows/splicing_analysis/terra_runs/env.sh"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

WORKSPACE_PROJECT="${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}"
WORKSPACE_NAME="${WORKSPACE_NAME:-AltAnalyze3_SNAF}"

if [ ! -f "$BATCH_CSV" ]; then
    echo "❌ Batch submissions file not found: $BATCH_CSV"
    exit 1
fi

echo "🔍 Batch Job Status Checker"
echo "=========================="
echo ""

# Read CSV and check each job
while IFS=, read -r tissue sample_count submission_id job_url submission_date; do
    # Skip header
    if [ "$tissue" = "tissue" ]; then
        continue
    fi
    
    echo "📊 $tissue ($sample_count samples)"
    echo "   Submitted: $submission_date"
    echo "   ID: $submission_id"
    
    # Get status
    STATUS=$(curl -s -X GET \
        "https://api.firecloud.org/api/workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME/submissions/$submission_id" \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" | \
        python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    workflow = data['workflows'][0]
    print(f'{workflow[\"status\"]}:\${workflow[\"cost\"]}')
except:
    print('ERROR:$0.00')
" 2>/dev/null)
    
    # Parse status and cost
    JOB_STATUS=$(echo "$STATUS" | cut -d: -f1)
    JOB_COST=$(echo "$STATUS" | cut -d: -f2)
    
    case $JOB_STATUS in
        "Succeeded")
            echo "   ✅ Status: $JOB_STATUS ($JOB_COST)"
            ;;
        "Failed")
            echo "   ❌ Status: $JOB_STATUS ($JOB_COST)"
            ;;
        "Running")
            echo "   🔄 Status: $JOB_STATUS ($JOB_COST)"
            ;;
        *)
            echo "   ⚠️  Status: $JOB_STATUS ($JOB_COST)"
            ;;
    esac
    
    echo "   URL: $job_url"
    echo ""
    
done < "$BATCH_CSV"

echo "Done checking batch status."
EOF
    
    chmod +x workflows/splicing_analysis/terra_runs/check_batch_status.sh
    echo "✅ Batch status checker created: workflows/splicing_analysis/terra_runs/check_batch_status.sh"
}

# ============================================================================
# Step 7: Execute Monitoring Functions
# ============================================================================

# Check if we have a recent submission to monitor
if [ -n "$RECENT_SUBMISSION" ]; then
    echo ""
    echo "📋 Step 7: Monitoring recent submission..."
    check_job_status "$RECENT_SUBMISSION"
fi

# Create monitoring utilities
create_monitoring_script
create_batch_status_checker

# ============================================================================
# Step 8: Interactive Monitoring Menu
# ============================================================================

show_monitoring_menu() {
    echo ""
    echo "🎛️  Monitoring Options:"
    echo "======================"
    echo "1. Check job status (enter submission ID)"
    echo "2. Get workflow logs (enter submission ID)"
    echo "3. List task outputs (enter submission ID)" 
    echo "4. Download results (enter submission ID)"
    echo "5. Start real-time monitoring"
    echo "6. Check batch job status"
    echo "7. Check workspace costs"
    echo "8. Exit"
    echo ""
    
    read -p "Select option (1-8): " choice
    
    case $choice in
        1)
            read -p "Enter submission ID: " sub_id
            check_job_status "$sub_id"
            ;;
        2)
            read -p "Enter submission ID: " sub_id
            get_workflow_logs "$sub_id"
            ;;
        3)
            read -p "Enter submission ID: " sub_id
            get_task_outputs "$sub_id"
            ;;
        4)
            read -p "Enter submission ID: " sub_id
            read -p "Output directory [./results/$sub_id]: " out_dir
            out_dir=${out_dir:-"./results/$sub_id"}
            download_results "$sub_id" "$out_dir"
            ;;
        5)
            ./workflows/splicing_analysis/terra_runs/monitor_jobs.sh
            ;;
        6)
            ./workflows/splicing_analysis/terra_runs/check_batch_status.sh
            ;;
        7)
            alto terra storage_estimate --output current_costs_$(date +%Y%m%d_%H%M).tsv --access owner
            echo "Cost data saved to: current_costs_$(date +%Y%m%d_%H%M).tsv"
            ;;
        8)
            echo "Exiting monitoring menu."
            return 0
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
}

echo ""
echo "🎉 Monitoring setup complete!"
echo ""
echo "Available monitoring utilities:"
echo "- ./workflows/splicing_analysis/terra_runs/monitor_jobs.sh (real-time monitoring)"
echo "- ./workflows/splicing_analysis/terra_runs/check_batch_status.sh (batch status)"
echo ""
echo "Quick commands:"
echo "- Current jobs: fissfc monitor -w $WORKSPACE_NAME -p $WORKSPACE_PROJECT | head -5"
echo "- Check costs: alto terra storage_estimate --output costs.tsv --access owner"
echo "- Job status: check_job_status SUBMISSION_ID"
echo "- Get logs: get_workflow_logs SUBMISSION_ID"

# Optionally show interactive menu
read -p "Show interactive monitoring menu? (y/N): " show_menu
if [[ $show_menu =~ ^[Yy]$ ]]; then
    show_monitoring_menu
fi

# Clean up temporary files
rm -f current_workspace_costs.tsv /tmp/live_costs.tsv 2>/dev/null || true