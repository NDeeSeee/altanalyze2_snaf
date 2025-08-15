#!/bin/bash

##############################################################################
# STAR 2-Pass RNA-seq Alignment Script (Containerized Version)
##############################################################################
# Description: Performs STAR 2-pass alignment for paired-end RNA-seq data
#              Optimized for Docker container execution
#              First pass generates splice junction database, second pass 
#              uses this data for improved alignment accuracy
#
# Usage: star_alignment.sh <R1.fastq.gz> <genome_dir> <genome.fa> <output_dir> [sample_name] [threads]
#
# Arguments:
#   $1: R1 FASTQ file path (R2 auto-detected by replacing .1. with .2.)
#   $2: STAR genome index directory
#   $3: Reference genome FASTA file
#   $4: Output directory for final BAM file
#
# Requirements:
#   - STAR 2.4.0h available in PATH
#   - Paired-end FASTQ files (.1.fastq.gz and .2.fastq.gz)
#   - Pre-built STAR genome index
#
# Output: Sorted BAM file in specified output directory
##############################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 <R1.fastq.gz> <genome_dir> <genome.fa> <output_dir> [sample_name] [threads]

Arguments:
  R1.fastq.gz    Path to R1 FASTQ file (R2 auto-detected)
  genome_dir     STAR genome index directory
  genome.fa      Reference genome FASTA file
  output_dir     Output directory for BAM file
  sample_name    Optional; basename for output files. If omitted, derived from R1
  threads        Optional; number of threads to use (default: nproc)

Example:
  $0 /data/input/sample.1.fastq.gz \\
     /data/reference/star_index \\
     /data/reference/genome.fa \\
     /data/output

Note: R2 file must follow naming pattern: sample.2.fastq.gz
EOF
}

