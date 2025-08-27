# Altocumulus (Alto) Complete Guide

This guide provides comprehensive documentation for using Altocumulus (`alto`) to run the AltAnalyze2 SNAF workflows on cloud platforms.

## What is Altocumulus?

Altocumulus is a Python toolkit for running bioinformatics workflows on cloud platforms. It provides:

- **Terra Integration**: Submit workflows to Terra/FireCloud
- **Cromwell Support**: Direct Cromwell server interaction  
- **File Management**: Automatic upload/download of workflow data
- **Cost Monitoring**: Workspace storage and cost estimation

## Installation

### Via pip (Recommended)
```bash
pip install altocumulus
```

### Via conda
```bash
conda install -c bioconda altocumulus
```

### From source
```bash
git clone https://github.com/lilab-bcb/altocumulus.git
cd altocumulus
pip install -e .
```

### Verify Installation
```bash
alto --version
# Expected: 2.3.0 or newer

fissfc --version
# Expected: 0.16.38 or newer

gsutil version
# Expected: 5.35 or newer

alto --help
# Should show available commands
```

**Note:** Installing altocumulus also installs the `firecloud` package which provides `fissfc` (FireCloud CLI). The Google Cloud SDK (including `gsutil`) must be installed separately.

## Command Structure

Altocumulus uses a hierarchical command structure:

```
alto <command> <subcommand> [options]
```

### Available Commands

- `terra` - Terra/FireCloud operations
- `cromwell` - Direct Cromwell server operations
- `upload` - Data upload utilities  
- `parse_monitoring_log` - Resource monitoring analysis

### Related Tools

- `fissfc` - FireCloud CLI (installed with altocumulus)
- `gsutil` - Google Cloud Storage management (from Google Cloud SDK)
- `bq` - BigQuery CLI (from Google Cloud SDK)
- `gcloud` - Main Google Cloud CLI (from Google Cloud SDK)

## Terra Commands (`alto terra`)

### `alto terra run` - Submit Workflows

Submit workflows to Terra for cloud execution.

**Basic syntax:**
```bash
alto terra run -m METHOD -w WORKSPACE -i INPUT_JSON [options]
```

**Parameters:**
- `-m, --method METHOD` - Workflow specification (required)
- `-w, --workspace WORKSPACE` - Terra workspace (required)
- `-i, --input INPUT_JSON` - WDL input JSON file (required)
- `--bucket-folder FOLDER` - Subdirectory in workspace bucket
- `-o, --upload OUTPUT_JSON` - Upload files and output updated JSON
- `--no-cache` - Disable call caching

#### Method Specifications

**Dockstore format:**
```bash
# organization:collection:name:version
-m "broadinstitute:cumulus:cumulus:1.5.0"

# Version optional (uses default)
-m "broadinstitute:cumulus:cumulus"
```

**Broad Methods Repository format:**
```bash
# namespace/name/version
-m "cumulus/cumulus/43"

# Version optional (uses latest)
-m "cumulus/cumulus"
```

#### Workspace Format

Terra workspaces use `namespace/name` format:
```bash
-w "mylab/altanalyze-analysis"
-w "broad-institute/gtex-analysis"
```

#### Examples

**Basic splicing analysis:**
```bash
alto terra run \
  -m "myorg:altanalyze:splicing:latest" \
  -w "mylab/splicing-workspace" \
  -i workflows/splicing_analysis/inputs/test.json
```

**With file upload and custom bucket folder:**
```bash
alto terra run \
  -m "myorg:altanalyze:splicing:latest" \
  -w "mylab/splicing-workspace" \
  -i local_inputs.json \
  -o uploaded_inputs.json \
  --bucket-folder "batch-2024-08"
```

**Disable caching for debugging:**
```bash
alto terra run \
  -m "myorg:altanalyze:splicing:latest" \
  -w "mylab/splicing-workspace" \
  -i workflows/splicing_analysis/inputs/test.json \
  --no-cache
```

### `alto terra add_method` - Upload Workflows

Add WDL workflows to Broad Methods Repository.

**Syntax:**
```bash
alto terra add_method -n NAMESPACE [-p] WDL_FILE [WDL_FILE ...]
```

**Parameters:**
- `-n, --namespace NAMESPACE` - Methods repository namespace (required)
- `-p, --public` - Make method publicly readable
- `WDL_FILE` - Path to WDL workflow file(s)

