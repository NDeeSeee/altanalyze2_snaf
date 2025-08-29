# Execution Scenarios: GTEx, TCGA, and Custom HPC Data

This guide provides a compact, decision-focused comparison of platforms and runners for your main data scenarios: GTEx v10 on AnVIL/GCP, TCGA from GDC, and custom datasets on your institutional HPC.
It covers WDL/Cromwell, Nextflow DSL2, CWL (via external platforms), and the major execution backends (Terra, Google Batch, AWS Batch, SevenBridges CGC).

## TL;DR recommendations
- GTEx v10 (AnVIL/GCP): Terra + WDL (primary). Alternatives that stay on GCP: Cromwell-on-GCP, Nextflow on Google Batch. Avoid egress to AWS/SBG.
- TCGA (GDC): If data stays in cloud, upload to GCS and use Terra/Cromwell/Nextflow on GCP; if you rely on CGC, SevenBridges is fine. For on-prem analysis, run on HPC with Nextflow or Cromwell.
- Custom HPC data: Run on-prem (Nextflow Slurm or Cromwell on Slurm). Push selected jobs to GCP when you need scale or proximity to cloud datasets.

## Scenario comparison matrix

| Scenario | Data locality | Recommended runner | Why | Egress risk | Op complexity |
|---|---|---|---|---|---|
| GTEx v10 on AnVIL | GCS (GCP) | Terra (WDL/Cromwell) | Native to AnVIL, Methods snapshots, zero egress, call cache | None | Low (you have wrappers)
|  |  | Cromwell on GCP (Google Batch) | Same WDLs, more control, zero egress | None | Medium (operate Cromwell)
|  |  | Nextflow on Google Batch | Portability + Tower observability, zero egress | None | Medium (DSL port + ops)
|  |  | SevenBridges (CGC) | Only if data already on CGC or mandated | High (to AWS) | Medium (licensing, migration)
| TCGA (GDC) | Download (anywhere) | Terra/Cromwell/Nextflow on GCP | Standardize to GCS buckets; leverage GCP scale | Low (after upload) | Low–Medium
|  |  | SevenBridges (CGC) | Strong fit if team already on CGC | None (if CGC) | Low–Medium
|  |  | HPC (Slurm) | On-prem cost, control | None | Medium (queue mgmt)
| Custom HPC | On-prem (POSIX) | Nextflow (Slurm) | Excellent HPC ergonomics, portable DSL | None | Medium (profiles)
|  |  | Cromwell (Slurm) | Keep WDLs; stable engine | None | Medium (server or client)
|  |  | GCP (Batch) | Burst compute, shared data with GTEx | Upload req. | Medium

## Deep reasoning: cost, performance, and governance
- Data locality dominates cost. GTEx is on GCS; keep compute on GCP to avoid egress and latency.
- Compute cost converges across runners when using the same container and preemptible strategy. Differences come from localization (e.g., Nextflow Fusion) and cache reuse patterns, typically second-order for this workload.
- Reproducibility + provenance: Terra Methods snapshots are strong primitives; Nextflow + Tower or Git + containers can match it with discipline. Cromwell-on-GCP gives full control + raw metadata.
- Governance: Terra/AnVIL simplifies dbGaP/AnVIL access. SBG/CGC excels where the org is already standardized there.

## Run recipes (copy/paste)

### GTEx v10 on Terra (primary)
```bash
workflows/splicing_analysis/terra_runs/dockstore_run.sh \
  -m AltAnalyze3_SNAF/splicing_analysis/<VERSION> \
  -i workflows/splicing_analysis/inputs/gtex_v10_validated/<tissue_N>.json \
  -d "GTEx <tissue> <N> samples | v<VERSION>"
```
Notes: Uses Rawls by default to attach comments and toggles; keep call cache; prefer preemptibles for BamToBed; on‑demand for RunJunctions.

### GTEx on GCP without Terra (Cromwell on GCP)
- Deploy Cromwell (GCE/GKE) with Google backend (Life Sciences/Batch) and a GCS work bucket.
- Submit the same WDL and inputs using your CI or `alto cromwell run`.
```bash
alto cromwell run \
  -s cromwell.your.org \
  -m workflows/splicing_analysis/splicing_analysis.wdl \
  -i workflows/splicing_analysis/inputs/gtex_v10_validated/<tissue_N>.json
```

### GTEx via Nextflow on Google Batch (portable second stack)
```bash
# Convert WDL inputs → Nextflow pairs.csv (optional if you curate CSVs directly)
python workflows/nextflow/make_pairs_csv.py \
  --wdl-json workflows/splicing_analysis/inputs/gtex_v10_validated/<tissue_N>_partial.json \
  --output pairs.csv

# Edit google_batch profile in nextflow.config (project/workDir/location), then run:
nextflow run workflows/nextflow/splicing_analysis.nf \
  --pairs_csv gs://YOUR_BUCKET/pairs.csv \
  --outdir gs://YOUR_BUCKET/nextflow-runs/$(date +%Y%m%d-%H%M%S) \
  -profile google_batch \
  -with-report -with-timeline
```

### AWS alternatives (when data is in S3)
#### Nextflow on AWS Batch
```bash
nextflow run workflows/nextflow/splicing_analysis.nf \
  --pairs_csv s3://YOUR_BUCKET/pairs.csv \
  --outdir s3://YOUR_BUCKET/nextflow-runs/$(date +%Y%m%d-%H%M%S) \
  -profile aws_batch \
  -with-report -with-timeline
```

#### Cromwell on AWS Batch (keep WDL)
- Deploy Cromwell with the AWS backend; configure S3 work bucket and IAM roles; submit the same WDL + inputs.

### CWL/SevenBridges (CGC)
- SevenBridges/CGC is CWL-first with growing WDL support; DNAnexus is a similar alternative.
- Best fit: TCGA and projects already in CGC; orgs that need strong governance/billing controls via GUI.
- For GTEx on GCS/AnVIL, avoid due to egress unless mandated.

### TCGA (GDC) on GCP
- Upload TCGA BAM/BAI to a GCS bucket (or mount via Access VMs if permitted).
- Use the same Terra/Cromwell/Nextflow commands as GTEx (replace inputs with TCGA URIs).

### TCGA on SevenBridges (CGC)
- If your team is already on CGC, use SBG tools to run WDL/CWL.
- Port inputs to SBG-compatible descriptors; reuse the same containers.
- Avoid moving GTEx here due to GCS→AWS egress.

### Custom datasets on HPC (on-prem)
- Prefer Nextflow with a `slurm` profile or Cromwell on Slurm to keep containers and logic.
- When you need cloud scale, selectively export subsets to GCS and run on Google Batch.

## Decision framework (quick checklist)
- Data lives where? GCS (AnVIL), CGC, S3, or on-prem only.
- Who needs to collaborate? Terra workspaces, SBG projects, or internal HPC groups.
- Ops maturity: Do you want a managed UI (Terra/SBG) or own the engine (Cromwell/Nextflow + Tower)?
- Cost: Preemptibles, call caching, disk types; egress avoidance.
- Roadmap: Do you plan to broaden beyond these two workflows → Nextflow may compound benefits.

## Current stance for this project
- Primary: Terra + WDL for GTEx (data-local, mature automation).
- Secondary: Nextflow on Google Batch as strategic portability (experimental pipeline included).
- Tertiary: Cromwell-on-GCP for teams who prefer API-first and owning the scheduler.
- SevenBridges: Only when data and collaborators require CGC.
