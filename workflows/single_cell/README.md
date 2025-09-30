# Single-Cell Cell Ranger Preprocessing CLI for Terra

This directory contains CLI tools for running **Cell Ranger count** preprocessing on Terra using the Cumulus `cellranger_count` task. This produces counts matrices from FASTQ files for downstream single-cell analysis.

## 🧬 What is Cell Ranger Count?

Cell Ranger count is a preprocessing step that:
- **Input**: Pre-demultiplexed FASTQ files (10X Genomics format)
- **Process**: Aligns reads, identifies cells, quantifies gene expression
- **Output**: Counts matrices (gene-barcode matrices) ready for downstream analysis
- **Platform**: 10X Genomics single-cell RNA-seq data

## 🚀 Quick Start

### Prerequisites
1. **Terra workspace** with appropriate permissions
2. **Google Cloud authentication** configured (`gcloud auth login`)
3. **Pre-demultiplexed FASTQ files** uploaded to GCS (10X Genomics format)
4. **Access to Cumulus methods** on Terra

### Basic Usage

```bash
# Process individual samples with Cell Ranger count (include_introns=true)
workflows/single_cell/terra_runs/cellranger_submit.sh \
  -i workflows/single_cell/inputs/cellranger_count_sample1.json \
  -m cumulus/cellranger_count/10 \
  -d "Cell Ranger count sample1 (introns)"

# Process additional samples
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

### Required Fields for Cell Ranger Count

```json
{
  "cellranger_count.sample_id": "SAMPLE_NAME",
  "cellranger_count.input_fastqs_directories": "gs://bucket/path/to/fastqs",
  "cellranger_count.output_directory": "gs://bucket/output/path",
  "cellranger_count.genome": "GRCh38-2024-A",
  "cellranger_count.chemistry": "auto",
  "cellranger_count.include_introns": true,
  "cellranger_count.cellranger_version": "6.0.1"
}
```

### Optional Fields

```json
{
  "cellranger_count.num_cpu": 8,
  "cellranger_count.memory": "32G",
  "cellranger_count.disk_space": 200,
  "cellranger_count.preemptible": 2,
  "cellranger_count.zones": "us-central1-a us-central1-b us-central1-c us-central1-f"
}
```

## 🔧 Configuration Options

### Cell Ranger Count Parameters

| Parameter | Description | Default | Notes |
|-----------|-------------|---------|-------|
| `cellranger_count.sample_id` | Sample identifier | Required | Unique sample name |
| `cellranger_count.genome` | Reference genome | GRCh38-2024-A | Human reference |
| `cellranger_count.chemistry` | Chemistry type | auto | Auto-detect or specify (SC3Pv3, etc.) |
| `cellranger_count.include_introns` | Include intronic reads | true | Recommended for better quantification |
| `cellranger_count.cellranger_version` | Cell Ranger version | 6.0.1 | Latest supported version |

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