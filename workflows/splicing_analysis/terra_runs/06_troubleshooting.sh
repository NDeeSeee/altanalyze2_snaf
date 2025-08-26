#!/bin/bash
# Terra Troubleshooting Guide
# Common issues, debugging commands, and recovery procedures

set -euo pipefail

echo "🔧 Terra Troubleshooting Guide"
echo "=============================="

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
: "${WORKSPACE_BUCKET:=fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f}"

# ============================================================================
# Common Issues & Solutions
# ============================================================================

troubleshoot_authentication() {
    echo "🔐 Authentication Troubleshooting"
    echo "================================="
    
    echo "Checking Google Cloud authentication..."
    
    # Check user authentication
    echo "1. User authentication:"
    if gcloud auth list | grep -q "ACTIVE"; then
        echo "   ✅ User authenticated"
        gcloud auth list | grep "ACTIVE"
    else
        echo "   ❌ No active user authentication"
        echo "   Solution: Run 'gcloud auth login'"
        return 1
    fi
    
    # Check application default credentials
    echo "2. Application default credentials:"
    if gcloud auth application-default print-access-token >/dev/null 2>&1; then
        echo "   ✅ Application default credentials working"
    else
        echo "   ❌ Application default credentials failed"
        echo "   Solution: Run 'gcloud auth application-default login'"
        return 1
    fi
    
    # Check Terra workspace access
    echo "3. Terra workspace access:"
    if fissfc space_list 2>/dev/null | grep -q "$WORKSPACE_NAME"; then
        echo "   ✅ Workspace accessible"
    else
        echo "   ❌ Cannot access workspace"
        echo "   Solution: Check workspace permissions and billing"
        return 1
    fi
    
    echo "✅ Authentication checks passed"
}