**Examples:**
```bash
# Add single workflow
alto terra add_method \
  -n altanalyze-methods \
  workflows/splicing_analysis/splicing_analysis.wdl

# Add multiple workflows as public
alto terra add_method \
  -n altanalyze-methods \
  -p \
  workflows/splicing_analysis/splicing_analysis.wdl \
  workflows/star_alignment/star_alignment.wdl
```

**Note:** Requires appropriate permissions for the specified namespace.

### `alto terra remove_method` - Remove Workflows

Remove workflows from Broad Methods Repository.

**Syntax:**
```bash
alto terra remove_method -n NAMESPACE -m METHOD_NAME [-v VERSION]
```

### `alto terra storage_estimate` - Cost Analysis

Export workspace storage cost estimates.

**Syntax:**
```bash
alto terra storage_estimate --output OUTPUT_FILE [--access ACCESS_LEVEL]
```

**Parameters:**
- `--output OUTPUT_FILE` - TSV file for results (required)
- `--access {owner,reader,writer}` - Workspace access level filter

**Examples:**
```bash
# All workspaces with owner access
alto terra storage_estimate \
  --output storage_costs.tsv \
  --access owner

# All accessible workspaces
alto terra storage_estimate \
  --output all_workspaces.tsv
```

**Output format (TSV):**
```
namespace	name	estimate
mylab	workspace1	$12.45
mylab	workspace2	$3.21
```

## Cromwell Commands (`alto cromwell`)

For direct Cromwell server interaction (local installations, custom servers).

### Available Subcommands

- `run` - Submit workflow
- `check_status` - Check job status
- `abort` - Abort running job
- `get_metadata` - Get job metadata
- `get_task_status` - Get task-level status
- `get_logs` - Retrieve job logs
- `list_jobs` - List jobs on server
- `timing` - Get timing information

### `alto cromwell run` - Submit to Cromwell

**Syntax:**
```bash
alto cromwell run -s SERVER -m METHOD -i INPUT [options]
```

**Parameters:**
- `-s, --server SERVER` - Cromwell server hostname/IP (required)
- `-p, --port PORT` - Port number (default: 8000)
- `-m, --method METHOD` - Workflow specification (required)
- `-i, --input INPUT` - Input JSON file (required)
- `-o, --upload OUTPUT_JSON` - Upload files and output updated JSON
- `-b, --bucket BUCKET_URL` - Cloud bucket for uploads
- `--no-cache` - Disable call caching
- `--no-ssl-verify` - Disable SSL verification
- `--time-out HOURS` - Wait timeout in hours
- `--job-id OUTPUT_FILE` - Write job ID to file

#### Method Formats for Cromwell

**Dockstore:**
```bash
-m "organization:collection:name:version"
```

**HTTP/HTTPS URL:**
```bash
-m "https://raw.githubusercontent.com/user/repo/main/workflow.wdl"
```

**Local file:**
```bash
-m "/path/to/workflow.wdl"
```

**Example:**
```bash
alto cromwell run \
  -s cromwell.mylab.edu \
  -p 8080 \
  -m "workflows/splicing_analysis/splicing_analysis.wdl" \
  -i workflows/splicing_analysis/inputs/test.json \
  -b gs://my-bucket/cromwell-uploads \
  --job-id job.id
```

### `alto cromwell list_jobs` - List Jobs

**Syntax:**
```bash
alto cromwell list_jobs -s SERVER [options]
```

**Parameters:**
- `-s, --server SERVER` - Cromwell server (required)
- `-p, --port PORT` - Port (default: 8000)
- `-a, --all` - List all jobs on server
- `-u, --user USER` - Filter by user
- `--only-succeeded` - Only successful jobs
- `--only-running` - Only running jobs  
- `--only-failed` - Only failed/aborted jobs
- `-n NUM_SHOWN` - Limit results

**Examples:**
```bash
# List your recent jobs
alto cromwell list_jobs -s cromwell-server.com

# List all running jobs
alto cromwell list_jobs -s cromwell-server.com -a --only-running

# List last 10 failed jobs for user
alto cromwell list_jobs \
  -s cromwell-server.com \
  -u john.doe@example.com \
  --only-failed \
  -n 10
```

### `alto cromwell check_status` - Job Status

**Syntax:**
```bash
alto cromwell check_status -s SERVER -j JOB_ID
```

### `alto cromwell get_logs` - Retrieve Logs

**Syntax:**
```bash
alto cromwell get_logs -s SERVER -j JOB_ID
```

## File Upload (`alto upload`)

Utilities for uploading data to cloud storage.