# Check if help is requested
if [[ $# -eq 0 ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    show_usage
    exit 0
fi

# Validate number of arguments
if [[ $# -lt 4 || $# -gt 6 ]]; then
    echo "Error: Incorrect number of arguments"
    show_usage
    exit 1
fi

# Parse command line arguments
FASTQ1="$1"
GENOME_DIR="$2"
GENOME="$3"
OUTPUT_DIR="$4"
USER_SAMPLE_NAME="${5:-}"
USER_THREADS="${6:-}"

# Validate input files and directories
if [[ ! -f "${FASTQ1}" ]]; then
    echo "Error: R1 FASTQ file '${FASTQ1}' not found"
    exit 1
fi

# Auto-detect R2 file (simple replacement strategy)
FASTQ2="${FASTQ1/.1./.2.}"
if [[ ! -f "${FASTQ2}" ]]; then
    echo "Error: Corresponding R2 file '${FASTQ2}' not found"
    echo "Expected paired files: ${FASTQ1} and ${FASTQ2}"
    exit 1
fi

# Validate genome directory and file
if [[ ! -d "${GENOME_DIR}" ]]; then
    echo "Error: STAR genome directory '${GENOME_DIR}' not found"
    exit 1
fi

if [[ ! -f "${GENOME}" ]]; then
    echo "Error: Reference genome file '${GENOME}' not found"
    exit 1
fi

# Extract sample name or use user-provided
SAMPLE=$(basename "${FASTQ1}" .1.fastq.gz)
if [[ -n "${USER_SAMPLE_NAME}" ]]; then
    SAMPLE="${USER_SAMPLE_NAME}"
fi

# Determine threads
if [[ -n "${USER_THREADS}" ]]; then
    THREADS="${USER_THREADS}"
else
    THREADS="$(nproc)"
fi

# Create working and output directories
WORK_DIR="/tmp/star_work_${SAMPLE}_$$"
mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"

# Cleanup function
cleanup() {
    echo "Cleaning up temporary files..."
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

echo "Starting STAR 2-pass alignment for sample: ${SAMPLE}"
echo "R1: ${FASTQ1}"
echo "R2: ${FASTQ2}"
echo "Working directory: ${WORK_DIR}"

##############################################################################
# STAR 2-Pass Alignment Strategy:
# Pass 1: Initial alignment to detect novel splice junctions
# Pass 2: Re-alignment using splice junctions from pass 1 for improved accuracy
##############################################################################

cd "${WORK_DIR}"

# Pass 1: Generate splice junctions database
echo "Pass 1: Detecting splice junctions..."
STAR \
    --genomeDir "${GENOME_DIR}" \
    --readFilesIn "${FASTQ1}" "${FASTQ2}" \
    --runThreadN "${THREADS}" \
    --outFilterMultimapScoreRange 1 \
    --outFilterMultimapNmax 20 \
    --outFilterMismatchNmax 10 \
    --alignIntronMax 500000 \
    --alignMatesGapMax 1000000 \
    --sjdbScore 2 \
    --alignSJDBoverhangMin 1 \
    --genomeLoad NoSharedMemory \
    --limitBAMsortRAM 100000000000 \
    --readFilesCommand gunzip -c \
    --outFileNamePrefix "${SAMPLE}_pass1_" \
    --outFilterMatchNminOverLread 0.33 \
    --outFilterScoreMinOverLread 0.33 \
    --sjdbOverhang 100 \
    --outSAMstrandField intronMotif \
    --outSAMtype None \
    --outSAMmode None

# Pass 2: Create sample-specific genome index with splice junctions
echo "Pass 2: Creating sample-specific genome index..."
SAMPLE_GENOME_DIR="${WORK_DIR}/GenomeRef_${SAMPLE}"
mkdir -p "${SAMPLE_GENOME_DIR}"

STAR \
    --runMode genomeGenerate \
    --genomeDir "${SAMPLE_GENOME_DIR}" \
    --genomeFastaFiles "${GENOME}" \
    --sjdbOverhang 100 \
    --runThreadN "${THREADS}" \
    --sjdbFileChrStartEnd "${SAMPLE}_pass1_SJ.out.tab" \
    --outFileNamePrefix "${SAMPLE}_pass2_" \
    --limitGenomeGenerateRAM 100000000000

# Pass 2: Final alignment using sample-specific genome index
echo "Pass 2: Final alignment with known splice junctions..."
STAR \
    --genomeDir "${SAMPLE_GENOME_DIR}" \
    --readFilesIn "${FASTQ1}" "${FASTQ2}" \
    --runThreadN "${THREADS}" \
    --outFilterMultimapScoreRange 1 \
    --outFilterMultimapNmax 20 \
    --outFilterMismatchNmax 10 \
    --alignIntronMax 500000 \
    --alignMatesGapMax 1000000 \
    --sjdbScore 2 \
    --alignSJDBoverhangMin 1 \
    --genomeLoad NoSharedMemory \
    --limitBAMsortRAM 100000000000 \
    --readFilesCommand gunzip -c \
    --outFileNamePrefix "${SAMPLE}_final_" \
    --outFilterMatchNminOverLread 0.33 \
    --outFilterScoreMinOverLread 0.33 \
    --sjdbOverhang 100 \
    --outSAMstrandField intronMotif \
    --outSAMattributes NH HI NM MD AS XS \
    --outSAMunmapped Within \
    --outSAMtype BAM SortedByCoordinate \
    --outSAMheaderHD @HD VN:1.4

# Move final BAM to output directory
echo "Moving final BAM file to output directory..."
if [[ -f "${SAMPLE}_final_Aligned.sortedByCoord.out.bam" ]]; then
    mv "${SAMPLE}_final_Aligned.sortedByCoord.out.bam" "${OUTPUT_DIR}/${SAMPLE}.bam"
    echo "Success: BAM file created at ${OUTPUT_DIR}/${SAMPLE}.bam"
else
    echo "Error: Final BAM file not found"
    exit 1
fi

echo "STAR 2-pass alignment completed successfully for sample: ${SAMPLE}"