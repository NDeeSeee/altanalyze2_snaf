# FireCloud/Terra Setup Guide

This guide covers the setup and configuration of FireCloud (Terra's backend API) for running AltAnalyze2 SNAF workflows through Altocumulus.

## Understanding FireCloud and Terra

### What is FireCloud?
- **FireCloud** is the backend API that powers Terra
- **Terra** is the web interface for cloud-based genomics analysis
- **Altocumulus** interacts with FireCloud APIs behind the scenes
- Users primarily work through Terra's web interface or Alto commands

### Relationship Between Components

```
User/Alto → FireCloud API → Google Cloud → Cromwell → Docker Containers
     ↓
Terra Web Interface → Same FireCloud API
```

## Terra Account Setup

### Step 1: Create Terra Account

1. **Visit Terra**: Go to [terra.bio](https://terra.bio)
2. **Sign In**: Use your Google account (same one used for gcloud)
3. **Accept Terms**: Complete the Terra registration process
4. **Profile Setup**: Complete your user profile

### Step 2: Billing Setup

**Critical**: Terra requires a Google Cloud billing account for all operations.

1. **Navigate to Billing**: In Terra, go to "Billing" in the user menu
2. **Create/Link Billing Project**: 
   - Create new Google Cloud project with billing enabled, OR
   - Link existing project with billing enabled
3. **Verify Billing**: Ensure billing is active and has payment method

**Command-line billing verification:**
```bash
# Check if project has billing enabled
gcloud beta billing projects describe YOUR_PROJECT_ID

# List available billing accounts
gcloud beta billing accounts list
```

### Step 3: Workspace Creation

#### Via Terra Web Interface (Recommended)

1. **Navigate to Workspaces**: Click "Workspaces" in Terra
2. **Create New Workspace**:
   - **Namespace**: Your username (e.g., "john-doe")
   - **Name**: Descriptive name (e.g., "altanalyze-splicing")  
   - **Billing Project**: Select your configured Google Cloud project
   - **Description**: Optional description of your analysis
   - **Authorization Domain**: Leave empty unless using controlled-access data

#### Automatic Creation via Alto

Workspaces are created automatically during workflow submission if they don't exist.

## FireCloud API Configuration

### Authentication Flow

The authentication flow for FireCloud API access:

1. **User Authentication**: `gcloud auth login`
2. **Application Credentials**: `gcloud auth application-default login`
3. **FireCloud Token**: Alto automatically handles FireCloud token exchange
4. **API Access**: Alto makes authenticated requests to FireCloud APIs

### Related Google Cloud Tools

Several command-line tools work together in the Terra ecosystem:

#### Google Cloud SDK Tools
```bash
# Main Google Cloud CLI
gcloud auth login
gcloud config set project PROJECT_ID

# Google Cloud Storage management  
gsutil ls gs://bucket-name/
gsutil cp file.txt gs://bucket-name/

# BigQuery CLI (for data analysis)
bq query "SELECT * FROM dataset.table LIMIT 10"

# Container Registry authentication
gcloud auth configure-docker
```

#### FireCloud-Specific Tools
```bash
# FISS (FireCloud Service Selector) - installed with altocumulus
fissfc space_list
fissfc meth_list

# Alto (Altocumulus) - high-level workflow submission
alto terra run -m method -w workspace -i input.json
```

#### Integration Example
```bash
# Complete workflow with all tools:

# 1. Authenticate
gcloud auth login
gcloud auth application-default login

# 2. Find workspace and bucket
fissfc space_list -p my-project
fissfc space_info -w my-workspace -p my-project

# 3. Upload data
gsutil -m cp -r data/ gs://fc-workspace-uuid/inputs/

# 4. Submit workflow
alto terra run -m "ns/method/v1" -w "project/workspace" -i input.json

# 5. Download results  
gsutil -m cp -r gs://fc-workspace-uuid/outputs/ ./results/
```

### API Endpoints

FireCloud uses these main API endpoints:
- **Production**: `https://api.firecloud.org/api/`
- **Staging**: `https://firecloud-orchestration.dsde-dev.broadinstitute.org/api/`

Alto automatically uses the production endpoint.

### Scopes and Permissions

Required Google OAuth scopes for FireCloud access:
```
https://www.googleapis.com/auth/userinfo.email
https://www.googleapis.com/auth/userinfo.profile
https://www.googleapis.com/auth/cloud-platform
```

These are automatically requested during `gcloud auth` setup.

## Workspace Configuration

### Workspace Structure

Terra workspaces contain:
- **Data**: Input files, reference data
- **Methods**: WDL workflows
- **Method Configurations**: Workflow parameter sets
- **Submissions**: Running/completed workflow executions
- **Notebooks**: Jupyter notebooks for analysis

### Google Cloud Storage Integration

Each Terra workspace has an associated Google Cloud Storage bucket:

**Bucket naming pattern:**
```
fc-{uuid}
```

**Access workspace bucket:**
```bash
# List workspace files
gsutil ls gs://fc-{workspace-uuid}/

# Upload files directly
gsutil cp local-file.txt gs://fc-{workspace-uuid}/uploads/
```

**Find workspace bucket UUID:**
```bash
# From Terra UI: Workspace → Cloud Information → Google Bucket
# From Alto: Check workflow submission outputs
```

### Access Control

#### Workspace Sharing

1. **Owner**: Full control, can delete workspace
2. **Writer**: Can run workflows, modify data
3. **Reader**: Can view workspace, cannot modify

**Share workspace via Terra UI:**
1. Navigate to workspace
2. Click "Share" button  
3. Add users by email with appropriate role

#### Authorization Domains

For controlled-access data:
1. **Create Authorization Domain** in Terra
2. **Add workspace to domain** during creation
3. **Users must be members** of domain to access

### Data Organization

#### Recommended Structure

```
workspace-bucket/
├── inputs/
│   ├── bam-files/
│   ├── reference-data/
│   └── sample-metadata/
├── outputs/
│   ├── 2024-08-25-batch1/
│   └── 2024-08-26-batch2/
├── methods/
│   └── altanalyze-configs/
└── notebooks/
    └── analysis-reports/
```

#### Upload Strategies

**Via Alto (automatic):**
```bash
alto terra run \
  -m method \
  -w workspace \
  -i input-with-local-files.json \
  -o uploaded-input.json \
  --bucket-folder "batch-$(date +%Y%m%d)"
```

**Via gsutil (manual):**
```bash
# Upload large datasets
gsutil -m cp -r /local/data/ gs://fc-{workspace-uuid}/inputs/

# Parallel uploads for many files
gsutil -m cp *.bam gs://fc-{workspace-uuid}/bam-files/
```

## Method Configuration

### Adding Methods to Terra

#### Option 1: Via Dockstore Integration

1. **Import from Dockstore**: Terra can import workflows from Dockstore
2. **Automatic Sync**: Changes in Dockstore sync to Terra
3. **Version Management**: Multiple versions available

**Command-line import:**
```bash
# Methods imported from Dockstore are automatically available
alto terra run \
  -m "organization:collection:name:version" \
  -w workspace \
  -i input.json
```

#### Option 2: Via Broad Methods Repository

**Upload method:**
```bash
alto terra add_method \
  -n your-namespace \
  -p \
  workflows/splicing_analysis/splicing_analysis.wdl
```

**Use uploaded method:**
```bash
alto terra run \
  -m "your-namespace/splicing_analysis/1" \
  -w workspace \
  -i input.json
```

#### Option 3: Via Terra Web Interface

1. **Navigate to Methods**: In Terra, go to "Methods"
2. **Import Method**: 
   - From Dockstore: Provide Dockstore URL
   - Upload WDL: Direct file upload
3. **Create Configuration**: Set default parameters

### Method Configurations

Method configurations define default parameters and input/output mappings.

**Configuration JSON structure:**
```json
{
  "name": "altanalyze-default-config",
  "namespace": "mylab",
  "methodConfigVersion": 1,
  "methodRepoMethod": {
    "methodNamespace": "mylab",
    "methodName": "altanalyze-splicing", 
    "methodVersion": 1
  },
  "inputs": {
    "SplicingAnalysis.bam_files": "this.bam_paths",
    "SplicingAnalysis.species": "\"Hs\""
  },
  "outputs": {
    "SplicingAnalysis.results": "this.splicing_results"
  }
}
```

## Workflow Execution

### Submission Process

1. **Method Selection**: Choose workflow from Methods Repository
2. **Configuration**: Set input parameters and output locations
3. **Validation**: Terra validates inputs and method
4. **Submission**: Workflow submitted to Google Cloud via Cromwell
5. **Monitoring**: Track progress through Terra UI or Alto commands

### Cromwell Integration

Terra uses Cromwell as the workflow execution engine:

**Cromwell features in Terra:**
- **Call Caching**: Reuse previous results for identical calls
- **Preemptible Instances**: Use cheaper, interruptible VMs
- **Auto-scaling**: Dynamically provision compute resources
- **Retry Logic**: Automatic retry of failed tasks

### Resource Management

#### Compute Resources

**Default instance types:**
- **Small tasks**: n1-standard-1 (1 vCPU, 3.75 GB RAM)
- **Medium tasks**: n1-standard-4 (4 vCPU, 15 GB RAM)  
- **Large tasks**: n1-standard-16 (16 vCPU, 60 GB RAM)

**Preemptible instances:**
- **Cost**: ~80% cheaper than regular instances
- **Limitation**: Can be interrupted with 30-second notice
- **Best for**: Fault-tolerant, non-urgent workloads

#### Storage Resources

**Disk types:**
- **HDD (pd-standard)**: Cheaper, slower (~$0.04/GB/month)
- **SSD (pd-ssd)**: Faster, more expensive (~$0.17/GB/month)

**Disk sizing:**
- **Input files**: Size based on input data
- **Working space**: 2-3x input size for intermediate files
- **Output space**: Estimated output size

## Monitoring and Troubleshooting

### Terra UI Monitoring

**Workspace Dashboard:**
- Recent submissions
- Storage usage
- Cost estimates
- Shared users

**Submission Details:**
- Workflow progress
- Task-level status  
- Execution logs
- Resource utilization

### Alto Command Monitoring

**Check submission status:**
```bash
# List recent jobs (requires custom Cromwell setup)
alto cromwell list_jobs -s your-cromwell-server

# Get detailed job information
alto cromwell get_metadata -s server -j job-id
```

### Common Issues and Solutions

#### 1. Authentication Problems

**Symptoms:**
- "Authentication failed" errors
- "Access denied" messages

**Solutions:**
```bash
# Re-authenticate
gcloud auth login
gcloud auth application-default login

# Verify authentication
gcloud auth list
gcloud config list
```

#### 2. Billing Issues

**Symptoms:**
- Workflows fail to start
- "Billing not enabled" errors

**Solutions:**
- Verify billing account is linked in Terra
- Check Google Cloud Console for billing status
- Ensure payment method is valid

#### 3. Workspace Access

**Symptoms:**
- "Workspace not found" errors
- Permission denied on workspace operations

**Solutions:**
- Verify workspace name spelling
- Check workspace sharing settings
- Ensure you're using correct Google account

#### 4. Method Not Found

**Symptoms:**
- "Method does not exist" errors
- "Invalid method reference"

**Solutions:**
- Verify method name and version
- Check method exists in Dockstore or Methods Repository
- Ensure method is publicly accessible

#### 5. Resource Limits

**Symptoms:**
- Tasks fail with out-of-memory errors
- Disk space exhausted

**Solutions:**
- Increase memory allocation in WDL
- Use larger disk sizes
- Consider SSD for I/O intensive tasks

### Log Analysis

**Terra submission logs:**
- Available through Terra UI
- Contain Cromwell execution details
- Include task-level stdout/stderr

**Google Cloud logs:**
```bash
# View Cromwell logs
gcloud logging read 'resource.type="cromwell_workflow"'

# Monitor compute instance logs
gcloud logging read 'resource.type="gce_instance"'
```

## Security and Compliance

### Data Protection

**Encryption:**
- Data encrypted at rest in Google Cloud Storage
- Data encrypted in transit between services
- Terra uses Google Cloud's encryption keys

**Access Control:**
- Integration with Google Identity and Access Management (IAM)
- Workspace-level permissions
- Authorization domains for controlled access

### Compliance Features

**HIPAA Compliance:**
- Available for healthcare data
- Requires BAA (Business Associate Agreement)
- Enhanced logging and audit trails

**Data Residency:**
- Choose Google Cloud regions for data storage
- Compliance with regional data protection laws

### Best Practices

1. **Regular Access Reviews**: Audit workspace permissions
2. **Data Classification**: Use authorization domains for sensitive data
3. **Audit Logging**: Monitor workspace activity
4. **Backup Strategies**: Regular data backups to separate locations

## Advanced Configuration

### Custom Cromwell Configuration

For organizations running their own Cromwell:

**Cromwell configuration file:**
```hocon
# cromwell.conf
include required(classpath("application"))

cromwell {
  backend {
    default = "GooglePAPI"
    providers {
      GooglePAPI {
        actor-factory = "cromwell.backend.google.pipelines.v2alpha1.PipelinesApiLifecycleActorFactory"
        config {
          project = "your-project-id"
          root = "gs://your-cromwell-bucket"
          compute-service-account = "cromwell@your-project.iam.gserviceaccount.com"
        }
      }
    }
  }
}
```

### Service Account Setup

For automated workflows:

**Create Terra-specific service account:**
```bash
gcloud iam service-accounts create terra-runner \
  --description="Service account for Terra workflow submission" \
  --display-name="Terra Runner"

# Grant necessary permissions
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:terra-runner@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/genomics.pipelinesRunner"

gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:terra-runner@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"
```

## Cost Optimization

### Monitoring Costs

**Regular cost checks:**
```bash
# Get storage estimates
alto terra storage_estimate --output costs.tsv --access owner

# Review monthly costs in Google Cloud Console
gcloud billing budgets list --billing-account=BILLING_ACCOUNT_ID
```

### Cost-Saving Strategies

1. **Use Preemptible Instances**: 80% cost reduction
2. **Right-size Resources**: Match CPU/memory to actual needs
3. **Clean Up Data**: Remove intermediate files regularly
4. **Use Regional Storage**: Choose cost-effective regions
5. **Optimize Workflows**: Reduce redundant computations

### Budget Alerts

**Set up billing alerts:**
```bash
gcloud billing budgets create \
  --billing-account=BILLING_ACCOUNT_ID \
  --display-name="Terra Workspace Budget" \
  --budget-amount=1000USD \
  --threshold-rule=percent:50 \
  --threshold-rule=percent:90
```

---

For complete setup instructions, see [SETUP.md](./SETUP.md).
For authentication details, see [AUTHENTICATION.md](./AUTHENTICATION.md).
For Alto command reference, see [ALTOCUMULUS_GUIDE.md](./ALTOCUMULUS_GUIDE.md).