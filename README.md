# AltAnalyze2 SNAF Workflows

This repository contains two WDL workflows and supporting container code:

- Splicing analysis with AltAnalyze: `workflows/splicing_analysis/splicing_analysis.wdl`
- STAR 2-pass alignment: `workflows/star_alignment/star_alignment.wdl`
- Containers: see `containers/altanalyze` and `containers/star-aligner`

## 📚 Setup and Usage Documentation

**New to Terra/Altocumulus?** Start with our comprehensive setup guides:

- **[Complete Setup Guide](docs/SETUP.md)** - Everything needed to get started
- **[Authentication Setup](docs/AUTHENTICATION.md)** - Google Cloud and Terra authentication
- **[Altocumulus Guide](docs/ALTOCUMULUS_GUIDE.md)** - Complete Alto command reference  
- **[Terra/FireCloud Setup](docs/FIRECLOUD_SETUP.md)** - Cloud platform configuration

See **[docs/README.md](docs/README.md)** for the complete documentation index.

## 🧭 Project navigation (start here)

- Splicing Analysis workflow WDL: `workflows/splicing_analysis/splicing_analysis.wdl`
- Terra CLI runbook, monitoring, cost, reruns: `workflows/splicing_analysis/terra_runs/README.md`
  - Submit wrapper (uses Rawls by default): `workflows/splicing_analysis/terra_runs/dockstore_run.sh`
  - Rawls submit helper: `workflows/splicing_analysis/terra_runs/terra_rawls_submit.sh`
  - Defaults (single source of truth): `workflows/splicing_analysis/inputs/gtex_defaults.json`
  - Apply defaults to all inputs: `workflows/splicing_analysis/terra_runs/apply_defaults.py`
  - Batch/chunk runner: `workflows/splicing_analysis/terra_runs/run_gtex_chunked.sh`
  - Partial rerun helper: `workflows/splicing_analysis/terra_runs/prepare_partial_rerun.py`
  - Per-run artifacts: `workflows/splicing_analysis/terra_runs/runs/`
    - Each submission gets a directory with monitor/collect scripts and metadata
  - Methods snapshot mapping: `workflows/splicing_analysis/terra_runs/method_ref.json`

### Supported workflow languages and engines
- WDL (primary) executed via Cromwell (Terra or self-hosted)
- Nextflow DSL2 (experimental mirror; runs on local, Google Batch, AWS Batch)
- CWL (via external platforms like SevenBridges/DNAnexus if needed; not primary here)
-
- ### Platform strategy and alternatives (executive summary)
- **Primary (recommended for GTEx/AnVIL data)**: Terra on GCP with WDL/Cromwell
  - Data locality to AnVIL/GTEx buckets (no egress), validated automation (Methods + Rawls), call caching, GUI + CLI.
- **Secondary on GCP (if you want a non‑Terra option)**:
  - Cromwell on GCP (self‑hosted) using Google Life Sciences/Batch. Keep WDLs, zero egress, more control than Terra.
  - Nextflow on Google Batch. Port workflows to Nextflow DSL; excellent observability with Tower; stays on GCP.
- **AWS options (when datasets live in S3 or collaborators require AWS)**:
  - Cromwell on AWS Batch (keep WDLs). Minimal rewrite, but GTEx data would incur egress from GCS.
  - Nextflow on AWS Batch (full DSL rewrite). Strong scalability; same egress caveat for GTEx.
- **Seven Bridges/CGC**: Enterprise platform with great governance and CWL/WDL support. Best when data already on SBG (e.g., TCGA/CGC). For GTEx on GCP, migration and egress reduce appeal.

- Validated GTEx inputs: `workflows/splicing_analysis/inputs/gtex_v10_validated/`
  - Update en masse via `apply_defaults.py` (above)
  - Input keys are auto-normalized (no legacy metadata)

### Dockstore configuration

The root `.dockstore.yml` registers both workflows for automatic discovery:

