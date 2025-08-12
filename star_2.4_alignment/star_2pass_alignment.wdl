version 1.2

##############################################################################
# STAR 2-Pass RNA-seq Alignment WDL Task
##############################################################################
# Description: WDL task for STAR 2-pass alignment using containerized workflow
# Author: Bioinformatics Team
# Version: 1.0
# STAR Version: 2.4.0h
##############################################################################

task StarTwoPassAlignment {
    meta {
        description: "Performs STAR 2-pass alignment for paired-end RNA-seq data"
        author: "Bioinformatics Team"
        email: "bioinformatics@example.com"
        version: "1.0"
    }
    
    parameter_meta {
        fastq_r1: {
            description: "R1 FASTQ file for paired-end RNA-seq data",
            patterns: ["*.fastq.gz", "*.fq.gz"],
            category: "required"
        }
        fastq_r2: {
            description: "R2 FASTQ file for paired-end RNA-seq data", 
            patterns: ["*.fastq.gz", "*.fq.gz"],
            category: "required"
        }
        star_genome_dir: {
            description: "STAR genome index directory",
            category: "required"
        }
        reference_genome: {
            description: "Reference genome FASTA file",
            patterns: ["*.fa", "*.fasta", "*.fa.gz"],
            category: "required"
        }
        sample_name: {
            description: "Sample identifier for output naming",
            category: "required"
        }
        cpu_cores: {
            description: "Number of CPU cores to use for alignment",
            category: "optional"
        }
        memory_gb: {
            description: "Memory allocation in GB",
            category: "optional"
        }
        disk_size_gb: {
            description: "Disk space allocation in GB",
            category: "optional"
        }
        max_intron_length: {
            description: "Maximum intron length for alignment",
            category: "optional"
        }
        max_mate_gap: {
            description: "Maximum gap between paired reads",
            category: "optional"
        }
        docker_image: {
            description: "Docker image for STAR alignment",
            category: "optional"
        }
    }

    input {
        # Required inputs
        File fastq_r1
        File fastq_r2  
        Directory star_genome_dir
        File reference_genome
        String sample_name

        # Optional parameters with sensible defaults
        Int cpu_cores = 8
        Int memory_gb = 64
        Int disk_size_gb = 500
        Int max_intron_length = 500000
        Int max_mate_gap = 1000000
        String docker_image = "star-aligner:2.4.0h"
        
        # Advanced STAR parameters
        Int outFilterMultimapNmax = 20
        Int outFilterMismatchNmax = 10
        Float outFilterMatchNminOverLread = 0.33
        Float outFilterScoreMinOverLread = 0.33
        Int sjdbOverhang = 100
    }

    # Calculate required disk space based on input file sizes
    Int final_disk_size = if disk_size_gb > 100 then disk_size_gb else 
                         max(100, ceil(3 * (size(fastq_r1, "GB") + size(fastq_r2, "GB"))))

    command <<<
        set -euo pipefail
        
        # Log system information
        echo "Starting STAR 2-pass alignment"
        echo "Sample: ~{sample_name}"
        echo "CPU cores: ~{cpu_cores}"
        echo "Memory: ~{memory_gb}GB"
        echo "Disk: ~{final_disk_size}GB"
        echo "Docker image: ~{docker_image}"
        
        # Create output directory
        mkdir -p /cromwell_root/output
        
        # Run STAR 2-pass alignment
        /usr/local/bin/star_align.sh \
            "~{fastq_r1}" \
            "~{star_genome_dir}" \
            "~{reference_genome}" \
            "/cromwell_root/output"
        
        # Verify output was created
        if [[ ! -f "/cromwell_root/output/~{sample_name}.bam" ]]; then
            echo "Error: Expected output BAM file not found"
            ls -la /cromwell_root/output/
            exit 1
        fi
        
        # Generate alignment statistics if available
        if [[ -f "*Log.final.out" ]]; then
            cp *Log.final.out /cromwell_root/output/~{sample_name}_Log.final.out
        fi
        
        echo "STAR alignment completed successfully"
    >>>

    output {
        File aligned_bam = "/cromwell_root/output/~{sample_name}.bam"
        File? alignment_log = "/cromwell_root/output/~{sample_name}_Log.final.out"
    }

    runtime {
        docker: docker_image
        cpu: cpu_cores
        memory: "~{memory_gb}GB"
        disks: "local-disk ~{final_disk_size} SSD"
        preemptible: 2
        maxRetries: 1
        bootDiskSizeGb: 20
    }
}

##############################################################################
# Example Workflow Using the STAR Task
##############################################################################

workflow StarAlignmentWorkflow {
    meta {
        description: "Complete workflow for STAR 2-pass RNA-seq alignment"
        version: "1.0"
    }
    
    input {
        File fastq_r1
        File fastq_r2
        Directory star_genome_dir  
        File reference_genome
        String sample_name
        
        # Optional runtime parameters
        Int? cpu_cores
        Int? memory_gb
        Int? disk_size_gb
    }

    call StarTwoPassAlignment {
        input:
            fastq_r1 = fastq_r1,
            fastq_r2 = fastq_r2,
            star_genome_dir = star_genome_dir,
            reference_genome = reference_genome,
            sample_name = sample_name,
            cpu_cores = select_first([cpu_cores, 8]),
            memory_gb = select_first([memory_gb, 64]),
            disk_size_gb = select_first([disk_size_gb, 500])
    }

    output {
        File aligned_bam = StarTwoPassAlignment.aligned_bam
        File? alignment_log = StarTwoPassAlignment.alignment_log
    }
}

##############################################################################
# Example input JSON:
# {
#   "StarAlignmentWorkflow.fastq_r1": "gs://bucket/sample.1.fastq.gz",
#   "StarAlignmentWorkflow.fastq_r2": "gs://bucket/sample.2.fastq.gz", 
#   "StarAlignmentWorkflow.star_genome_dir": "gs://bucket/star_index/",
#   "StarAlignmentWorkflow.reference_genome": "gs://bucket/genome.fa",
#   "StarAlignmentWorkflow.sample_name": "sample_001",
#   "StarAlignmentWorkflow.cpu_cores": 16,
#   "StarAlignmentWorkflow.memory_gb": 128
# }
##############################################################################