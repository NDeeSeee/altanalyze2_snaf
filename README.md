# AltAnalyze2 SNAF Workflows

This repository contains two WDL workflows and supporting container code:

- Splicing analysis with AltAnalyze: `workflows/splicing_analysis.wdl`
- STAR 2-pass alignment: `star_2.4_alignment/star_alignment.wdl`

### Dockstore configuration

The root `.dockstore.yml` registers both workflows for automatic discovery:

- `splicing_analysis` with `primaryDescriptorPath: /workflows/splicing_analysis.wdl`
- `star_2pass_alignment` with `primaryDescriptorPath: /star_2.4_alignment/star_alignment.wdl`

You can import this repo into Dockstore to run the workflows directly.

### Splicing analysis (AltAnalyze)

- WDL: `workflows/splicing_analysis.wdl`
- Container: `frankligy123/altanalyze:latest`
- Docker build: `docker/` (for custom builds)
- Example inputs: `inputs/splicing_analysis_test.json`

Required inputs:
- `SplicingAnalysis.bam_files`: array of BAMs
- `SplicingAnalysis.bai_files`: corresponding BAI indexes

Optional parameters:
- `SplicingAnalysis.cpu_cores`: CPU cores (default 1)
- `SplicingAnalysis.extra_bed_files`: additional BED files to include
- `SplicingAnalysis.species`: species code (default "Hs" for human)

Resource configuration (configurable via input JSON):
- `SplicingAnalysis.bam_to_bed_memory`: BAM->BED memory (default "16 GB")
- `SplicingAnalysis.bam_to_bed_disk_size`: BAM->BED disk space in GB (default 50)
- `SplicingAnalysis.bam_to_bed_disk_type`: "HDD" or "SSD" (default "HDD")
- `SplicingAnalysis.junction_analysis_memory`: Junction analysis memory (default "16 GB")  
- `SplicingAnalysis.junction_analysis_disk_size`: Junction analysis disk space in GB (default 50)
- `SplicingAnalysis.junction_analysis_disk_type`: "HDD" or "SSD" (default "HDD")

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

**Example**: See `inputs/splicing_analysis_configurable.json` for complete configuration options.

### STAR 2-pass alignment

- WDL: `star_2.4_alignment/star_alignment.wdl`
- Container: `ndeeseee/star-aligner:latest`
- Script: `star_2.4_alignment/star_alignment.sh`
- Example inputs: `star_2.4_alignment/star_alignment_test.json`

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