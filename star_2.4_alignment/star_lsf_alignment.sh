#!/bin/bash

##############################################################################
# STAR 2-Pass RNA-seq Alignment Script
##############################################################################
# Description: Performs STAR 2-pass alignment for paired-end RNA-seq data
#              First pass generates splice junction database, second pass
#              uses this data for improved alignment accuracy
#
# Usage: bash star_lsf_alignment.sh <input_R1.fastq.gz>
#        Input file must follow pattern: sample.1.fastq.gz (R1)
#        Corresponding R2 file: sample.2.fastq.gz (auto-detected)
#
# Requirements:
#   - STAR 2.4.0h module available
#   - LSF job scheduler (bsub)
#   - Paired-end FASTQ files (.1.fastq.gz and .2.fastq.gz)
#   - Reference genome and index files
#
# Output: Sorted BAM file in ./bams/ directory
##############################################################################

# Input validation
if [ $# -eq 0 ] || [ -z "$1" ]; then
    echo "Error: No input file specified"
    echo "Usage: $0 <input_R1.fastq.gz>"
    echo "Example: $0 sample.1.fastq.gz"
    exit 1
fi

# Get the input FASTQ file from the command-line argument
FASTQ1=$1

# Validate input file exists
if [ ! -f "$FASTQ1" ]; then
    echo "Error: Input file '$FASTQ1' not found"
    exit 1
fi
# Auto-detect corresponding R2 file and extract sample name
FASTQ2="${FASTQ1/.1/.2}"
SAMPLE=$(basename "${FASTQ1}" .1.fastq.gz)

# Validate R2 file exists
if [ ! -f "${FASTQ2}" ]; then
    echo "Error: Corresponding R2 file '${FASTQ2}' not found"
    echo "Expected paired files: ${FASTQ1} and ${FASTQ2}"
    exit 1
fi

# Set working directory and paths
DIR=$(pwd)

OUT_DIR="${DIR}/star_output"
LOG_DIR="/data/salomonis2/Michal/Kith_Pradhan_shares_bms/logs"
BAM_DIR="${DIR}/bams"
GENOME_DIR=/data/salomonis2/Genomes/Star2pass-GRCH38/GenomeRef
GENOME=/data/salomonis2/Genomes/Star2pass-GRCH38/GRCh38.d1.vd1.fa

# Create required directories
if ! mkdir -p "${OUT_DIR}" "${LOG_DIR}" "${BAM_DIR}"; then
    echo "Error: Failed to create required directories"
    exit 1
fi

# Validate reference genome files exist
if [ ! -d "${GENOME_DIR}" ]; then
    echo "Error: Reference genome directory '${GENOME_DIR}' not found"
    exit 1
fi

if [ ! -f "${GENOME}" ]; then
    echo "Error: Reference genome file '${GENOME}' not found"
    exit 1
fi

# Generate LSF job submission script with embedded STAR commands
cat <<EOF
#BSUB -L /bin/bash
#BSUB -W 20:00
#BSUB -n 2
#BSUB -M 128000
#BSUB -e $LOG_DIR/${SAMPLE}_star_redo_%J.err
#BSUB -o $LOG_DIR/${SAMPLE}_star_redo_%J.out
#BSUB -J $SAMPLE

cd $DIR
module load STAR/2.4.0h

# STAR 2-Pass Alignment Strategy:
# Pass 1: Initial alignment to detect novel splice junctions
# Pass 2: Re-alignment using splice junctions from pass 1 for improved accuracy

# 1st Pass: Generate the splice junctions database
STAR --genomeDir ${GENOME_DIR} \
     --readFilesIn $FASTQ1 $FASTQ2 \
     --runThreadN 8 \
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
     --outFileNamePrefix ${OUT_DIR}/${SAMPLE}_pass1_ \
     --outFilterMatchNminOverLread 0.33 \
     --outFilterScoreMinOverLread 0.33 \
     --sjdbOverhang 100 \
     --outSAMstrandField intronMotif \
     --outSAMtype None \
     --outSAMmode None

# 2nd Pass: Create sample-specific genome index with splice junctions from pass 1
mkdir -p ${OUT_DIR}/GenomeRef_${SAMPLE}
STAR --runMode genomeGenerate \
     --genomeDir ${OUT_DIR}/GenomeRef_${SAMPLE} \
     --genomeFastaFiles $GENOME \
     --sjdbOverhang 100 \
     --runThreadN 8 \
     --sjdbFileChrStartEnd ${OUT_DIR}/${SAMPLE}_pass1_SJ.out.tab \
     --outFileNamePrefix ${OUT_DIR}/${SAMPLE}_pass2_

# Final alignment using sample-specific genome index with known splice junctions
STAR --genomeDir ${OUT_DIR}/GenomeRef_${SAMPLE} \
     --readFilesIn $FASTQ1 $FASTQ2 \
     --runThreadN 8 \
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
     --outFileNamePrefix ${OUT_DIR}/${SAMPLE}_second_ \
     --outFilterMatchNminOverLread 0.33 \
     --outFilterScoreMinOverLread 0.33 \
     --sjdbOverhang 100 \
     --outSAMstrandField intronMotif \
     --outSAMattributes NH HI NM MD AS XS \
     --outSAMunmapped Within \
     --outSAMtype BAM SortedByCoordinate \
     --outSAMheaderHD @HD VN:1.4

# Cleanup: Move final BAM to output directory and remove temporary files
mv ${OUT_DIR}/${SAMPLE}_second_Aligned.sortedByCoord.out.bam ${BAM_DIR}/${SAMPLE}.bam
rm -r ${OUT_DIR}/GenomeRef_${SAMPLE}
rm ${OUT_DIR}/${SAMPLE}_pass1_SJ.out.tab
EOF


# Example batch processing command:
# for i in *1.fastq.gz; do bash star_lsf_alignment.sh $i | bsub; done