troubleshoot_workflow_submission() {
    echo "🚀 Workflow Submission Troubleshooting"
    echo "======================================"
    
    # Check if methods exist
    echo "1. Checking uploaded methods..."
    if fissfc meth_list -n "$NAMESPACE" 2>/dev/null | grep -q "splicing_analysis"; then
        echo "   ✅ Splicing analysis method found"
    else
        echo "   ❌ Splicing analysis method not found"
        echo "   Solution: Run 'alto terra add_method -n $NAMESPACE workflows/splicing_analysis/splicing_analysis.wdl'"
        return 1
    fi
    
    # Test input JSON validation
    echo "2. Input JSON validation function:"
    
    validate_input_json() {
        local json_file=$1
        
        if [ ! -f "$json_file" ]; then
            echo "   ❌ Input file not found: $json_file"
            return 1
        fi
        
        # Check JSON syntax
        if ! python3 -m json.tool "$json_file" >/dev/null 2>&1; then
            echo "   ❌ Invalid JSON syntax in $json_file"
            return 1
        fi
        
        # Check required parameters
        local required_params=(
            "SplicingAnalysis.bam_files"
            "SplicingAnalysis.bai_files"
            "SplicingAnalysis.species"
        )
        
        for param in "${required_params[@]}"; do
            if ! grep -q "\"$param\"" "$json_file"; then
                echo "   ❌ Missing required parameter: $param"
                return 1
            fi
        done
        
        # Check BAM/BAI count match
        local bam_count=$(python3 -c "
import json
with open('$json_file') as f:
    data = json.load(f)
print(len(data.get('SplicingAnalysis.bam_files', [])))
")
        
        local bai_count=$(python3 -c "
import json
with open('$json_file') as f:
    data = json.load(f)
print(len(data.get('SplicingAnalysis.bai_files', [])))
")
        
        if [ "$bam_count" != "$bai_count" ]; then
            echo "   ❌ BAM/BAI count mismatch: $bam_count vs $bai_count"
            return 1
        fi
        
        echo "   ✅ Input JSON validated ($bam_count samples)"
    }
    
    echo "   Use: validate_input_json <input.json>"
    echo "✅ Workflow submission checks available"
}

troubleshoot_file_access() {
    echo "📁 File Access Troubleshooting"
    echo "=============================="
    
    check_file_access() {
        local gs_path=$1
        
        echo "Checking file: $gs_path"
        
        # Check if file exists
        if gsutil ls "$gs_path" >/dev/null 2>&1; then
            echo "   ✅ File exists"
            
            # Check file size
            local size=$(gsutil ls -l "$gs_path" | awk '{print $1}')
            echo "   📏 Size: $size bytes"
            
            # Check permissions
            if gsutil acl get "$gs_path" >/dev/null 2>&1; then
                echo "   ✅ Read permissions available"
            else
                echo "   ❌ Permission denied"
                echo "   Solution: Check file permissions and bucket access"
                return 1
            fi
        else
            echo "   ❌ File not found"
            echo "   Solution: Verify file path and existence"
            return 1
        fi
    }
    
    echo "Use: check_file_access gs://bucket/path/file.bam"
    echo "✅ File access checker available"
}

troubleshoot_job_failures() {
    echo "❌ Job Failure Troubleshooting"
    echo "=============================="
    
    analyze_job_failure() {
        local submission_id=$1
        
        echo "🔍 Analyzing failed job: $submission_id"
        
        # Get workflow metadata
        local metadata_url="https://api.firecloud.org/api/workspaces/$WORKSPACE/submissions/$submission_id/workflows"
        
        echo "Getting workflow information..."
        local workflow_id=$(curl -s -X GET \
            "https://api.firecloud.org/api/workspaces/$WORKSPACE/submissions/$submission_id" \
            -H "Authorization: Bearer $(gcloud auth print-access-token)" | \
            python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['workflows'][0]['workflowId'])
except:
    print('ERROR')
" 2>/dev/null)
        
        if [ "$workflow_id" = "ERROR" ]; then
            echo "❌ Failed to get workflow information"
            return 1
        fi
        
        echo "Workflow ID: $workflow_id"
        
        # Get failure details
        echo "Getting failure details..."
        curl -s -X GET \
            "https://api.firecloud.org/api/workspaces/$WORKSPACE/submissions/$submission_id/workflows/$workflow_id" \
            -H "Authorization: Bearer $(gcloud auth print-access-token)" | \
            python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'failures' in data and data['failures']:
        print('Failure Details:')
        for failure in data['failures']:
            print('  Message:', failure.get('message', 'No message'))
            if 'causedBy' in failure:
                for cause in failure['causedBy']:
                    print('  Caused by:', cause.get('message', 'No cause message'))
    else:
        print('No detailed failure information available')
except Exception as e:
    print('Error parsing failure data:', str(e))
"
        
        # Check for common failure patterns
        echo ""
        echo "Common failure patterns to check:"
        echo "1. FileNotFoundException - Check file paths and existence"
        echo "2. Memory errors (exit code 137) - Increase memory allocation"
        echo "3. Disk space errors - Increase disk space or use different disk type"
        echo "4. Preemptible failures - Reduce preemptible setting or increase retries"
        echo "5. Docker image issues - Verify image exists and is accessible"
        
        # Get task logs if available
        echo ""
        echo "Checking for task logs..."
        if gsutil ls "gs://$WORKSPACE_BUCKET/submissions/$submission_id/" >/dev/null 2>&1; then
            echo "Available log directories:"
            gsutil ls "gs://$WORKSPACE_BUCKET/submissions/$submission_id/"
            
            # Look for stderr files
            local stderr_files=$(gsutil ls -r "gs://$WORKSPACE_BUCKET/submissions/$submission_id/" | grep stderr || true)
            if [ -n "$stderr_files" ]; then
                echo ""
                echo "Error logs found:"
                echo "$stderr_files"
                echo ""
                echo "To view error logs:"
                echo "gsutil cat 'gs://$WORKSPACE_BUCKET/submissions/$submission_id/SplicingAnalysis/*/call-*/stderr'"
            fi
        fi
    }
    
    echo "Use: analyze_job_failure <submission_id>"
    echo "✅ Job failure analyzer available"
}

create_recovery_procedures() {
    echo "🔄 Recovery Procedures"
    echo "====================="
    
    cat > workflows/splicing_analysis/terra_runs/recovery_procedures.md << 'EOF'
# Terra Recovery Procedures

## Common Recovery Scenarios

### 1. Authentication Expired
**Problem**: "Could not authenticate with Terra"
**Solution**:
```bash
gcloud auth login
gcloud auth application-default login
```

### 2. Workflow Submission Failed
**Problem**: "Extra inputs" or "validation errors"
**Solution**:
```bash
# Clean input JSON to match WDL exactly
# Remove any extra parameters not defined in WDL
# Verify parameter names match exactly
```

### 3. File Not Found Errors
**Problem**: "FileNotFoundException: gs://..."
**Solution**:
```bash
# Check file existence
gsutil ls gs://path/to/file.bam

# Check permissions
gsutil acl get gs://path/to/file.bam

# Verify file path in input JSON
```

### 4. Memory/Resource Failures
**Problem**: Task failed with exit code 137 (OOM) or disk space errors
**Solution**:
```bash
# Increase memory in input JSON:
"SplicingAnalysis.bam_to_bed_memory": "16 GB"  # Increase from 8 GB

# Increase disk space:
"SplicingAnalysis.bam_to_bed_disk_multiplier": 4.0  # Increase multiplier

# Use SSD for better I/O:
"SplicingAnalysis.bam_to_bed_disk_type": "SSD"
```

### 5. Preemptible Instance Failures
**Problem**: Multiple preemptions causing repeated failures
**Solution**:
```bash
# Reduce preemptible attempts:
"SplicingAnalysis.bam_to_bed_preemptible": 1  # Reduce from 3

# Increase max retries:
"SplicingAnalysis.bam_to_bed_max_retries": 3  # Increase from 2
```

### 6. Docker Image Issues
**Problem**: "docker: image not found" or container failures
**Solution**:
```bash
# Verify image exists:
docker pull ndeeseee/altanalyze:v1.6.37

# Use specific tag:
"SplicingAnalysis.docker_image": "ndeeseee/altanalyze:v1.6.37"
```

## Batch Job Recovery

### Failed Batch Jobs
```bash
# 1. Identify failed jobs
./workflows/splicing_analysis/terra_runs/check_batch_status.sh

# 2. Get failure details
analyze_job_failure <submission_id>

# 3. Fix input JSON based on error
# 4. Resubmit specific tissues:
alto terra run -m "method" -w "workspace" -i "fixed_input.json"
```

### Partial Batch Completion
```bash
# 1. Collect completed results
./workflows/splicing_analysis/terra_runs/collect_batch_results.sh

# 2. Identify remaining tissues
# 3. Submit remaining tissues individually
```

## Data Recovery

### Download Failed Job Logs
```bash
SUBMISSION_ID="your-submission-id"
mkdir -p debug_logs/$SUBMISSION_ID

# Download all logs
gsutil -m cp -r \
  "gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/submissions/$SUBMISSION_ID/" \
  "debug_logs/$SUBMISSION_ID/"
```

### Rescue Partial Results
```bash
# Check for partial outputs
gsutil ls -r "gs://workspace-bucket/submissions/$SUBMISSION_ID/"

# Download any available results
gsutil -m cp -r \
  "gs://workspace-bucket/submissions/$SUBMISSION_ID/SplicingAnalysis/" \
  "./partial_results/"
```

## Cost Management Recovery

### Unexpected High Costs
```bash
# 1. Check current costs
alto terra storage_estimate --output emergency_costs.tsv --access owner

# 2. Identify expensive jobs
fissfc monitor -w workspace -p project | grep "Running"

# 3. Abort expensive jobs if necessary
# (Note: Use Terra web interface to abort jobs)

# 4. Review resource allocations for future jobs
```

### Budget Exceeded
```bash
# 1. Pause new submissions
# 2. Collect completed results
./workflows/splicing_analysis/terra_runs/collect_batch_results.sh

# 3. Review and optimize resource settings
# 4. Resume with smaller batches or reduced resources
```

## Prevention Strategies

1. **Always test with small datasets first**
2. **Monitor costs regularly during batch processing**
3. **Keep backup copies of working input JSONs**
4. **Document successful resource configurations**
5. **Set up automated monitoring for long-running batches**
EOF
    
    echo "✅ Recovery procedures documented: workflows/splicing_analysis/terra_runs/recovery_procedures.md"
}

create_diagnostic_script() {
    cat > workflows/splicing_analysis/terra_runs/diagnose_system.sh << 'EOF'
#!/bin/bash
# Terra System Diagnostics
# Complete system health check and configuration validation

set -euo pipefail

echo "🩺 Terra System Diagnostics"
echo "==========================="
echo "Timestamp: $(date)"
echo ""

# Check all system components
echo "1. System Requirements:"
echo "   Google Cloud SDK: $(gcloud --version 2>/dev/null | head -1 || echo 'NOT INSTALLED')"
echo "   Altocumulus: $(alto --version 2>/dev/null || echo 'NOT INSTALLED')"
echo "   FISS: $(fissfc --version 2>/dev/null || echo 'NOT INSTALLED')"
echo "   Python: $(python3 --version 2>/dev/null || echo 'NOT INSTALLED')"
echo "   gsutil: $(gsutil version 2>/dev/null | head -1 || echo 'NOT INSTALLED')"
echo ""

# Authentication status
echo "2. Authentication Status:"
ACTIVE_ACCOUNT=$(gcloud config get-value account 2>/dev/null || echo 'NONE')
echo "   Active account: $ACTIVE_ACCOUNT"

if gcloud auth application-default print-access-token >/dev/null 2>&1; then
    echo "   Application default: ✅ WORKING"
else
    echo "   Application default: ❌ FAILED"
fi
echo ""

# Terra access
echo "3. Terra Access:"
if fissfc space_list 2>/dev/null | grep -q "AltAnalyze3_SNAF"; then
    echo "   Workspace access: ✅ WORKING"
else
    echo "   Workspace access: ❌ FAILED"
fi

    echo "   Workspace details:"
    fissfc space_info -w "$WORKSPACE_NAME" -p "$WORKSPACE_PROJECT" 2>/dev/null | grep -E "(billingAccount|bucketName|state)" || echo "   Cannot retrieve workspace info"
echo ""

# Method availability
echo "4. Uploaded Methods:"
if fissfc meth_list -n "$NAMESPACE" 2>/dev/null; then
    echo "   ✅ Methods accessible"
else
    echo "   ❌ Cannot access methods"
fi
echo ""

# Recent job status
echo "5. Recent Jobs:"
fissfc monitor -w AltAnalyze3_SNAF -p AltAnalyze3_SNAF 2>/dev/null | head -3 || echo "   Cannot retrieve job information"
echo ""

# Storage access
echo "6. Storage Access:"
if gsutil ls gs://fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f/ >/dev/null 2>&1; then
    echo "   Workspace bucket: ✅ ACCESSIBLE"
else
    echo "   Workspace bucket: ❌ ACCESS DENIED"
fi
echo ""

# Configuration files
echo "7. Configuration Files:"
CONFIG_FILES=(
    "workflows/splicing_analysis/terra_runs/01_authentication_setup.sh"
    "workflows/splicing_analysis/terra_runs/02_workflow_management.sh"
    "workflows/splicing_analysis/terra_runs/03_job_submission.sh"
    "workflows/splicing_analysis/terra_runs/04_monitoring_commands.sh"
)

for config in "${CONFIG_FILES[@]}"; do
    if [ -f "$config" ]; then
        echo "   ✅ $config"
    else
        echo "   ❌ $config (missing)"
    fi
done
echo ""

# Input files check
echo "8. Input Files:"
INPUT_DIR="workflows/splicing_analysis/inputs/gtex_v10_validated"
if [ -d "$INPUT_DIR" ]; then
    echo "   Input directory: ✅ EXISTS"
    echo "   Available inputs: $(ls "$INPUT_DIR"/*.json 2>/dev/null | wc -l) JSON files"
else
    echo "   Input directory: ❌ MISSING"
fi
echo ""

echo "🩺 Diagnostic complete!"
echo "If any checks failed, refer to recovery_procedures.md"
EOF
    
    chmod +x workflows/splicing_analysis/terra_runs/diagnose_system.sh
    echo "✅ Diagnostic script created: workflows/splicing_analysis/terra_runs/diagnose_system.sh"
}

# ============================================================================
# Execute Troubleshooting Setup
# ============================================================================

echo "📋 Setting up troubleshooting functions..."

# Make functions available
echo "Authentication troubleshooting: troubleshoot_authentication"
echo "Workflow submission troubleshooting: troubleshoot_workflow_submission"
echo "File access troubleshooting: troubleshoot_file_access"
echo "Job failure analysis: troubleshoot_job_failures"

echo ""
echo "📋 Creating recovery documentation..."
create_recovery_procedures

echo ""
echo "📋 Creating diagnostic script..."
create_diagnostic_script

# ============================================================================
# Interactive Troubleshooting Menu
# ============================================================================

show_troubleshooting_menu() {
    echo ""
    echo "🔧 Interactive Troubleshooting Menu"
    echo "==================================="
    echo "1. Run system diagnostics"
    echo "2. Test authentication"
    echo "3. Validate input JSON file"
    echo "4. Analyze failed job"
    echo "5. Check file access"
    echo "6. View recovery procedures"
    echo "7. Exit"
    echo ""
    
    read -p "Select option (1-7): " choice
    
    case $choice in
        1)
            ./workflows/splicing_analysis/terra_runs/diagnose_system.sh
            ;;
        2)
            troubleshoot_authentication
            ;;
        3)
            read -p "Enter path to JSON file: " json_path
            validate_input_json "$json_path" 2>/dev/null || echo "Validation function not loaded"
            ;;
        4)
            read -p "Enter submission ID: " sub_id
            analyze_job_failure "$sub_id" 2>/dev/null || echo "Analysis function not loaded"
            ;;
        5)
            read -p "Enter gs:// path: " gs_path
            check_file_access "$gs_path" 2>/dev/null || echo "File check function not loaded"
            ;;
        6)
            if [ -f "workflows/splicing_analysis/terra_runs/recovery_procedures.md" ]; then
                less workflows/splicing_analysis/terra_runs/recovery_procedures.md
            else
                echo "Recovery procedures file not found"
            fi
            ;;
        7)
            echo "Exiting troubleshooting menu."
            return 0
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
}

echo ""
echo "🎉 Troubleshooting Setup Complete!"
echo "=================================="
echo ""
echo "Available troubleshooting tools:"
echo "1. 🩺 System diagnostics: ./workflows/splicing_analysis/terra_runs/diagnose_system.sh"
echo "2. 📖 Recovery procedures: workflows/splicing_analysis/terra_runs/recovery_procedures.md"
echo "3. 🔧 Interactive functions: source this script to load troubleshooting functions"
echo ""
echo "Quick diagnostic commands:"
echo "- Full system check: ./workflows/splicing_analysis/terra_runs/diagnose_system.sh"
echo "- Test auth: troubleshoot_authentication"
echo "- Analyze failure: analyze_job_failure <submission_id>"
echo "- Check file: check_file_access <gs://path>"

# Optionally show interactive menu
read -p "Show interactive troubleshooting menu? (y/N): " show_menu
if [[ $show_menu =~ ^[Yy]$ ]]; then
    show_troubleshooting_menu
fi