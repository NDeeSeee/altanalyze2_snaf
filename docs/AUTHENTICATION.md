# Authentication Setup Guide

This guide provides detailed instructions for setting up authentication for Google Cloud, Terra, and related services needed for running AltAnalyze2 SNAF workflows.

## Overview

The workflows require authentication for:
- Google Cloud Platform (GCP) - primary requirement
- Terra/FireCloud API access - automatic once GCP is configured
- Docker registries (only if using private/custom images)

## Google Cloud SDK Authentication

### Initial Setup

#### 1. Install Google Cloud SDK

If not already installed, follow platform-specific instructions:

**macOS (Homebrew):**
```bash
brew install google-cloud-sdk
```

**macOS/Linux (curl installer):**
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

**Verify installation:**
```bash
gcloud --version
```

#### 2. Initialize gcloud

```bash
gcloud init
```

This interactive setup will:
- Prompt for Google account login
- Allow project selection
- Set default compute region/zone

### Authentication Commands

#### User Authentication

**Primary login command:**
```bash
gcloud auth login
```

This command:
- Opens browser for OAuth flow
- Stores user credentials locally
- Enables `gcloud` command usage

**Verify current user:**
```bash
gcloud auth list
```

Expected output:
```
     Credentialed Accounts
ACTIVE  ACCOUNT
*       your-email@domain.com
```

#### Application Default Credentials (ADC)

**Critical for Altocumulus:**
```bash
gcloud auth application-default login
```

This command:
- Sets up credentials for applications/SDKs
- Required for Alto to access Google Cloud APIs
- Stores credentials in `~/.config/gcloud/application_default_credentials.json`

**Verify ADC setup:**
```bash
gcloud auth application-default print-access-token
```

If successful, prints an access token.

#### Service Account Authentication (Optional)

For automated/production workflows:

**Create service account:**
```bash
gcloud iam service-accounts create altanalyze-runner \
  --description="Service account for AltAnalyze workflows" \
  --display-name="AltAnalyze Runner"
```

**Generate key file:**
```bash
gcloud iam service-accounts keys create ~/altanalyze-sa-key.json \
  --iam-account=altanalyze-runner@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

**Activate service account:**
```bash
gcloud auth activate-service-account \
  --key-file=~/altanalyze-sa-key.json
```

**Grant necessary permissions:**
```bash
# Storage access for workflow data
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:altanalyze-runner@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Compute access for VM creation
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:altanalyze-runner@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1"
```

### Project Configuration

#### Set Default Project

**List available projects:**
```bash
gcloud projects list
```

**Set default project:**
```bash
gcloud config set project YOUR_PROJECT_ID
```

**Verify configuration:**
```bash
gcloud config list
```

Expected output includes:
```
[core]
account = your-email@domain.com
project = your-project-id
```

**Test gsutil access:**
```bash
# Test basic gsutil functionality
gsutil ls

# Check gsutil version and configuration
gsutil version -l

