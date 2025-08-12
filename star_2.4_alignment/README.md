# STAR 2-Pass RNA-seq Alignment

This directory contains scripts and configurations for STAR 2-pass RNA-seq alignment, available in both HPC cluster (LSF) and containerized Docker implementations.

## Files Overview

### Core Scripts
- **`star_2.4.sh`** - Original LSF job scheduler version
- **`star_2.4_container.sh`** - Containerized version for Docker/cloud workflows

### Container Infrastructure  
- **`Dockerfile`** - Multi-stage Docker build for STAR 2.4.0h
- **`star_2pass_alignment.wdl`** - WDL task definition for workflow systems
- **`build_and_test.sh`** - Docker build and validation script

## Key Differences Between Scripts

| Feature | `star_2.4.sh` (LSF) | `star_2.4_container.sh` (Container) |
|---------|---------------------|-------------------------------------|
| **Execution** | Generates LSF job scripts | Direct command execution |
| **Environment** | HPC clusters with LSF | Docker containers/cloud |
| **Resource Management** | Fixed LSF directives | Dynamic CPU detection |
| **Path Handling** | Hard-coded cluster paths | Command-line arguments |
| **Error Handling** | Basic | Comprehensive with `set -euo pipefail` |

## Usage

### LSF Version (HPC Cluster)
```bash
# Single sample
bash star_2.4.sh sample.1.fastq.gz | bsub

# Batch processing
for i in *1.fastq.gz; do bash star_2.4.sh $i | bsub; done
```

### Container Version
```bash
# Build container
docker build -t star-aligner:2.4.0h .

# Run alignment
docker run --rm \
  -v /path/to/data:/data \
  star-aligner:2.4.0h \
  /data/input/sample.1.fastq.gz \
  /data/reference/star_index \
  /data/reference/genome.fa \
  /data/output
```

### WDL Workflow
Use `star_2pass_alignment.wdl` with Cromwell, Terra, or other WDL-compatible systems.

## Requirements

### LSF Version
- LSF job scheduler
- STAR 2.4.0h module
- Paired-end FASTQ files
- Pre-built STAR genome index

### Container Version  
- Docker
- Pre-built STAR genome index
- Paired-end FASTQ files

## Output
- **BAM file**: `{sample_name}.bam` - Coordinate-sorted aligned reads
- **Log file**: `{sample_name}_Log.final.out` - Alignment statistics (container version)

## STAR 2-Pass Strategy
1. **Pass 1**: Initial alignment to detect novel splice junctions
2. **Pass 2**: Re-alignment using discovered splice junctions for improved accuracy

This approach significantly improves alignment quality for RNA-seq data by incorporating sample-specific splice junction information.