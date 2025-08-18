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
        String docker_image = "ndeeseee/altanalyze:v1.6.7"
    }

    Int bam_gib = ceil(size(bam_file, "GiB"))
    Int bam_disk_candidate = bam_gib * 3 + 30
    Int disk_space = if bam_disk_candidate > 50 then bam_disk_candidate else 50

    command <<<
        set -euo pipefail
        mkdir -p /mnt/bam
        bn=$(basename "~{bam_file}")
        ln -s "~{bam_file}" "/mnt/bam/${bn}"
        ln -s "~{bai_file}"  "/mnt/bam/${bn}.bai"

        /usr/src/app/AltAnalyze.sh bam_to_bed "bam/${bn}"

        # Expose outputs in task dir with symlinks to avoid duplication
        shopt -s nullglob
        for f in /mnt/bam/*.bed; do
            ln -s "$f" ./
        done
    >>>

    output {
        # Two outputs per BAM: Sample.bed and Sample__junction.bed
        Array[File] bed_files = glob("*.bed")
    }

    runtime {
        docker: docker_image
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
        Boolean counts_only = false
        String docker_image = "ndeeseee/altanalyze:v1.6.7"
    }

    Int bed_gib = ceil(size(bed_files, "GiB"))
    Int bed_disk_candidate = bed_gib * 4 + 20
    Int disk_space = if bed_disk_candidate > 50 then bed_disk_candidate else 50

    command <<<
        set -euo pipefail
        mkdir -p /mnt/bam
        mkdir -p /mnt/altanalyze_output/ExpressionInput

        # Localize/link all BEDs with robust parsing preserving spaces
        mapfile -t BED_FILES < <(printf '%s\n' ~{sep='\n' bed_files})
        if [ ${#BED_FILES[@]} -eq 0 ]; then
            echo "No BED files found for junction analysis" >&2
            exit 1
        fi
        for bed in "${BED_FILES[@]}"; do
            ln -s "$bed" /mnt/bam/
        done

        # Run AltAnalyze junction step
        if [ "~{counts_only}" = "true" ]; then
            PERFORM_ALT=no SKIP_PRUNE=yes /usr/src/app/AltAnalyze.sh bed_to_junction "bam"
        else
            PERFORM_ALT=yes SKIP_PRUNE=no /usr/src/app/AltAnalyze.sh bed_to_junction "bam"
        fi

        # Ensure expected event file exists to keep downstream consumers happy
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
        docker: docker_image
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

    command {
        set -euo pipefail
        if [[ ~{bam_count} -eq 0 || ~{bai_count} -eq 0 ]]; then
            echo "No inputs: bam_files=~{bam_count}, bai_files=~{bai_count}" >&2
            exit 1
        fi

        if [[ ~{bam_count} -ne ~{bai_count} ]]; then
            echo "BAM/BAI length mismatch: ~{bam_count} vs ~{bai_count}" >&2
            exit 1
        fi
        echo OK
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

task PreflightPair {
    input {
        File bam_file
        File bai_file
    }

    command {
        set -euo pipefail
        # Force localization
        test -s "~{bam_file}"
        test -s "~{bai_file}"

        bn=$(basename "~{bam_file}")
        bai_bn=$(basename "~{bai_file}")
        expect_bai="${bn}.bai"
        if [[ "$expect_bai" != "$bai_bn" ]]; then
            echo "Pair mismatch: expected BAI '$expect_bai' for BAM '$bn', got '$bai_bn'" >&2
            exit 1
        fi
        echo "OK ${bn}"
    }

    output {
        String status = read_string(stdout())
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
        String docker_image = "ndeeseee/altanalyze:latest"
        Boolean preflight_enabled = false

        # Task-specific resource configuration
        Int bam_to_bed_cpu_cores = 1
        String bam_to_bed_memory = "8 GB"
        String bam_to_bed_disk_type = "HDD"
        Int bam_to_bed_preemptible = 3
        Int bam_to_bed_max_retries = 2

        Int junction_analysis_cpu_cores = 1
        String junction_analysis_memory = "8 GB"
        String junction_analysis_disk_type = "HDD"
        Int junction_analysis_preemptible = 1
        Int junction_analysis_max_retries = 1
    }

    # Input validation: ensure BAM and BAI arrays have matching lengths
    Int bam_count = length(bam_files)
    Int bai_count = length(bai_files)
    call ValidateInputs { input: bam_count = bam_count, bai_count = bai_count }

    # Optional preflight: quick per-pair checks (existence, pairing)
    if (preflight_enabled) {
        scatter (i in range(bam_count)) {
            call PreflightPair as Preflight { input: bam_file = bam_files[i], bai_file = bai_files[i] }
        }
    }

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
                max_retries = bam_to_bed_max_retries,
                docker_image = docker_image
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
            max_retries = junction_analysis_max_retries,
            docker_image = docker_image
    }

    output {
        File splicing_results = RunJunctions.results_archive
    }
}