- `splicing_analysis` with `primaryDescriptorPath: /workflows/splicing_analysis/splicing_analysis.wdl`
- `star_2pass_alignment` with `primaryDescriptorPath: /workflows/star_alignment/star_alignment.wdl`

You can import this repo into Dockstore to run the workflows directly.

CLI launch options (what to use when):

- Broad Methods Repository (recommended if you maintain the WDL here)
  - Use `alto terra run -m "Namespace/method/version"` (e.g., `AltAnalyze3_SNAF/splicing_analysis/1`)
  - Works best for CLI and automation: accepts your JSON directly per run

- Dockstore via TRS
  - Terra GUI understands TRS like `#workflow/github.com/ORG/REPO/PATH:TAG`
  - Alto requires the Dockstore ID `organization:collection:name[:version]` (not TRS). If you don’t have a Dockstore org/collection, use Methods or Terra config.

- Terra Workspace Configuration (GUI-linked to Dockstore)
  - Use `fissfc config_start` or our `dockstore_run.sh -c <config_name>`
  - If a config has `rootEntityType`, you must pass a data entity row; otherwise remove root entity and provide inputs directly.
  - CLI here is equivalent to the GUI launch: it uses whatever is saved in the config unless you first update the config’s inputs.

### Recommended launch strategy (what we use by default)

- Use the Methods path for CLI submissions as the primary route, via our wrapper.
  - Why: no Dockstore org/collection required; accepts your JSON inputs per run; reproducible Methods snapshots; Rawls comments/toggles.
  - Command (Rawls-backed):
    ```bash
    workflows/splicing_analysis/terra_runs/dockstore_run.sh \
      -m AltAnalyze3_SNAF/splicing_analysis/<VERSION> \
      -i workflows/splicing_analysis/inputs/gtex_v10_validated/<tissue_N>.json
    ```
- Keep a Terra workspace configuration linked to Dockstore for GUI users and public provenance.
  - Caveat: CLI submissions via the config (`fissfc config_start`) use the config’s saved inputs. They’re not better than the GUI unless you programmatically update the config first.
- Direct Dockstore TRS with Alto isn’t supported without a Dockstore `organization:collection:name` ID. Until that’s available, prefer Methods for CLI.

We codified this in `workflows/splicing_analysis/terra_runs/dockstore_run.sh`:
- Default behavior: submit via Methods with your provided JSON; only “clean” the JSON if it contains non-WDL keys.
- Optional: `-c <config_name>` to use a Terra workspace config (GUI-linked to Dockstore) when you want that flow.

### Nextflow pipeline (experimental, GCP‑friendly)

- Pipeline: `workflows/nextflow/splicing_analysis.nf`
- Config/profiles: `workflows/nextflow/nextflow.config` (`local`, `google_batch`)
- Inputs: a CSV of BAM/BAI pairs (or bed‑only mode), optional BED manifest.

CSV format (BAM/BAI pairs):
```csv
sample,bam,bai
GTEX-XXXX-0001,gs://path/to/sample.bam,gs://path/to/sample.bam.bai
```

Local test (Docker required):
```bash
nextflow run workflows/nextflow/splicing_analysis.nf \
  --pairs_csv /path/to/pairs.csv \
  --outdir results/local-test \
  -profile local
```

Bed‑only mode:
```bash
nextflow run workflows/nextflow/splicing_analysis.nf \
  --bed_only true \
  --extra_bed_manifest /path/to/bed_manifest.txt \
  --species Hs \
  -profile local
```

Run on Google Batch (keep data in GCS; edit `nextflow.config` first):
```bash
# Set google.project, workDir, and location in nextflow.config (profile: google_batch)
nextflow run workflows/nextflow/splicing_analysis.nf \
  --pairs_csv gs://YOUR_BUCKET/pairs.csv \
  --outdir gs://YOUR_BUCKET/nextflow-runs/$(date +%Y%m%d-%H%M%S) \
  -profile google_batch \
  -with-report -with-timeline
```

