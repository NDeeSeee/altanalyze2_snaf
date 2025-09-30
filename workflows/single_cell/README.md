# Single-Cell Workflow CLI for Terra

This directory contains CLI tools for running established single-cell RNA-seq workflows on Terra using the **Cumulus** pipeline.

## 🧬 What is Cumulus?

Cumulus is a well-established, production-ready single-cell RNA-seq processing pipeline available on Terra. It supports multiple platforms including:
- **10X Genomics** (Chromium, Xenium)
- **Smart-seq2**
- **Drop-seq**
- **CEL-seq2**
- **InDrops**

## 🚀 Quick Start

### Prerequisites
1. **Terra workspace** with appropriate permissions
2. **Altocumulus installed**: `pip install altocumulus`
3. **Google Cloud authentication** configured
4. **Single-cell FASTQ data** uploaded to GCS

### Basic Usage

```bash
# 1) Process individual samples with Cell Ranger (include_introns=true)
workflows/single_cell/terra_runs/cellranger_submit.sh \
  -i workflows/single_cell/inputs/cellranger_count_sample1.json \
  -m cumulus/cellranger_count/10 \
  -d "Cell Ranger count sample1 (introns)"

# 2) Process additional samples
workflows/single_cell/terra_runs/cellranger_submit.sh \
  -i workflows/single_cell/inputs/cellranger_count_sample2.json \
  -m cumulus/cellranger_count/10 \
  -d "Cell Ranger count sample2 (introns)"
```

## 📁 Directory Structure

```
workflows/single_cell/
├── README.md                    # This file
├── inputs/                      # Input JSON templates
│   ├── cellranger_template.json # Cell Ranger individual task template
│   ├── cellranger_count_sample*.json # Individual sample configurations
│   └── cellranger_samplesheet.csv # Sample sheet with FASTQ paths
├── terra_runs/                 # CLI scripts
│   ├── cellranger_submit.sh    # Cell Ranger submission runner
│   └── runs/                   # Per-run tracking (auto-created)
```

## 📋 Input Requirements

### Required Fields for All Platforms

```json
{
  "cumulus.fastq_r1_files": ["gs://bucket/sample_R1.fastq.gz"],
  "cumulus.fastq_r2_files": ["gs://bucket/sample_R2.fastq.gz"],
  "cumulus.sample_names": ["sample1"],
  "cumulus.reference_genome": "gs://bucket/references/hg38.fasta",
  "cumulus.reference_transcriptome": "gs://bucket/references/hg38.gtf",
  "cumulus.platform": "10X"
}
```

### Platform-Specific Fields

#### 10X Genomics
```json
{
  "cumulus.fastq_i1_files": ["gs://bucket/sample_I1.fastq.gz"],
  "cumulus.chemistry": "v3",
  "cumulus.expect_cells": 5000
}
```

#### Smart-seq2
```json
{
  "cumulus.platform": "Smart-seq2"
  // No I1 files needed
}
```

## 🔧 Configuration Options

### Cumulus Parameters

| Parameter | Description | Default | Notes |
|-----------|-------------|---------|-------|
| `cumulus.expect_cells` | Expected number of cells | 5000 | 10X only |
| `cumulus.min_genes_per_cell` | Minimum genes per cell | 200 | Quality filter |
| `cumulus.min_umis_per_cell` | Minimum UMIs per cell | 500 | Quality filter |
| `cumulus.max_genes_per_cell` | Maximum genes per cell | 5000 | Quality filter |
| `cumulus.min_cells_per_gene` | Minimum cells per gene | 3 | Gene filter |

### CLI Options

```bash
cumulus_run.sh [OPTIONS]

Options:
  -i INPUT_JSON       Path to Cumulus input JSON (required)
  -d DESCRIPTION      Run description (default: auto-generated)
  -v VERSION          Cumulus version (default: latest)
  -p PROJECT          Terra project (default from env)
  -w WORKSPACE        Terra workspace (default from env)
  -C MAX_COST_USD     Maximum cost threshold (default: 50.00)
  -h                  Show help
```

## 📊 Cost Estimation

Single-cell workflows are computationally intensive. Typical costs:

| Platform | Samples | Expected Cells | Est. Cost |
|----------|---------|----------------|-----------|
| 10X v3 | 1 | 5,000 | $15-25 |
| 10X v3 | 4 | 20,000 | $50-80 |
| Smart-seq2 | 1 | 1,000 | $10-15 |
| Smart-seq2 | 4 | 4,000 | $30-50 |

**Note**: Costs vary based on data quality, reference genome size, and Terra pricing.

## 🔍 Monitoring and Results

### Per-Run Tracking
Each submission creates a tracking directory:
```
workflows/single_cell/terra_runs/runs/YYYYMMDD-HHMMSS/
├── metadata.json           # Run metadata
├── input.json              # Input JSON used
├── submission_output.txt   # Submission logs
└── job_url.txt            # Terra job URL
```

### Monitoring Commands
```bash
# Check submission status
alto terra monitor -w "project/workspace"

# View job details
alto terra describe -w "project/workspace" -s SUBMISSION_ID
```

## 🛠️ Troubleshooting

### Common Issues

1. **Missing FASTQ files**
   ```
   Error: cumulus.fastq_r1_files not found
   Solution: Ensure all FASTQ files are uploaded to GCS and paths are correct
   ```

2. **Invalid reference genome**
   ```
   Error: Reference genome format not supported
   Solution: Use standard FASTA format with .fasta extension
   ```

3. **Authentication errors**
   ```
   Error: Authentication failed
   Solution: Run `gcloud auth login` and `alto auth login`
   ```

### Getting Help

- **Cumulus Documentation**: [Broad Institute Cumulus](https://cumulus.readthedocs.io/)
- **Terra Support**: [Terra Help Center](https://support.terra.bio/)
- **Altocumulus Issues**: [GitHub Issues](https://github.com/lilab-bcb/altocumulus/issues)

## 🔄 Integration with Existing Workflows

This single-cell workflow CLI integrates seamlessly with the existing AltAnalyze2 SNAF infrastructure:

- **Environment Configuration**: Uses same `workflows/terra/env.sh`
- **Authentication**: Leverages existing Terra authentication
- **Monitoring**: Compatible with existing monitoring tools
- **Cost Management**: Integrates with existing cost estimation

## 📚 Examples

### Example 1: 10X Genomics Analysis
```bash
# Prepare input JSON
cp workflows/single_cell/inputs/10x_template.json my_10x_input.json

# Edit paths in my_10x_input.json:
# - Update FASTQ file paths
# - Update reference genome paths
# - Adjust expected cell count

# Submit workflow
workflows/single_cell/terra_runs/cumulus_run.sh \
  -i my_10x_input.json \
  -d "10X single-cell analysis - PBMC dataset"
```

### Example 2: Smart-seq2 Analysis
```bash
# Prepare input JSON
cp workflows/single_cell/inputs/smartseq2_template.json my_smartseq2_input.json

# Edit paths and parameters
# Submit workflow
workflows/single_cell/terra_runs/cumulus_run.sh \
  -i my_smartseq2_input.json \
  -v 1.5.0 \
  -d "Smart-seq2 single-cell analysis"
```

## 🎯 Next Steps

After Cumulus processing, you can:
1. **Download results** from Terra workspace
2. **Run downstream analysis** (clustering, differential expression)
3. **Integrate with AltAnalyze** for splicing analysis
4. **Export to standard formats** (H5, MTX, CSV)

For downstream analysis integration, see the main [README.md](../../README.md).