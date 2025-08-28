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
# 0. (One-time) Configure global env
cp workflows/terra/env.example.sh workflows/terra/env.sh
# Edit workflows/terra/env.sh with your workspace details

# 1. (Optional) Run preflight checks
bash workflows/terra/preflight.sh

# 2. Set up authentication
source 01_authentication_setup.sh

# 3. Upload workflow to Terra
source 02_workflow_management.sh

# 4. Submit a job (choose one)
#   a) Via Methods Repository (validated end-to-end)
source 03_job_submission.sh
#   b) Via Terra configuration (GUI-linked to Dockstore)
#      This creates per-run tracking under `terra_runs/runs/`
workflows/splicing_analysis/terra_runs/dockstore_run.sh \
  -c altanalyze_splicing_analysis \
  -i workflows/splicing_analysis/inputs/gtex_v10_validated/cervix_uteri_55.json \
  -d "GTEx cervix 55 (Terra config v1.6.38)"

# 5. Monitor progress
source 04_monitoring_commands.sh
```

## Current Status (as of last validation):

- **Recent Job (config/Dockstore)**: GTEx Cervix Uteri analysis (55 samples)
- **Job URL**: Shown by `dockstore_run.sh` when submitted; also visible in Terra job history
- **Status**: Submitted; monitoring and cost tracking verified

Commands here are validated end-to-end on real GTEx data for submission, monitoring, and log access. Resource tuning may be required for Succeeded status. Default Docker image: `ndeeseee/altanalyze:v1.6.38`.