Notes:
- Requires Nextflow 23.10+ (for `google-batch` executor) and GCP authentication.
- Container is the same as Terra (`ndeeseee/altanalyze:v1.6.39`).
- This pipeline mirrors the WDL tasks: BAM→BED shards, then a single junction aggregation over all BEDs.

See also: `docs/NEXTFLOW.md` and scenario playbook `docs/EXECUTION_SCENARIOS.md`.

### Cromwell‑on‑GCP (self‑hosted) and Google Batch (what and why)

- **Cromwell on GCP (self‑hosted)**
  - You deploy Cromwell (on GCE/GKE) configured for Google Life Sciences/Batch, point it at a GCS work bucket, and run the same WDLs.
  - Pros: zero egress with GTEx, call caching control, no Terra workspace overhead, integrates with existing CI.
  - Cons: own the server, IAM/service‑account setup, log aggregation, and quotas yourself.
  - See `docs/FIRECLOUD_SETUP.md` (Custom Cromwell configuration) for a starting config.

- **Google Batch**
  - Managed job service on GCP. Used underneath Cromwell’s Google backend and by Nextflow’s `google-batch` executor.
  - Pros: elastic, preemptibles, spots, fine‑grained job control, stays in GCS; easy to pair with Nextflow Tower.
  - Cons: fewer “workspace” conveniences than Terra; you build your own provenance and reporting.

### Is Nextflow better than current setup?

- For GTEx on GCP today: **No—Terra + WDL is already production‑ready and data‑local.** Rewriting to Nextflow adds engineering/time risk without clear cost/perf gains for these specific tasks.
- When Nextflow shines:
  - You need true multi‑cloud/HPC portability and a single runtime (Slurm, Google Batch, AWS Batch) with the same DSL.
  - You want Tower’s observability/operability stack (queues, sharing, fine metrics) across many pipelines.
  - You plan a broader method suite beyond WDL, or collaborators standardize on Nextflow/nf‑core.
- Balanced view: keep Terra/WDL as the primary for GTEx; build the Nextflow variant (above) as a strategic second stack on Google Batch to de‑risk long‑term portability.

### Seven Bridges (CGC) in context

- Strengths: enterprise governance, polished GUI, CWL/WDL support, great for TCGA/CGC‑resident data.
- Caveats for GTEx: GTEx lives on AnVIL/GCP; moving to SBG (AWS) implies egress costs/time and added governance setup. Choose SBG when the data and collaborators are already there.


### Splicing analysis (AltAnalyze)

- WDL: `workflows/splicing_analysis/splicing_analysis.wdl`
- Container: `ndeeseee/altanalyze:latest`
- Docker build: `containers/altanalyze/` (fast overrides)
  

Required inputs:
- `SplicingAnalysis.bam_files`: array of BAMs (unless running bed-only)
- `SplicingAnalysis.bai_files`: corresponding BAI indexes

Optional inputs (see defaults file for current values):
- `SplicingAnalysis.extra_bed_files`: additional BEDs to include
- `SplicingAnalysis.species`: species code (default "Hs")
- `SplicingAnalysis.docker_image`: container image tag
- Task resources (BamToBed): `bam_to_bed_cpu_cores`, `bam_to_bed_memory`, `bam_to_bed_disk_type`, `bam_to_bed_preemptible`, `bam_to_bed_max_retries`, `bam_to_bed_disk_multiplier`, `bam_to_bed_disk_buffer_gb`, `bam_to_bed_min_disk_gb`
- Task resources (RunJunctions): `junction_analysis_cpu_cores`, `junction_analysis_memory`, `junction_analysis_disk_type`, `junction_analysis_preemptible`, `junction_analysis_max_retries`, `junction_disk_multiplier`, `junction_disk_buffer_gb`, `junction_min_disk_gb`
- Flow control: `bed_only` (expect only BEDs), `stop_on_missing_beds` (stop before RunJunctions if some beds missing)

