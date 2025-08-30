# Nextflow usage (experimental, GCP‑friendly)

This repository includes an experimental Nextflow variant of the splicing analysis that mirrors the WDL workflow.
It is intended as a second stack to keep data on GCP (Google Batch) while maintaining portability.

## Files
- `workflows/nextflow/splicing_analysis.nf` — Pipeline (BAM→BED shards; single junction aggregation)
- `workflows/nextflow/nextflow.config` — Profiles: `local`, `google_batch`
- `workflows/nextflow/make_pairs_csv.py` — Helper to generate `pairs.csv` from WDL input JSONs

## Requirements
- Nextflow 23.10+
- Docker (local) or GCP permissions (google-batch)
- GCP auth for Google Batch profile:
  ```bash
  gcloud auth application-default login
  ```

## Inputs
- `pairs.csv` with headers `sample,bam,bai` (URIs can be local paths or `gs://`)
- Optional: BED manifest with one path per line for bed-only or mixed runs

## Local run (Docker)
```bash
nextflow run workflows/nextflow/splicing_analysis.nf \
  --pairs_csv /path/to/pairs.csv \
  --outdir results/local-test \
  -profile local
```

## Bed-only mode
```bash
nextflow run workflows/nextflow/splicing_analysis.nf \
  --bed_only true \
  --extra_bed_manifest /path/to/bed_manifest.txt \
  --species Hs \
  -profile local
```

## Run on Google Batch (recommended for GTEx locality)
1) Edit `workflows/nextflow/nextflow.config` under the `google_batch` profile:
   - `google.project = 'YOUR_GCP_PROJECT'`
   - `workDir = 'gs://YOUR_WORKSPACE_BUCKET/nextflow-work'`
   - `location = 'us-central1'` (or your region)
2) Run:
```bash
nextflow run workflows/nextflow/splicing_analysis.nf \
  --pairs_csv gs://YOUR_BUCKET/pairs.csv \
  --outdir gs://YOUR_BUCKET/nextflow-runs/$(date +%Y%m%d-%H%M%S) \
  -profile google_batch \
  -with-report -with-timeline
```

## Run on AWS Batch (when data is in S3)
1) Edit `workflows/nextflow/nextflow.config` under the `aws_batch` profile:
   - `workDir = 's3://YOUR_S3_BUCKET/nextflow-work'`
   - `aws.region = 'us-east-1'` (or your region)
   - Configure Batch job role, queue, compute env as needed
2) Run:
```bash
nextflow run workflows/nextflow/splicing_analysis.nf \
  --pairs_csv s3://YOUR_BUCKET/pairs.csv \
  --outdir s3://YOUR_BUCKET/nextflow-runs/$(date +%Y%m%d-%H%M%S) \
  -profile aws_batch \
  -with-report -with-timeline
```

Note: For GTEx on GCS/AnVIL, prefer Google Batch to avoid egress.

## Generate pairs.csv from WDL JSON
Use the helper to convert a WDL inputs JSON into a CSV for Nextflow:
```bash
python workflows/nextflow/make_pairs_csv.py \
  --wdl-json workflows/splicing_analysis/inputs/gtex_v10_validated/cervix_uteri_55_partial.json \
  --output pairs.csv
```

## Generate pairs.csv from TCGA sheets
Given a GDC sample sheet (TSV) or `uuid_and_filename_cleaned.tsv`, build URIs under your bucket/prefix:
```bash
python workflows/nextflow/make_pairs_from_tcga_sheet.py \
  --sheet data/tcga/uvm/gdc_sample_sheet.2025-08-12.tsv \
  --prefix gs://YOUR_BUCKET/tcga/uvm \
  --output pairs.tcga.csv
```

## Notes
- Container image is the same as WDL (`ndeeseee/altanalyze:v1.6.38`).
- This pipeline is for parity and portability; Terra + WDL remains primary for GTEx.
