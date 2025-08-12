version 1.0

##############################################################################
# STAR 2-Pass RNA-seq Alignment WDL Task
##############################################################################
# Description: WDL task for STAR 2-pass alignment using containerized workflow
# Author: Valerii Pavlov
# Email: valerii.pavlov@fccc.com
# Version: 1.0
# STAR Version: 2.4.0h
##############################################################################

task StarTwoPassAlignment {
    meta {
        description: "Performs STAR 2-pass alignment for paired-end RNA-seq data"
        author: "Valerii Pavlov"
        email: "valerii.pavlov@fccc.com"
        version: "1.0"
    }
    
    parameter_meta {
        fastq_r1: "R1 FASTQ file for paired-end RNA-seq data"
        fastq_r2: "R2 FASTQ file for paired-end RNA-seq data"
        star_genome_dir: "STAR genome index directory"
        reference_genome: "Reference genome FASTA file"
        sample_name: "Sample identifier for output naming"
        cpu_cores: "Number of CPU cores to use for alignment"
        memory_gb: "Memory allocation in GB"
        disk_size_gb: "Disk space allocation in GB"
        docker_image: "Docker image for STAR alignment"
    }

    input {
        # Required inputs
        File fastq_r1
        File fastq_r2  
        String star_genome_dir
        File reference_genome
        String sample_name

        # Optional parameters with sensible defaults
        Int cpu_cores = 8
        Int memory_gb = 64
        Int disk_size_gb = 500
        String docker_image = "ndeeseee/star-aligner:latest"
    }

    # Calculate required disk space based on input file sizes
    Float input_size_gb = size(fastq_r1, "GB") + size(fastq_r2, "GB")
    Int calculated_disk = ceil(3.0 * input_size_gb)
    Int final_disk_size = if disk_size_gb > 100 then disk_size_gb else 
                         if calculated_disk > 100 then calculated_disk else 100

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
        /usr/local/bin/star_alignment.sh \
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
        if ls ./*Log.final.out 1> /dev/null 2>&1; then
            cp ./*Log.final.out /cromwell_root/output/~{sample_name}_Log.final.out
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
        author: "Valerii Pavlov"
        email: "valerii.pavlov@fccc.com"
        version: "1.0"
    }
    
    input {
        File fastq_r1
        File fastq_r2
        String star_genome_dir
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