# Test with your project's buckets
gsutil ls gs://
```

#### Enable Required APIs

```bash
# Enable required Google Cloud APIs
gcloud services enable genomics.googleapis.com
gcloud services enable storage-api.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
```

## Terra Authentication

### Account Setup

1. **Visit Terra**: Go to [terra.bio](https://terra.bio)
2. **Sign in**: Use the same Google account as gcloud
3. **Accept Terms**: Complete Terra registration
4. **Link Billing**: Associate a Google Cloud billing account

### Workspace Access

#### Create Terra Workspace

1. Navigate to [app.terra.bio](https://app.terra.bio)
2. Click "Create New Workspace"
3. Fill in:
   - **Namespace**: Your username or organization
   - **Name**: Descriptive workspace name
   - **Billing Project**: Select your GCP project
   - **Description**: Optional description

#### Test Terra Access

**Check workspace storage:**
```bash
alto terra storage_estimate --output test.tsv --access owner
cat test.tsv
```

**Expected output (if workspaces exist):**
```
namespace	name	estimate
mylab	altanalyze-workspace	$0.50
```

### FireCloud API Access

FireCloud is Terra's backend API. Authentication is handled automatically through gcloud credentials.

**Test FireCloud connectivity:**
```bash
# This command tests FireCloud API access
alto terra add_method --help
```

If authentication works, you'll see help text. If not, you'll get authentication errors.

## Docker Registry Authentication

For custom Docker images or private registries:

### Google Container Registry (GCR)

**Configure Docker for GCR:**
```bash
gcloud auth configure-docker
```

**Test access:**
```bash
docker pull gcr.io/YOUR_PROJECT_ID/your-image:latest
```

### Docker Hub Authentication

**Login to Docker Hub:**
```bash
docker login
```

**For automated workflows, use access tokens instead of passwords.**

## Troubleshooting Authentication

### Common Issues and Solutions

#### 1. "Default credentials not found" error

**Solution:**
```bash
gcloud auth application-default login
```

#### 2. "Permission denied" errors

**Check current authentication:**
```bash
gcloud auth list
gcloud config list
```

**Re-authenticate if needed:**
```bash
gcloud auth login
gcloud auth application-default login
```

#### 3. Wrong project selected

**Set correct project:**
```bash
gcloud config set project CORRECT_PROJECT_ID
```

#### 4. Expired credentials

**Refresh credentials:**
```bash
gcloud auth application-default revoke
gcloud auth application-default login
```

#### 5. Terra workspace access denied

**Verify Terra account:**
- Check billing is set up at [terra.bio](https://terra.bio)
- Ensure you're using the same Google account
- Verify workspace permissions

### Credential File Locations

**User credentials:**
```
~/.config/gcloud/credentials.db
~/.config/gcloud/legacy_credentials/
```

**Application Default Credentials:**
```
~/.config/gcloud/application_default_credentials.json
```

**Service Account keys:**
```
Specified location (e.g., ~/service-account-key.json)
```

### Environment Variables

**Override credential locations:**
```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
export GCLOUD_PROJECT=your-project-id
```

## Security Best Practices

### 1. Credential Management

- **Never commit credentials to version control**
- Use `.gitignore` to exclude credential files
- Rotate service account keys regularly
- Use IAM conditions for fine-grained access

### 2. Principle of Least Privilege

Grant minimal required permissions:

**For workflow execution:**
```bash
# Storage access only
--role="roles/storage.objectViewer"
--role="roles/storage.objectCreator"
```

**For Terra integration:**
```bash
# Genomics pipeline permissions
--role="roles/genomics.pipelinesRunner"
```

### 3. Monitoring and Auditing

**Enable audit logging:**
```bash
gcloud logging sinks create audit-sink \
  bigquery.googleapis.com/projects/YOUR_PROJECT/datasets/audit_logs \
  --log-filter='protoPayload.serviceName="storage.googleapis.com"'
```

**Monitor credential usage:**
```bash
gcloud logging read 'protoPayload.authenticationInfo.principalEmail="your-service-account@project.iam.gserviceaccount.com"'
```

### 4. Automated Workflows

For CI/CD or automated workflows:

**Use GitHub Actions secrets:**
```yaml
# .github/workflows/workflow.yml
env:
  GOOGLE_APPLICATION_CREDENTIALS: ${{ secrets.GCP_SA_KEY }}
```

**Use service accounts instead of user credentials**

## Verification Checklist

Before running workflows, verify:

- [ ] `gcloud auth list` shows correct account
- [ ] `gcloud config list` shows correct project  
- [ ] `gcloud auth application-default print-access-token` works
- [ ] `alto --version` command works
- [ ] Terra account is set up and billing is linked
- [ ] Required Google Cloud APIs are enabled
- [ ] Docker authentication is configured (if using custom images)

## Getting Help

If authentication issues persist:

1. **Google Cloud Console**: Check IAM permissions
2. **Terra Support**: [support.terra.bio](https://support.terra.bio)
3. **Alto Documentation**: Run `alto --help`
4. **Google Cloud Documentation**: [cloud.google.com/docs](https://cloud.google.com/docs)

---

Next: Proceed to [SETUP.md](./SETUP.md) for complete workflow setup instructions.