**Check help:**
```bash
alto upload --help
```

## FireCloud CLI (`fissfc`) Integration

FISS (FireCloud Service Selector) provides granular control over Terra workspaces and methods.

### Key FISS Commands

#### Workspace Management
```bash
# List accessible workspaces
fissfc space_list

# List workspaces in specific project
fissfc space_list -p project-name

# Get workspace information (including bucket)
fissfc space_info -w workspace-name -p project-name

# Create new workspace
fissfc space_new -w new-workspace -p project-name

# Delete workspace
fissfc space_delete -w workspace-name -p project-name
```

#### Project/Namespace Management
```bash
# List accessible projects
fissfc proj_list

# Get project information
fissfc space_search -p project-name
```

#### Method Management
```bash
# List available methods
fissfc meth_list

# Search for specific methods
fissfc meth_list -n namespace-name

# Get method information
fissfc meth_exists -n namespace -m method-name

# Delete method
fissfc meth_delete -n namespace -m method-name -s snapshot-id
```

#### Configuration Management
```bash
# List workflow configurations
fissfc config_list -w workspace -p project

# Get configuration details
fissfc config_get -w workspace -p project -c config-name

# Start workflow
fissfc config_start -w workspace -p project -c config-name
```

#### Monitoring
```bash
# Monitor workspace activity
fissfc monitor -w workspace -p project

# List running submissions
fissfc space_info -w workspace -p project
```

## Google Cloud Storage (`gsutil`) Integration

Terra workspaces use Google Cloud Storage buckets for data management.

### Essential gsutil Commands

#### Basic Operations
```bash
# List bucket contents
gsutil ls gs://bucket-name/

# List with details (size, date)
gsutil ls -l gs://bucket-name/

# List recursively
gsutil ls -r gs://bucket-name/

# Copy single file
gsutil cp local-file.txt gs://bucket-name/path/

# Copy directory
gsutil cp -r local-directory/ gs://bucket-name/path/
```

#### Efficient Data Transfer
```bash
# Parallel transfers (much faster for many files)
gsutil -m cp -r large-dataset/ gs://bucket-name/

# Sync directories (only copies changed files)
gsutil -m rsync -r -d local-dir/ gs://bucket-name/remote-dir/

# Resume interrupted transfers
gsutil -o 'GSUtil:resumable_threshold=1048576' cp large-file.bam gs://bucket/
```

#### Workspace Integration
```bash
# Find your workspace bucket from Terra UI or:
fissfc space_info -w workspace-name -p project-name | grep bucket

# Copy workflow inputs to workspace
gsutil cp -r input-data/ gs://fc-{workspace-uuid}/inputs/

# Download workflow results
gsutil -m cp -r gs://fc-{workspace-uuid}/outputs/ ./results/

# Monitor transfer progress
gsutil -m cp -r data/ gs://bucket/ 2>&1 | grep -E "(Copying|Uploading)"
```

#### Data Management
```bash
# Check bucket size and costs
gsutil du -sh gs://bucket-name/

# Set lifecycle policies (auto-delete old files)
gsutil lifecycle set lifecycle.json gs://bucket-name/

# Make files publicly readable (if needed)
gsutil acl ch -r -u AllUsers:R gs://bucket-name/public-data/

# Remove files
gsutil rm gs://bucket-name/unwanted-file.txt
gsutil rm -r gs://bucket-name/unwanted-directory/
```

#### Performance and Monitoring
```bash
# Test network performance
gsutil perfdiag gs://bucket-name/

# Check gsutil configuration
gsutil version -l

# Enable/disable progress indicators
gsutil -o GSUtil:enable_progress_reporter=True cp large-file gs://bucket/
```

### Integration Workflows

#### Complete Data Pipeline
```bash
# 1. Find your workspace and bucket
fissfc space_list -p my-project
fissfc space_info -w my-workspace -p my-project

# 2. Upload input data
gsutil -m cp -r ./bam-files/ gs://fc-{workspace-uuid}/inputs/

# 3. Submit workflow with Alto
alto terra run \
  -m "namespace/method/version" \
  -w "my-project/my-workspace" \
  -i input.json

# 4. Download results
gsutil -m cp -r gs://fc-{workspace-uuid}/outputs/ ./results/
```

#### Workspace Backup
```bash
# Backup entire workspace
gsutil -m cp -r gs://fc-{workspace-uuid}/ ./backup-$(date +%Y%m%d)/

# Backup specific analysis
gsutil -m cp -r gs://fc-{workspace-uuid}/analysis-2024/ ./analysis-backup/
```

