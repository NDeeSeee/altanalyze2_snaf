# Terra CLI Commands Reference (with Nextflow alternative)

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
  -d "GTEx cervix 55 (Terra config v1.6.39)"

# 5. Monitor progress
source 04_monitoring_commands.sh

## Alternative: Nextflow on Google Batch (same containers, GCP‑local)

If you prefer a non‑Terra runner while keeping data on GCP, use the experimental Nextflow pipeline that mirrors this WDL:

```bash
# Generate pairs.csv from a WDL JSON (optional helper)
python workflows/nextflow/make_pairs_csv.py \
  --wdl-json workflows/splicing_analysis/inputs/gtex_v10_validated/cervix_uteri_55_partial.json \
  --output pairs.csv

# Run on Google Batch (edit project/workDir/location in nextflow.config)
nextflow run workflows/nextflow/splicing_analysis.nf \
  --pairs_csv gs://$WORKSPACE_BUCKET/pairs.csv \
  --outdir gs://$WORKSPACE_BUCKET/nextflow-runs/$(date +%Y%m%d-%H%M%S) \
  -profile google_batch
```

See `docs/NEXTFLOW.md` for details.
```

## Current Status (as of last validation):

- **Recent Job (config/Dockstore)**: GTEx Cervix Uteri analysis (55 samples)
- **Job URL**: Shown by `dockstore_run.sh` when submitted; also visible in Terra job history
- **Status**: Submitted; monitoring and cost tracking verified

Commands here are validated end-to-end on real GTEx data for submission, monitoring, and log access. Resource tuning may be required for Succeeded status. Default Docker image: `ndeeseee/altanalyze:v1.6.39`.

## Cost optimization: preemptibles vs retries

- Earlier GTEx cervix (55 shards) finished BamToBed and failed in RunJunctions with estimated cost ~$1.2 while using preemptibles (cheaper VMs):
  - `SplicingAnalysis.bam_to_bed_preemptible: 3`, `bam_to_bed_max_retries: 2`
  - `SplicingAnalysis.junction_analysis_preemptible: 1`, `junction_analysis_max_retries: 1`
  - Even with some attempt-2/3 shards, overall cost stayed low due to preemptible pricing.
- A later run with on‑demand VMs (`preemptible: 0` for all tasks) accrued >$3.5 before finishing all shards. On‑demand is ~3–4× more expensive per CPU-hour.

Recommended defaults for cost/stability balance:
- BamToBed (scatter of many short jobs):
  - `bam_to_bed_preemptible: 2–3`
  - `bam_to_bed_max_retries: 1–2`
- RunJunctions (single heavier aggregation):
  - `junction_analysis_preemptible: 0` (on‑demand for stability)
  - `junction_analysis_max_retries: 0–1`

Notes:
- Keep `useCallCache: true` to reuse identical shards across re-runs.
- Consider submitting via `terra_rawls_submit.sh` to enable `deleteIntermediateOutputFiles: true` and set a visible `userComment` in Terra.

## What is Rawls?

Rawls is Terra's workflow orchestration service exposed via REST APIs. Submissions created via Rawls allow you to:
- Attach a visible user comment in the Terra UI
- Toggle advanced flags (e.g., `deleteIntermediateOutputFiles`, `useCallCache`)
- Programmatically upsert method configs and submit in one shot

We provide `workflows/splicing_analysis/terra_runs/terra_rawls_submit.sh` as a thin wrapper. Our default submit path in `dockstore_run.sh` now uses Rawls for Methods submissions so comments and toggles are always set.

## Partial success and selective re‑runs

- The workflow now tolerates BamToBed shard errors to let other shards complete and cache their BEDs. It optionally stops before `RunJunctions` when some shards produced no BEDs (`stop_on_missing_beds: true` by default).
- Rerun strategy:
  1) Inspect failing shards via monitoring summaries or stderr paths
  2) Rebuild a small input JSON containing only failing BAM/BAI pairs
  3) Submit again; call cache will reuse all successful shards; only missing BEDs are recomputed
  4) Provide previously produced BEDs via `SplicingAnalysis.extra_bed_files` to skip recomputation when running `bed_only: true`

Automation helper:
```bash
# Build a partial rerun JSON with only failed BAMs and with successful BEDs preloaded
python workflows/splicing_analysis/terra_runs/prepare_partial_rerun.py \
  --submission-id <SUBMISSION_ID> \
  --input-json workflows/splicing_analysis/inputs/gtex_v10_validated/<tissue_N>.json \
  --out workflows/splicing_analysis/inputs/gtex_v10_validated/<tissue_N>_partial.json

# Then resubmit the partial JSON (Rawls path sets a visible comment)
workflows/splicing_analysis/terra_runs/dockstore_run.sh \
  -m AltAnalyze3_SNAF/splicing_analysis/<VERSION> \
  -i workflows/splicing_analysis/inputs/gtex_v10_validated/<tissue_N>_partial.json
```

Mixed inputs:
- `bed_only: true` intentionally expects no BAMs. For mixed runs (some BEDs already produced, some BAMs to recompute), keep `bed_only: false`, put successful BEDs into `extra_bed_files`, and keep only the failed BAM/BAI in the arrays. The helper above does this automatically.

Bucket/run naming & comments:
- Runs are annotated automatically, e.g., `GTEx v10 | cervix_uteri | 55 samples | AltAnalyze3_SNAF/splicing_analysis/3` in Terra's comment.
- Bucket folder: `gtex_v10/<tissue>/<N>_samples/<run_id>`