Manage all defaults in one place:
- Edit `workflows/splicing_analysis/inputs/gtex_defaults.json`
- Apply to all validated GTEx inputs:
  ```bash
  PYTHONPATH=. python workflows/splicing_analysis/terra_runs/apply_defaults.py \
    --defaults workflows/splicing_analysis/inputs/gtex_defaults.json \
    --inputs-dir workflows/splicing_analysis/inputs/gtex_v10_validated
  ```

Output:
- `splicing_results`: `altanalyze_output.tar.gz` containing AltAnalyze results

#### Docker Container Usage

```bash
# BAM to BED conversion
docker run --rm -v /path/to/data:/mnt \
  frankligy123/altanalyze:latest \
  bam_to_bed bam/sample.bam

# Full pipeline with parallelization
docker run --rm -v /path/to/data:/mnt \
  frankligy123/altanalyze:latest \
  identify bam_folder 4

# Custom species (e.g., mouse)
docker run --rm -v /path/to/data:/mnt \
  -e SPECIES=Mm \
  frankligy123/altanalyze:latest \
  bam_to_bed bam/mouse_sample.bam
```

#### Building Custom Container

```bash
cd docker/
make build          # Build image
make test           # Test image  
make build-test     # Build and test
make push           # Push to registry
```

See `docker/README.md` for complete documentation.

#### Resource Optimization

**Disk Parameter Explanation:**
- **Purpose**: Temporary storage for task execution (input files, intermediate outputs)
- **HDD**: Cheaper, slower traditional disk storage
- **SSD**: Faster solid-state storage, more expensive but better for I/O intensive tasks
- **Size**: Storage space in GB - increase for larger datasets

**Resource Recommendations:**
```json
# Default (conservative) - works for most small to medium datasets
{
  "SplicingAnalysis.cpu_cores": 1,
  "SplicingAnalysis.bam_to_bed_memory": "16 GB",
  "SplicingAnalysis.bam_to_bed_disk_size": 50,
  "SplicingAnalysis.junction_analysis_memory": "16 GB",
  "SplicingAnalysis.junction_analysis_disk_size": 50
}

# Medium datasets (10-50 samples, faster processing)
{
  "SplicingAnalysis.cpu_cores": 4,
  "SplicingAnalysis.junction_analysis_memory": "32 GB",
  "SplicingAnalysis.junction_analysis_disk_size": 100
}

# Large datasets (> 50 samples, > 50GB BAMs)  
{
  "SplicingAnalysis.cpu_cores": 8,
  "SplicingAnalysis.bam_to_bed_memory": "32 GB",
  "SplicingAnalysis.bam_to_bed_disk_size": 200,
  "SplicingAnalysis.bam_to_bed_disk_type": "SSD",
  "SplicingAnalysis.junction_analysis_memory": "128 GB", 
  "SplicingAnalysis.junction_analysis_disk_size": 500,
  "SplicingAnalysis.junction_analysis_disk_type": "SSD"
}
```

See GTEx validated inputs under `workflows/splicing_analysis/inputs/gtex_v10_validated/`.

### STAR 2-pass alignment

- WDL: `workflows/star_alignment/star_alignment.wdl`
- Container: `ndeeseee/star-aligner:latest`
- Script: `containers/star-aligner/star_alignment.sh`
- Example inputs: `workflows/star_alignment/inputs/test.json`

CLI (container) usage:

```bash
docker run --rm \
  -v /path/to/data:/data \
  ndeeseee/star-aligner:latest \
  /data/input/sample.1.fastq.gz \
  /data/reference/star_index \
  /data/reference/genome.fa \
  /data/output \
  sample_001 \
  16
```

WDL ensures deterministic output naming by passing `sample_name` to the script and threads via `cpu_cores`.

Output:
- `{sample}.bam` and optional `{sample}_Log.final.out`

### Development

- Shell scripts are linted with ShellCheck via GitHub Actions.
- To run locally: `shellcheck **/*.sh`