## Advanced Usage

### Working with Input Files

#### Local File Detection

Alto automatically detects local files in input JSON and uploads them:

**Original input JSON:**
```json
{
  "workflow.input_bam": "/local/path/sample.bam",
  "workflow.input_reference": "/local/path/genome.fa"
}
```

**After upload (with `-o updated.json`):**
```json
{
  "workflow.input_bam": "gs://workspace-bucket/uploads/sample.bam",
  "workflow.input_reference": "gs://workspace-bucket/uploads/genome.fa"
}
```

#### Custom Upload Locations

**Organize uploads by date:**
```bash
alto terra run \
  -m "workflow" \
  -w "workspace" \
  -i input.json \
  -o uploaded.json \
  --bucket-folder "$(date +%Y-%m-%d)-analysis"
```

#### Pre-upload Files

**Upload files separately:**
```bash
# Upload files first
gsutil cp -r /local/data/* gs://workspace-bucket/data/

# Reference uploaded files in JSON
{
  "workflow.input": "gs://workspace-bucket/data/sample.bam"
}
```

### Monitoring and Debugging

#### Job Tracking

**Save job ID for monitoring:**
```bash
alto cromwell run \
  -s server \
  -m workflow.wdl \
  -i input.json \
  --job-id current-job.id

# Later, check status
JOB_ID=$(cat current-job.id)
alto cromwell check_status -s server -j $JOB_ID
```

#### Resource Monitoring

**Parse monitoring logs:**
```bash
alto parse_monitoring_log --help
```

### Batch Processing

#### Multiple Samples

**Create input JSON for each sample:**
```bash
#!/bin/bash
for sample in sample1 sample2 sample3; do
  # Create input JSON from template
  sed "s/SAMPLE_NAME/$sample/g" template.json > ${sample}_input.json
  
  # Submit workflow
  alto terra run \
    -m "workflow" \
    -w "workspace" \
    -i ${sample}_input.json \
    --bucket-folder "batch-$(date +%Y%m%d)/$sample"
done
```

## Error Handling and Troubleshooting

### Common Errors

#### 1. Authentication Errors
```
ERROR: Could not authenticate with Terra
```

**Solution:**
```bash
gcloud auth login
gcloud auth application-default login
```

#### 2. Method Not Found
```
ERROR: Method 'org:collection:name:version' not found
```

**Solutions:**
- Verify method name spelling and format
- Check method exists in Dockstore/Broad Methods Repository
- Ensure version is correct or omit for default

#### 3. Workspace Access Denied
```
ERROR: Access denied to workspace 'namespace/name'
```

**Solutions:**
- Verify workspace exists and spelling is correct
- Check Terra workspace permissions
- Ensure billing is set up

#### 4. Upload Failures
```
ERROR: Failed to upload file to bucket
```

**Solutions:**
- Check Google Cloud storage permissions
- Verify bucket exists and is accessible
- Test with `gsutil cp` manually

### Debug Mode

**Enable verbose output:**
```bash
# Add -v flag to any command for verbose output
alto -v terra run -m workflow -w workspace -i input.json
```

### Log Locations

**Alto logs:**
```bash
# Check system logs
tail -f ~/.config/altocumulus/logs/alto.log
```

**Cromwell logs:**
```bash
# Server-side logs (if accessible)
alto cromwell get_logs -s server -j job-id
```

## Best Practices

### 1. Organization

**Workspace naming:**
- Use descriptive names: `mylab-rnaseq-2024`
- Include date/version: `gtex-analysis-v2.1`
- Group related analyses: `covid-samples-batch1`

**Method versioning:**
- Tag versions: `altanalyze:splicing:v1.6.25`
- Use semantic versioning
- Document changes between versions

### 2. Cost Management

**Monitor storage:**
```bash
# Regular storage checks
alto terra storage_estimate --output monthly-costs.tsv --access owner
```

**Optimize resources:**
- Use preemptible instances when possible
- Right-size CPU/memory requirements
- Clean up intermediate files

### 3. Security

**Workspace access:**
- Use principle of least privilege
- Regular access reviews
- Separate sensitive data workspaces

**Credential management:**
- Don't embed credentials in code
- Use service accounts for automation
- Regular credential rotation

### 4. Documentation

**Track analyses:**
- Document input parameters
- Save workflow versions used
- Record analysis dates and purposes

## Integration Examples

### Automation Examples

