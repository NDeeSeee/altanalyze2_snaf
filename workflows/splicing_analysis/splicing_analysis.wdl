version 1.0

task BamToBed {
    input {
        File bam_file
        File bai_file
        Int cpu_cores = 1
        String memory = "8 GB"
        String disk_type = "HDD"
        Int preemptible = 2
        Int max_retries = 2
        String docker_image = "ndeeseee/altanalyze:v1.6.37"
        Float disk_multiplier = 1.3
        Int disk_buffer_gb = 20
        Int min_disk_gb = 50
    }

    Int bam_gib = ceil(size(bam_file, "GiB"))
    Int disk_candidate = ceil(bam_gib * disk_multiplier + disk_buffer_gb)
    Int disk_space = if disk_candidate > min_disk_gb then disk_candidate else min_disk_gb

    command <<<
        set -euo pipefail
        # Optional inline monitoring: start monitor.sh if present (no-op otherwise)
        MON_START() {
            if [[ "${ENABLE_MONITORING:-1}" != "0" ]]; then
                # Avoid starting a second monitor if one is already running (e.g., workspace-level monitoring)
                # Prefer a quick file-based guard first (workspace monitor usually writes this immediately)
                if [[ -s /cromwell_root/monitoring/metadata.json ]]; then return 0; fi
                if pgrep -f "monitor.sh" >/dev/null 2>&1; then return 0; fi
                if command -v monitor.sh >/dev/null 2>&1; then
                    MON_DIR="$PWD/monitoring" MON_MAX_SAMPLES=0 nohup monitor.sh >/dev/null 2>&1 & echo $! > .mon.pid || true
                elif [[ -x /usr/local/bin/monitor.sh ]]; then
                    MON_DIR="$PWD/monitoring" MON_MAX_SAMPLES=0 nohup /usr/local/bin/monitor.sh >/dev/null 2>&1 & echo $! > .mon.pid || true
                fi
            fi
        }
        MON_STOP() { if [[ -f .mon.pid ]]; then kill "$(cat .mon.pid)" >/dev/null 2>&1 || true; fi }
        trap MON_STOP EXIT
        MON_START
        mkdir -p bam
        bn=$(basename "~{bam_file}")
        bai_bn=$(basename "~{bai_file}")
        ln -s "~{bam_file}" "bam/${bn}"
        # Create BAI symlink with expected name regardless of actual BAI filename
        ln -s "~{bai_file}" "bam/${bn}.bai" || true

        # Ensure BAM index is present and up-to-date to avoid "index file is older than the data file"
        if command -v samtools >/dev/null 2>&1; then
            if [ -f "bam/${bn}.bai" ]; then
                # Detect stale index via warning from idxstats or mtime comparison
                samtools idxstats "bam/${bn}" >/dev/null 2>idx.err || true
                if grep -qi "index file" idx.err || ([ -f "bam/${bn}.bai" ] && [ "bam/${bn}" -nt "bam/${bn}.bai" ]); then
                    samtools index -@ ~{cpu_cores} "bam/${bn}" || true
                fi
                rm -f idx.err || true
            else
                samtools index -@ ~{cpu_cores} "bam/${bn}" || true
            fi
        fi
        /usr/src/app/AltAnalyze.sh bam_to_bed "bam/${bn}"

        # Expose outputs by copying to working dir so backend delocalizes them
        shopt -s nullglob
        for f in bam/*.bed; do
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
        String docker_image = "ndeeseee/altanalyze:v1.6.37"
        Float disk_multiplier = 2.0
        Int disk_buffer_gb = 10
        Int min_disk_gb = 50
    }

    Int bed_gib = ceil(size(bed_files, "GiB"))
    Int bed_disk_candidate = ceil(bed_gib * disk_multiplier + disk_buffer_gb)
    Int disk_space = if bed_disk_candidate > min_disk_gb then bed_disk_candidate else min_disk_gb

    command <<<
        set -euo pipefail
        # Optional inline monitoring: start monitor.sh if present (no-op otherwise)
        MON_START() {
            if [[ "${ENABLE_MONITORING:-1}" != "0" ]]; then
                # Avoid starting a second monitor if one is already running (e.g., workspace-level monitoring)
                # Prefer a quick file-based guard first (workspace monitor usually writes this immediately)
                if [[ -s /cromwell_root/monitoring/metadata.json ]]; then return 0; fi
                if pgrep -f "monitor.sh" >/dev/null 2>&1; then return 0; fi
                if command -v monitor.sh >/dev/null 2>&1; then
                    MON_DIR="$PWD/monitoring" MON_MAX_SAMPLES=0 nohup monitor.sh >/dev/null 2>&1 & echo $! > .mon.pid || true
                elif [[ -x /usr/local/bin/monitor.sh ]]; then
                    MON_DIR="$PWD/monitoring" MON_MAX_SAMPLES=0 nohup /usr/local/bin/monitor.sh >/dev/null 2>&1 & echo $! > .mon.pid || true
                fi
            fi
        }
        MON_STOP() { if [[ -f .mon.pid ]]; then kill "$(cat .mon.pid)" >/dev/null 2>&1 || true; fi }
        trap MON_STOP EXIT
        MON_START
        mkdir -p bed
        mkdir -p altanalyze_output/ExpressionInput

        # Localize/link all BEDs with robust parsing preserving spaces
        mapfile -t BED_FILES < <(printf '%s\n' ~{sep='\n' bed_files})
        if [ ${#BED_FILES[@]} -eq 0 ]; then
            echo "No BED files found for junction analysis" >&2
            exit 1
        fi
        for bed in "${BED_FILES[@]}"; do
            # Copy to ensure readable permissions and avoid symlink permission issues
            cp -f "$bed" bed/
        done

        # Run AltAnalyze junction step
        if [ "~{counts_only}" = "true" ]; then
            PERFORM_ALT=no SKIP_PRUNE=yes /usr/src/app/AltAnalyze.sh bed_to_junction "bed"
        else
            PERFORM_ALT=yes SKIP_PRUNE=no /usr/src/app/AltAnalyze.sh bed_to_junction "bed"
        fi

        # Ensure expected event file exists to keep downstream consumers happy
        EVENT_FILE="altanalyze_output/AltResults/AlternativeOutput/~{species}_RNASeq_top_alt_junctions-PSI_EventAnnotation.txt"
        if [ ! -s "$EVENT_FILE" ]; then
            mkdir -p "$(dirname "$EVENT_FILE")"
            printf "UID\n" > "$EVENT_FILE"
        fi

        # Collect outputs
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

## (No preflight tasks) — name checks are done purely in WDL expressions

workflow SplicingAnalysis {
    input {
        Array[File] bam_files = []
        Array[File] bai_files = []
        Array[File] extra_bed_files = []
        String species = "Hs"
        String docker_image = "ndeeseee/altanalyze:v1.6.37"
        Boolean preflight_enabled = true
        Boolean stop_on_preflight_failure = false
        Boolean bed_only = false

        # Task-specific resource configuration
        Int bam_to_bed_cpu_cores = 1
        String bam_to_bed_memory = "8 GB"
        String bam_to_bed_disk_type = "HDD"
        Int bam_to_bed_preemptible = 2
        Int bam_to_bed_max_retries = 2
        Float bam_to_bed_disk_multiplier = 3.0
        Int bam_to_bed_disk_buffer_gb = 30
        Int bam_to_bed_min_disk_gb = 75

        Int junction_analysis_cpu_cores = 1
        String junction_analysis_memory = "8 GB"
        String junction_analysis_disk_type = "HDD"
        Int junction_analysis_preemptible = 1
        Int junction_analysis_max_retries = 1
        Float junction_disk_multiplier = 1.3
        Int junction_disk_buffer_gb = 10
        Int junction_min_disk_gb = 30
    }

    # Input validation: ensure BAM and BAI arrays have matching lengths
    Int bam_count = length(bam_files)
    Int bai_count = length(bai_files)
    if (!bed_only) {
        call ValidateInputs { input: bam_count = bam_count, bai_count = bai_count }
    }

    # Soft preflight using pure-name checks (no task calls): never fail, filter invalid pairs
    scatter (i in range(bam_count)) {
        String bn = basename(bam_files[i])
        String bin = basename(bai_files[i])
        String stem = sub(bn, "\\.bam$", "")
        Boolean name_matches = (bin == bn + ".bai") || (bin == stem + ".bai")
        Boolean pair_ok = (!preflight_enabled) || name_matches
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
    # Skip this check in bed_only mode (we intentionally have no BAMs then)
    if (preflight_enabled && !bed_only && valid_count == 0) {
        call ValidateInputs as NoValidPairs {
            input:
                bam_count = 0,
                bai_count = 0
        }
    }

    # Always define scatter; use zero iterations when bed_only
    Int effective_count = if (bed_only) then 0 else valid_count
    scatter (i in range(effective_count)) {
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
    Array[Array[File]] bed_arrays = if (defined(BamToBedScatter.bed_files)) then BamToBedScatter.bed_files else []
    Array[File] produced_beds = flatten(bed_arrays)
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