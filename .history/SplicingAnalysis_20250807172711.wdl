version 1.0

task AltAnalyzeSplicing {
    input {
        Array[File] bam_files
        Array[File] bai_files
        Int cpu_cores = 4
        Boolean? perform_alt_analysis
    }

    command <<<!
        set -e
        # AltAnalyze.sh expects BAMs in /mnt/bam. Stage everything there.
        mkdir -p /mnt/bam

        # Copy all BAMs and their BAI indexes into /mnt/bam
        for bam in ~{sep=' ' bam_files}; do
            cp "$bam" /mnt/bam/
        done
        for bai in ~{sep=' ' bai_files}; do
            cp "$bai" /mnt/bam/
        done

        # Run AltAnalyze (folder name is "bam").
        /usr/src/app/AltAnalyze.sh identify bam ~{cpu_cores} ~{if defined(perform_alt_analysis) && !perform_alt_analysis then "--perform_alt_analysis no" else ""}

        # Ensure prune.py won't fail when there are no splicing events (e.g., single group/sample)
        EVENT_FILE="/mnt/altanalyze_output/AltResults/AlternativeOutput/Hs_RNASeq_top_alt_junctions-PSI_EventAnnotation.txt"
        if [ ! -s "$EVENT_FILE" ]; then
            mkdir -p "$(dirname "$EVENT_FILE")"
            printf "UID\n" > "$EVENT_FILE"
        fi

        # Move results out so Cromwell can access them.
        cp -R /mnt/altanalyze_output ./altanalyze_output


        # Tarball for WDL 1.0 compatibility
        tar -czf altanalyze_output.tar.gz altanalyze_output
    >>>

    output {
        File results_archive = "altanalyze_output.tar.gz"
    }

    runtime {
        docker: "frankligy123/altanalyze:0.7.0.1"
        cpu: 4
        memory: "16 GB"
        disks: "local-disk 50 HDD"
    }
}

workflow SplicingAnalysis {
    input {
        Array[File] bam_files
        Array[File] bai_files
        Int cpu_cores = 4
        Boolean? perform_alt_analysis
    }

    # Default behavior: if not provided, run alt analysis only when there are >= 2 samples
    Boolean run_alt = select_first([perform_alt_analysis, length(bam_files) > 1])

    call AltAnalyzeSplicing {
        input:
            bam_files = bam_files,
            bai_files = bai_files,
            cpu_cores = cpu_cores,
            perform_alt_analysis = run_alt
    }

    output {
        File splicing_results = AltAnalyzeSplicing.results_archive
    }
}
