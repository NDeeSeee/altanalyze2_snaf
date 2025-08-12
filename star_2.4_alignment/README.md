# STAR 2-Pass RNA-seq Alignment

Containerized STAR 2-pass RNA-seq alignment for modern bioinformatics workflows. This implementation provides a portable, reproducible solution that works across local, cloud, and HPC environments.

## Files Overview

### Core Components
- **`star_alignment.sh`** - Main alignment script (containerized)
- **`Dockerfile`** - Multi-stage Docker build for STAR 2.4.0h
- **`star_alignment.wdl`** - WDL task definition for workflow systems
- **`docker_build.sh`** - Docker build and validation script

## Why Container-Only Approach?

**Modern & Portable:**
- Works everywhere Docker is available
- Compatible with HPC via Singularity/Shifter
- Cloud-native for Terra, Cromwell, Nextflow workflows

**Reproducible:**
- Consistent environment across all platforms
- Version-controlled dependencies
- No environment-specific configurations

**Simplified Maintenance:**
- Single script to maintain and update
- Standard containerization practices

## Usage

### 1. Build Container
```bash
# Automated build and test
./docker_build.sh

# Or manual build
docker build -t star-aligner:2.4.0h .
```

### 2. Run Alignment

#### Local Docker
```bash
docker run --rm \
  -v /path/to/data:/data \
  star-aligner:2.4.0h \
  /data/input/sample.1.fastq.gz \
  /data/reference/star_index \
  /data/reference/genome.fa \
  /data/output
```

#### HPC with Singularity
```bash
# Convert Docker to Singularity
singularity build star_aligner.sif docker://star-aligner:2.4.0h

# Run on HPC
singularity exec \
  --bind /scratch:/data \
  star_aligner.sif \
  star_align.sh \
  /data/input/sample.1.fastq.gz \
  /data/reference/star_index \
  /data/reference/genome.fa \
  /data/output
```

#### Cloud Workflows
Use `star_alignment.wdl` with:
- **Terra/FireCloud** - Upload WDL and run workflows
- **Cromwell** - Local or cloud execution 
- **Nextflow** - Adapt WDL to Nextflow DSL

### 3. Example WDL Input
```json
{
  "StarAlignmentWorkflow.fastq_r1": "gs://bucket/sample.1.fastq.gz",
  "StarAlignmentWorkflow.fastq_r2": "gs://bucket/sample.2.fastq.gz", 
  "StarAlignmentWorkflow.star_genome_dir": "gs://bucket/star_index/",
  "StarAlignmentWorkflow.reference_genome": "gs://bucket/genome.fa",
  "StarAlignmentWorkflow.sample_name": "sample_001",
  "StarAlignmentWorkflow.cpu_cores": 16,
  "StarAlignmentWorkflow.memory_gb": 128
}
```

## Requirements

### Input Files
- **R1/R2 FASTQ files** - Paired-end RNA-seq data (`.fastq.gz`)
- **STAR genome index** - Pre-built index directory
- **Reference genome** - FASTA file (`.fa` or `.fasta`)

### System Requirements
- **Docker** (local/cloud) or **Singularity** (HPC)
- **Memory**: 64GB+ recommended
- **CPU**: 8+ cores recommended  
- **Disk**: 3x input file size + index size

## Output
- **`{sample}.bam`** - Coordinate-sorted aligned reads
- **`{sample}_Log.final.out`** - Alignment statistics and metrics

## STAR 2-Pass Strategy
1. **Pass 1**: Initial alignment discovers novel splice junctions
2. **Pass 2**: Re-alignment using sample-specific splice junctions

This approach significantly improves alignment accuracy by incorporating discovered splice sites, particularly important for detecting novel isoforms and splice variants in RNA-seq data.

## Advanced Usage

### Batch Processing
```bash
# Process multiple samples
for sample in samples/*.1.fastq.gz; do
  docker run --rm \
    -v $(pwd):/data \
    star-aligner:2.4.0h \
    /data/${sample} \
    /data/reference/star_index \
    /data/reference/genome.fa \
    /data/output
done
```

### Resource Customization
The container automatically detects available CPU cores. For memory-intensive datasets, ensure adequate RAM allocation in your Docker/Singularity settings.