**Simple batch script:**
```bash
#!/bin/bash
# Process multiple samples

for sample in sample1 sample2 sample3; do
    # Create input JSON for each sample
    sed "s/SAMPLE_PLACEHOLDER/$sample/g" template.json > ${sample}.json
    
    # Submit workflow
    alto terra run \
        -m "namespace/method/version" \
        -w "username/workspace" \
        -i ${sample}.json \
        --bucket-folder "batch-$(date +%Y%m%d)"
done
```

For CI/CD integration, see the authentication guide for service account setup.

---

## Production Workflow Management & Monitoring

This section covers real-world workflow management based on successful GTEx data processing experience.

### **Complete Workflow Lifecycle**

#### 1. Upload Workflow to Terra
```bash
# Upload WDL to Broad Methods Repository
alto terra add_method -n "$NAMESPACE" workflows/splicing_analysis/splicing_analysis.wdl
# Output: Method URL and version number

# List your uploaded methods
fissfc meth_list -n "$NAMESPACE"
# Shows: namespace method_name version_number
```

#### 2. Submit Production Jobs
```bash
# Submit with real data
alto terra run \
  -m "$NAMESPACE/splicing_analysis/1" \
  -w "$WORKSPACE_PROJECT/$WORKSPACE_NAME" \
  -i "workflows/splicing_analysis/inputs/gtex_v10_validated/cervix_uteri_55.json" \
  --bucket-folder "gtex-cervix-$(date +%Y%m%d-%H%M)"

# Returns: Terra job monitoring URL
# Example: https://app.terra.bio/#workspaces/AltAnalyze3_SNAF/AltAnalyze3_SNAF/job_history/896f0b24-49e7-4198-b1f3-6ea942618c58
```

#### 3. Real-time Monitoring
```bash
# Monitor active submissions
fissfc monitor -w "$WORKSPACE_NAME" -p "$WORKSPACE_PROJECT" | head -5
# Shows: status, submission_id, workflow_statuses, dates

# Check specific submission details
curl -X GET "https://api.firecloud.org/api/workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME/submissions/SUBMISSION_ID" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" | python3 -m json.tool

# Monitor cost accumulation
alto terra storage_estimate --output current_costs.tsv --access owner
```

### **Advanced Monitoring Commands**

#### Submission Status Tracking
```bash
# Live submission monitoring (refresh every 30 seconds)
watch -n 30 'fissfc monitor -w WORKSPACE -p PROJECT | head -3'

# Get workflow execution details  
SUBMISSION_ID="your-submission-id"
curl -X GET "https://api.firecloud.org/api/workspaces/NAMESPACE/WORKSPACE/submissions/$SUBMISSION_ID/workflows/WORKFLOW_ID" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" | python3 -m json.tool | grep -A 10 -B 10 "status\|failure"
```

#### Log Access & Analysis
```bash
# List submission files
gsutil ls "gs://WORKSPACE_BUCKET/submissions/SUBMISSION_ID/"

# Get workflow logs
gsutil cat "gs://WORKSPACE_BUCKET/submissions/SUBMISSION_ID/workflow.logs/workflow.*.log"

# Check task-specific outputs
gsutil ls -r "gs://WORKSPACE_BUCKET/submissions/SUBMISSION_ID/WORKFLOW_NAME/"

# Download results
gsutil -m cp -r "gs://WORKSPACE_BUCKET/submissions/SUBMISSION_ID/WORKFLOW_NAME/" ./results/
```

#### Performance & Cost Analysis
```bash
# Real-time cost monitoring
echo "Monitoring costs every 60 seconds..."
while true; do
  echo "$(date): Checking workspace costs..."
  alto terra storage_estimate --output temp_costs.tsv --access owner
  cat temp_costs.tsv
  sleep 60
done

# Detailed resource usage
gsutil ls -l "gs://WORKSPACE_BUCKET/submissions/" | grep "$(date +%Y-%m-%d)" | awk '{sum+=$1} END{print "Today: " sum/1000000000 " GB"}'
```

### **Batch Processing Patterns**

