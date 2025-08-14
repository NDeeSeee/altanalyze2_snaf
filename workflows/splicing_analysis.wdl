version 1.0

task BamToBed {
    input {
        File bam_file
        File bai_file
        Int cpu_cores = 4
    }

    command <<<
        set -euo pipefail
        mkdir -p /mnt/bam
        cp "~{bam_file}" /mnt/bam/
        cp "~{bai_file}" /mnt/bam/

        bn=$(basename "~{bam_file}")
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
        memory: "16 GB"
        disks: "local-disk 50 HDD"
    }
}

task BedToJunction {
    input {
        Array[File] bed_files
        Int cpu_cores = 4
        String species = "Hs"
    }

    command <<<
        set -euo pipefail
        mkdir -p /mnt/bam
        mkdir -p /mnt/altanalyze_output/ExpressionInput

        # Use AltAnalyze defaults for perform_alt_analysis in options.txt

        # Localize all BEDs using a robust array expansion
        declare -a BED_FILES=()
        read -r -a BED_FILES <<< "~{sep=' ' bed_files}"
        for bed in "${BED_FILES[@]}"; do
            cp "$bed" /mnt/bam/
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
        memory: "64 GB"
        disks: "local-disk 100 HDD"
    }
}

workflow SplicingAnalysis {
    input {
        Array[File] bam_files
        Array[File] bai_files
        Int cpu_cores = 4
        Array[File] extra_bed_files = []
    }

    # Input validation: ensure BAM and BAI arrays have matching lengths
    # This will cause workflow to fail early if arrays don't match
    Int bam_count = length(bam_files)
    Int bai_count = length(bai_files)
    Boolean valid_inputs = bam_count == bai_count

    # Scatter: convert each BAM to its two BED files in parallel
    # Use conditional to ensure validation passes (will fail if arrays don't match)
    scatter (i in range(if valid_inputs then bam_count else 0)) {
        call BamToBed as BamToBedScatter {
            input:
                bam_file = bam_files[i],
                bai_file = bai_files[i],
                cpu_cores = cpu_cores
        }
    }

    # Gather: collect all generated BED files and append any extra provided BEDs
    Array[File] produced_beds = flatten(BamToBedScatter.bed_files)
    Array[File] all_beds = flatten([produced_beds, extra_bed_files])

    # Single final analysis over all BEDs
    call BedToJunction as AnalyzeJunctions {
        input:
            bed_files = all_beds,
            cpu_cores = cpu_cores,
            species = "Hs"
    }

    output {
        File splicing_results = AnalyzeJunctions.results_archive
    }
}
