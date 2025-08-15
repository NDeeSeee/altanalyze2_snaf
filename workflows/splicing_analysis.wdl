version 1.0

task BamToBed {
    input {
        File bam_file
        File bai_file
        Int cpu_cores = 1
        String memory = "8 GB"
        String disk_type = "HDD"
        Int preemptible = 3
        Int max_retries = 2
    }

    Int bam_gib = ceil(size(bam_file, "GiB"))
    Int disk_space = if (bam_gib*2 + 10) > 10 then (bam_gib*2 + 10) else 10

    command <<<
        set -euo pipefail
        mkdir -p /mnt/bam
        bn=$(basename "~{bam_file}")
        ln -s "~{bam_file}" "/mnt/bam/${bn}"
        ln -s "~{bai_file}"  "/mnt/bam/${bn}.bai"

        /usr/src/app/AltAnalyze.sh bam_to_bed "bam/${bn}"

        # Move outputs to task dir
        shopt -s nullglob
        for f in /mnt/bam/*.bed; do
            cp "$f" ./
        done
    >>>

    output {
        # Two outputs per BAM: Sample.bed and Sample__junction.bed
        Array[File] bed_files = glob("*.bed")
    }

    runtime {
        docker: "frankligy123/altanalyze:0.7.0.1"
        cpu: cpu_cores
        memory: memory
        disks: "local-disk ~{disk_space} ~{disk_type}"
        preemptible: preemptible
        maxRetries: max_retries
    }
}

task BedToJunction {
    input {
        Array[File] bed_files
        Int cpu_cores = 1
        String species = "Hs"
        String memory = "8 GB"
        String disk_type = "HDD"
        Int preemptible = 1
        Int max_retries = 1
    }

    Int bed_gib = ceil(size(bed_files, "GiB"))
    Int disk_space = if (bed_gib*2 + 10) > 10 then (bed_gib*2 + 10) else 10

    command <<<
        set -euo pipefail
        mkdir -p /mnt/bam
        mkdir -p /mnt/altanalyze_output/ExpressionInput

        # Use AltAnalyze defaults for perform_alt_analysis in options.txt

        # Localize all BEDs using a robust array expansion
        declare -a BED_FILES=()
        read -r -a BED_FILES <<< "~{sep=' ' bed_files}"
        for bed in "${BED_FILES[@]}"; do
            ln -s "$bed" /mnt/bam/
        done

        # Build minimal groups/comparisons here? We let AltAnalyze.sh do this inside bed_to_junction
        /usr/src/app/AltAnalyze.sh bed_to_junction "bam"

        # Harden prune step as in monolithic task
        EVENT_FILE="/mnt/altanalyze_output/AltResults/AlternativeOutput/~{species}_RNASeq_top_alt_junctions-PSI_EventAnnotation.txt"
        if [ ! -s "$EVENT_FILE" ]; then
            mkdir -p "$(dirname "$EVENT_FILE")"
            printf "UID\n" > "$EVENT_FILE"
        fi

        # Collect outputs
        cp -R /mnt/altanalyze_output ./altanalyze_output
        tar -czf altanalyze_output.tar.gz altanalyze_output
    >>>

    output {
        File results_archive = "altanalyze_output.tar.gz"
    }

    runtime {
        docker: "frankligy123/altanalyze:0.7.0.1"
        cpu: cpu_cores
        memory: memory
        disks: "local-disk ~{disk_space} ~{disk_type}"
        preemptible: preemptible
        maxRetries: max_retries
    }
}

task ValidateInputs {
    input {
        Int bam_count
        Int bai_count
    }

    command <<<'
        set -euo pipefail
        if [ ~{bam_count} -ne ~{bai_count} ]; then
          echo "BAM/BAI length mismatch: ~{bam_count} vs ~{bai_count}" >&2
          exit 1
        fi
        echo OK
    >>>

    output {
        String ok = read_string(stdout())
    }

    runtime {
        docker: "ubuntu:22.04"
        cpu: 1
        memory: "1 GB"
        disks: "local-disk 5 HDD"
        preemptible: 0
        maxRetries: 0
    }
}

workflow SplicingAnalysis {
    input {
        Array[File] bam_files
        Array[File] bai_files
        Array[File] extra_bed_files = []
        String species = "Hs"

        # Task-specific resource configuration
        Int bam_to_bed_cpu_cores = 1
        String bam_to_bed_memory = "8 GB"
        String bam_to_bed_disk_space = "10"
        String bam_to_bed_disk_type = "HDD"
        Int bam_to_bed_preemptible = 3
        Int bam_to_bed_max_retries = 2

        Int junction_analysis_cpu_cores = 1
        String junction_analysis_memory = "8 GB"
        String junction_analysis_disk_space = "10"
        String junction_analysis_disk_type = "HDD"
        Int junction_analysis_preemptible = 1
        Int junction_analysis_max_retries = 1
    }

    # Input validation: ensure BAM and BAI arrays have matching lengths
    Int bam_count = length(bam_files)
    Int bai_count = length(bai_files)
    call ValidateInputs { input: bam_count = bam_count, bai_count = bai_count }

    # Scatter: convert each BAM to its two BED files in parallel
    scatter (i in range(bam_count)) {
        call BamToBed as BamToBedScatter {
            input:
                bam_file = bam_files[i],
                bai_file = bai_files[i],
                cpu_cores = bam_to_bed_cpu_cores,
                memory = bam_to_bed_memory,
                disk_type = bam_to_bed_disk_type,
                preemptible = bam_to_bed_preemptible,
                max_retries = bam_to_bed_max_retries
        }
    }

    # Gather: collect all generated BED files and append any extra provided BEDs
    Array[File] produced_beds = flatten(BamToBedScatter.bed_files)
    Array[File] all_beds = flatten([produced_beds, extra_bed_files])

    # Single final analysis over all BEDs
    call BedToJunction as RunJunctions {
        input:
            bed_files = all_beds,
            cpu_cores = junction_analysis_cpu_cores,
            species = species,
            memory = junction_analysis_memory,
            disk_type = junction_analysis_disk_type,
            preemptible = junction_analysis_preemptible,
            max_retries = junction_analysis_max_retries
    }

    output {
        File splicing_results = RunJunctions.results_archive
    }
}