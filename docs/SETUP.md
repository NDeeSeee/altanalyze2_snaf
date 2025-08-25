# AltAnalyze2 SNAF Workflows - Setup Guide

This guide provides comprehensive setup instructions for running the AltAnalyze2 SNAF workflows using Terra, Altocumulus, and related cloud tools.

## Overview

The AltAnalyze2 SNAF repository provides two main WDL workflows:
- **Splicing analysis with AltAnalyze** (`workflows/splicing_analysis/splicing_analysis.wdl`)
- **STAR 2-pass alignment** (`workflows/star_alignment/star_alignment.wdl`)

These workflows can be run locally with Cromwell or on cloud platforms via Terra using the Altocumulus toolkit.

## Prerequisites

- Python 3.8+ with pip
- Google Cloud SDK  
- Google account with Terra access
- Docker (optional, for local container testing)

## Quick Start

1. [Install Google Cloud SDK](#1-google-cloud-sdk-setup)
2. [Install Altocumulus](#2-altocumulus-installation)
3. [Configure Authentication](#3-authentication-setup)
4. [Setup Terra/FireCloud](#4-terraFireCloud-setup)
5. [Run Workflows](#5-running-workflows)

## Detailed Setup Instructions

### 1. Google Cloud SDK Setup

#### Installation

**macOS (Homebrew):**
```bash
brew install google-cloud-sdk
```

**Linux/macOS (Direct download):**
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

**Windows:**
Download and run the installer from [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)

#### Verification
```bash
gcloud --version
which gcloud
```

### 2. Altocumulus Installation

Altocumulus (alto) is a toolkit for running workflows on cloud platforms including Terra.

#### Installation via pip
```bash
pip install altocumulus
```

#### Installation via conda
```bash
conda install -c bioconda altocumulus
```

#### Verification
```bash
alto --version
alto --help
```

**Expected output:**
```
usage: alto [-h] [-v] {terra,upload,parse_monitoring_log,cromwell,query} ...

Run an altocumulus command.
```

### 3. Authentication Setup

#### Google Cloud Authentication

**Step 1: User Authentication**
```bash
# Login with your Google account
gcloud auth login
```
This opens a browser window for Google OAuth authentication.

**Step 2: Application Default Credentials**
```bash
# Set up application-default credentials for tools to use
gcloud auth application-default login
```
This is required for tools like Alto to access Google Cloud APIs.

**Step 3: Set Default Project** (if needed)
```bash
# List available projects
gcloud projects list

# Set default project
gcloud config set project YOUR_PROJECT_ID
```

**Step 4: Verify Authentication**
```bash
# Check current authentication status
gcloud auth list

# Verify configuration
gcloud config list
```

### 4. Terra/FireCloud Setup

Terra is built on Google Cloud and requires proper setup for workspace access.

#### Terra Account Setup

1. **Create Terra Account**: Visit [terra.bio](https://terra.bio) and sign in with your Google account
2. **Link Billing Account**: In Terra, link a Google Cloud billing account
3. **Create Workspace**: Create a Terra workspace for your analyses

#### FireCloud Integration

FireCloud is Terra's backend API. Alto automatically handles FireCloud interactions.

**Verify Terra Access:**
```bash
# Test workspace storage access (may show empty if no workspaces exist)
alto terra storage_estimate --output workspace_test.tsv --access owner

# Check available methods (if you have access)
alto terra add_method --help
```

### 5. Running Workflows

#### Option A: Via Terra (Recommended for Cloud)

**Basic Command Structure:**
```bash
alto terra run \
  -m "organization:collection:name:version" \
  -w "namespace/workspace-name" \
  -i input.json
```

**Example with Dockstore Workflow:**
```bash
# Using a Dockstore workflow - replace with actual method when available
alto terra run \
  -m "organization:altanalyze:splicing:latest" \
  -w "myusername/altanalyze-workspace" \
  -i workflows/splicing_analysis/inputs/test.json
```

**Example with Broad Methods Repository:**
```bash
# Using Broad Methods Repository - requires uploaded method
alto terra run \
  -m "myusername/altanalyze-splicing/1" \
  -w "myusername/altanalyze-workspace" \
  -i workflows/splicing_analysis/inputs/test.json
```

#### Option B: Via Direct Cromwell

For local Cromwell servers or custom setups:

```bash
alto cromwell run \
  -s your-cromwell-server.com \
  -m "path/to/workflow.wdl" \
  -i input.json
```

#### Adding Workflows to Methods Repository

To make workflows available via Terra:

```bash
alto terra add_method \
  -n your-namespace \
  -p \
  workflows/splicing_analysis/splicing_analysis.wdl
```

**Note:** You need appropriate permissions for the namespace.

## Example Workflows

### Splicing Analysis Example

The repository includes working example inputs. Start with the test configuration:

**Use existing test input:**
```bash
# Use the provided test input as a starting point
cp workflows/splicing_analysis/inputs/test.json my_analysis_input.json

# Edit my_analysis_input.json to point to your actual data files
# Replace the example gs:// paths with your data locations
```

**Basic run command (once method is available):**
```bash
alto terra run \
  -m "method-namespace/splicing-analysis/1" \
  -w "your-username/your-workspace" \
  -i my_analysis_input.json
```

**Note:** You'll need to either:
1. Upload the workflow as a method first using `alto terra add_method`, OR  
2. Use a Dockstore-hosted version of the workflow

### STAR Alignment Example

**Use existing test input:**
```bash
# Use the provided test input as a template
cp workflows/star_alignment/inputs/test.json my_star_input.json

# Edit to point to your FASTQ files and reference data
```

## Troubleshooting

### Common Issues

**1. Authentication Errors**
```bash
# Re-authenticate if needed
gcloud auth application-default revoke
gcloud auth application-default login
```

**2. Workspace Permission Issues**
- Ensure you have appropriate access to Terra workspaces
- Check billing account is linked
- Verify project permissions in Google Cloud Console

**3. Method Not Found**
- Verify method exists in Dockstore or Broad Methods Repository
- Check method name format: `organization:collection:name:version`
- Ensure version is specified or default exists

**4. Storage Issues**
```bash
# Check storage estimates
alto terra storage_estimate --output storage.tsv --access reader

# Verify bucket access
gsutil ls gs://your-workspace-bucket/
```

### Getting Help

- **Alto Documentation**: Run `alto --help` or `alto terra --help`
- **Terra Support**: [support.terra.bio](https://support.terra.bio)
- **Dockstore Documentation**: [docs.dockstore.org](https://docs.dockstore.org)
- **Cromwell Documentation**: [cromwell.readthedocs.io](https://cromwell.readthedocs.io)

## Advanced Configuration

### Custom Docker Images

If using custom containers, ensure they're accessible:
```bash
# Test Docker image access
docker pull ndeeseee/altanalyze:latest
```

### Resource Optimization

Refer to the main [README.md](../README.md) for detailed resource configuration examples.

### Monitoring Jobs

```bash
# List running jobs
alto cromwell list_jobs -s your-server --only-running

# Check job status
alto cromwell check_status -s your-server -j job-id

# Get detailed logs
alto cromwell get_logs -s your-server -j job-id
```

## Security Considerations

- Keep authentication tokens secure
- Use service accounts for automated workflows
- Regular review of workspace permissions
- Monitor cloud costs and resource usage

---

For workflow-specific documentation, see the main [README.md](../README.md).
For container details, see `containers/` subdirectories.