#### GTEx Large-scale Processing
```bash
#!/bin/bash
# Process validated GTEx tissues in batches

TISSUES=(
  "cervix_uteri_55" 
  "adipose_tissue_1480"
  "skin_2292"
  "esophagus_1831"
)

for tissue in "${TISSUES[@]}"; do
  echo "Processing GTEx $tissue..."
  
  # Submit workflow
  URL=$(alto terra run \
    -m "$NAMESPACE/splicing_analysis/1" \
    -w "$WORKSPACE_PROJECT/$WORKSPACE_NAME" \
    -i "workflows/splicing_analysis/inputs/gtex_v10_validated/${tissue}.json" \
    --bucket-folder "gtex-batch-$(date +%Y%m%d)/$tissue")
  
  echo "Submitted: $URL"
  
  # Extract submission ID for monitoring
  SUBMISSION_ID=$(echo "$URL" | sed 's/.*job_history\///')
  echo "Monitoring: $SUBMISSION_ID"
  
  # Optional: Wait for completion before next tissue
  # (Remove this for parallel processing)
  echo "Waiting 5 minutes before next submission..."
  sleep 300
done
```

#### Automated Success/Failure Handling
```bash
#!/bin/bash
# Check batch job status and handle results

check_workflow_status() {
  local submission_id=$1
  
  # Get status via API
  status=$(curl -s -X GET \
    "https://api.firecloud.org/api/workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME/submissions/$submission_id" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['workflows'][0]['status'])")
  
  case $status in
    "Succeeded")
      echo "✅ $submission_id: SUCCESS"
      # Download results
      gsutil -m cp -r "gs://WORKSPACE_BUCKET/submissions/$submission_id/" "./results/$submission_id/"
      ;;
    "Failed")
      echo "❌ $submission_id: FAILED"
      # Get failure logs
      gsutil cat "gs://WORKSPACE_BUCKET/submissions/$submission_id/workflow.logs/workflow.*.log" > "failures/$submission_id.log"
      ;;
    "Running")
      echo "🔄 $submission_id: RUNNING"
      ;;
    *)
      echo "⚠️  $submission_id: $status"
      ;;
  esac
}

# Monitor multiple submissions
SUBMISSION_IDS=(
  "896f0b24-49e7-4198-b1f3-6ea942618c58"
  # Add more IDs
)

for id in "${SUBMISSION_IDS[@]}"; do
  check_workflow_status "$id"
done
```

### **Troubleshooting & Recovery**

#### Common Issues & Solutions
```bash
# 1. Input validation errors
# Problem: "Extra inputs: SplicingAnalysis.junction_analysis_disk_space"
# Solution: Clean input JSON to match WDL exactly

# 2. File not found errors  
# Problem: "FileNotFoundException: gs://bucket/file.bam"
# Solution: Verify file exists and permissions
gsutil ls "gs://bucket/file.bam"
gsutil acl get "gs://bucket/file.bam"

# 3. Memory/disk failures
# Problem: "Task failed with exit code 137 (out of memory)"
# Solution: Increase resource allocations in WDL or input JSON

# 4. Preemptible instance failures
# Problem: Multiple preemptions causing task failures
# Solution: Reduce preemptible setting or increase max_retries
```

#### Method Version Management  
```bash
# List all versions of a method
fissfc meth_list -n YOUR_NAMESPACE | grep method_name

# Update to newer version
alto terra add_method -n "$NAMESPACE" workflows/splicing_analysis/splicing_analysis.wdl
# Creates version 2, 3, etc.

# Use specific version
alto terra run -m "$NAMESPACE/splicing_analysis/2" -w "$WORKSPACE_PROJECT/$WORKSPACE_NAME" -i input.json

# Use latest version (omit version number)  
alto terra run -m "$NAMESPACE/splicing_analysis" -w "$WORKSPACE_PROJECT/$WORKSPACE_NAME" -i input.json
```

### **Production Checklist**

Before large-scale processing:
- [ ] Test with 2-3 samples first
- [ ] Validate input JSON matches WDL parameters exactly  
- [ ] Confirm data file accessibility via `gsutil ls`
- [ ] Set up cost monitoring and alerts
- [ ] Plan result storage and archival strategy
- [ ] Configure appropriate retry and preemptible settings
- [ ] Have monitoring scripts ready for batch processing

**Real Production Example:**
- Successfully processing GTEx Cervix Uteri 55 samples
- Job URL: https://app.terra.bio/#workspaces/AltAnalyze3_SNAF/AltAnalyze3_SNAF/job_history/896f0b24-49e7-4198-b1f3-6ea942618c58  
- Status tracking: `{'Running': 1}` via `fissfc monitor`
- Cost: Real-time tracking via `alto terra storage_estimate`

---

For authentication setup, see [AUTHENTICATION.md](./AUTHENTICATION.md).
For complete setup instructions, see [SETUP.md](./SETUP.md).