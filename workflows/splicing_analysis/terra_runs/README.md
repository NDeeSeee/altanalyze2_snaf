# Terra CLI Commands Reference

This directory contains complete Terra CLI command sequences for running the AltAnalyze splicing analysis workflow on Terra platform.

## Files in this directory:

- **`01_authentication_setup.sh`** - Complete authentication and environment setup
- **`02_workflow_management.sh`** - Upload and manage workflows in Terra
- **`03_job_submission.sh`** - Submit jobs with various input configurations
- **`04_monitoring_commands.sh`** - Monitor workflows, costs, and results
- **`05_batch_processing.sh`** - Large-scale batch processing scripts
- **`06_troubleshooting.sh`** - Common issues and debugging commands

## Quick Start:

```bash
# 1. Set up authentication
source 01_authentication_setup.sh

# 2. Upload workflow to Terra
source 02_workflow_management.sh

# 3. Submit a job
source 03_job_submission.sh

# 4. Monitor progress
source 04_monitoring_commands.sh
```

## Current Status (as of last validation):

- **Recent Job**: GTEx Cervix Uteri analysis (2 samples)
- **Job URL**: https://app.terra.bio/#workspaces/AltAnalyze3_SNAF/AltAnalyze3_SNAF/job_history/896f0b24-49e7-4198-b1f3-6ea942618c58
- **Status**: Submitted and processed; final status reported as Failed (resource-related). Monitoring and cost tracking verified.
- **Observed Cost (pilot)**: ~$0.01 (partial processing)

Commands here are validated end-to-end on real GTEx data for submission, monitoring, and log access. Resource tuning may be required for Succeeded status.