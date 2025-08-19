version 1.0

task BamToBed {
    input {
        File bam_file
        File bai_file
        Int cpu_cores = 1
        String memory = "16 GB"
        String disk_type = "HDD"
        Int preemptible = 0
        Int max_retries = 2
        String docker_image = "ndeeseee/altanalyze:v1.6.26"
        Float disk_multiplier = 4.0
        Int disk_buffer_gb = 50
        Int min_disk_gb = 100
    }

    Int bam_gib = ceil(size(bam_file, "GiB"))
    Int disk_candidate = ceil(bam_gib * disk_multiplier + disk_buffer_gb)
    Int disk_space = if disk_candidate > min_disk_gb then disk_candidate else min_disk_gb

    command <<<
        set -euo pipefail
        mkdir -p /mnt/bam
        bn=$(basename "~{bam_file}")
        ln -s "~{bam_file}" "/mnt/bam/${bn}"
        ln -s "~{bai_file}"  "/mnt/bam/${bn}.bai" || true

        # If samtools is present, attempt quick index check and reindex if needed
        if command -v samtools >/dev/null 2>&1; then
            samtools quickcheck -v "/mnt/bam/${bn}" >/dev/null 2>&1 || samtools index "/mnt/bam/${bn}" || true
        fi
        /usr/src/app/AltAnalyze.sh bam_to_bed "/mnt/bam/${bn}"

        # Expose outputs by copying to working dir so backend delocalizes them
        shopt -s nullglob
        for f in /mnt/bam/*.bed; do
            cp -f "$f" ./
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
        String docker_image = "ndeeseee/altanalyze:v1.6.26"
        Float disk_multiplier = 5.0
        Int disk_buffer_gb = 50
        Int min_disk_gb = 100
    }

    Int bed_gib = ceil(size(bed_files, "GiB"))
    Int bed_disk_candidate = ceil(bed_gib * disk_multiplier + disk_buffer_gb)
    Int disk_space = if bed_disk_candidate > min_disk_gb then bed_disk_candidate else min_disk_gb

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
            PERFORM_ALT=no SKIP_PRUNE=yes /usr/src/app/AltAnalyze.sh bed_to_junction "/mnt/bam"
        else
            PERFORM_ALT=yes SKIP_PRUNE=no /usr/src/app/AltAnalyze.sh bed_to_junction "/mnt/bam"
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

        bam_name=$(basename "~{bam_file}")
        bai_name=$(basename "~{bai_file}")
        bam_stem=$(printf '%s' "$bam_name" | sed 's/\\.bam$//')
        expected1="$bam_name.bai"      # e.g., sample.bam.bai
        expected2="$bam_stem.bai"      # e.g., sample.bai
        if [[ "$bai_name" != "$expected1" && "$bai_name" != "$expected2" ]]; then
            echo "Pair mismatch for BAM '$bam_name': expected BAI '$expected1' or '$expected2', got '$bai_name'" >&2
            exit 1
        fi
        echo "OK $bam_name"
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

task PreflightNames {
    input {
        String bam_name
        String bai_name
    }

    command <<<'
        set -euo pipefail
        ok_file=ok.txt
        sample_file=sample.txt

        bam_name="~{bam_name}"
        bai_name="~{bai_name}"
        bam_stem="${bam_name%.bam}"
        expected1="${bam_name}.bai"    # sample.bam.bai
        expected2="${bam_stem}.bai"    # sample.bai

        if [[ "$bai_name" == "$expected1" || "$bai_name" == "$expected2" ]]; then
            echo "true" > "${ok_file}"
        else
            echo "false" > "${ok_file}"
        fi
        echo "${bam_name}" > "${sample_file}"
    '>>>

    output {
        String ok = read_string("ok.txt")
        String sample = read_string("sample.txt")
    }

    runtime {
        docker: "ubuntu:22.04"
        cpu: 1
        memory: "0.5 GB"
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
        String docker_image = "ndeeseee/altanalyze:v1.6.26"
        Boolean preflight_enabled = true
        Boolean stop_on_preflight_failure = false

        # Task-specific resource configuration
        Int bam_to_bed_cpu_cores = 1
        String bam_to_bed_memory = "8 GB"
        String bam_to_bed_disk_type = "HDD"
        Int bam_to_bed_preemptible = 3
        Int bam_to_bed_max_retries = 2
        Float bam_to_bed_disk_multiplier = 4.0
        Int bam_to_bed_disk_buffer_gb = 50
        Int bam_to_bed_min_disk_gb = 100

        Int junction_analysis_cpu_cores = 1
        String junction_analysis_memory = "8 GB"
        String junction_analysis_disk_type = "HDD"
        Int junction_analysis_preemptible = 1
        Int junction_analysis_max_retries = 1
        Float junction_disk_multiplier = 5.0
        Int junction_disk_buffer_gb = 50
        Int junction_min_disk_gb = 100
    }

    # Input validation: ensure BAM and BAI arrays have matching lengths
    Int bam_count = length(bam_files)
    Int bai_count = length(bai_files)
    call ValidateInputs { input: bam_count = bam_count, bai_count = bai_count }

    # Soft preflight using name-only checks: never fail, filter invalid pairs
    scatter (i in range(bam_count)) {
        String bn = basename(bam_files[i])
        String bin = basename(bai_files[i])
        call PreflightNames as Preflight { input: bam_name = bn, bai_name = bin }

        Boolean pair_ok = (!preflight_enabled) || (Preflight.ok == "true")
        Array[File] maybe_bam    = if (pair_ok) then [bam_files[i]] else []
        Array[File] maybe_bai    = if (pair_ok) then [bai_files[i]] else []
        Array[String] maybe_fail = if (pair_ok) then [] else [bn]
    }

    Array[File] valid_bam_files = flatten(maybe_bam)
    Array[File] valid_bai_files = flatten(maybe_bai)
    Array[String] failed_samples = flatten(maybe_fail)
    Int valid_count = length(valid_bam_files)

    # Optionally fail fast if any invalid pairs were detected
    if (stop_on_preflight_failure && preflight_enabled && length(failed_samples) > 0) {
        call ValidateInputs as FailOnPreflight {
            input:
                bam_count = valid_count,
                bai_count = -1
        }
    }

    # Ensure there is at least one valid pair to process when preflight is enabled
    if (preflight_enabled && valid_count == 0) {
        call ValidateInputs as NoValidPairs {
            input:
                bam_count = 0,
                bai_count = 0
        }
    }

    # Scatter: convert each BAM to its two BED files in parallel
    scatter (i in range(valid_count)) {
        call BamToBed as BamToBedScatter {
            input:
                bam_file = valid_bam_files[i],
                bai_file = valid_bai_files[i],
                cpu_cores = bam_to_bed_cpu_cores,
                memory = bam_to_bed_memory,
                disk_type = bam_to_bed_disk_type,
                preemptible = bam_to_bed_preemptible,
                max_retries = bam_to_bed_max_retries,
                docker_image = docker_image,
                disk_multiplier = bam_to_bed_disk_multiplier,
                disk_buffer_gb = bam_to_bed_disk_buffer_gb,
                min_disk_gb = bam_to_bed_min_disk_gb
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
            docker_image = docker_image,
            disk_multiplier = junction_disk_multiplier,
            disk_buffer_gb = junction_disk_buffer_gb,
            min_disk_gb = junction_min_disk_gb
    }

    output {
        File splicing_results = RunJunctions.results_archive
    }
}