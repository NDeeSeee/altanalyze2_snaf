version 1.0

task AltAnalyzeSplicing {
    input {
        Array[File] bam_files
        Array[File] bai_files
        Int cpu_cores = 4
        Boolean? perform_alt_analysis
    }

    command <<<
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

        # Prepare groups/comps explicitly to avoid invalid comparisons in single-sample runs
        mkdir -p /mnt/altanalyze_output/ExpressionInput
        GROUPS=/mnt/altanalyze_output/ExpressionInput/groups.original.txt
        COMPS=/mnt/altanalyze_output/ExpressionInput/comps.original.txt
        : > "$GROUPS"; : > "$COMPS"
        i=0
        for bam in ~{sep=' ' bam_files}; do
            i=$((i+1))
            bn=$(basename "$bam")
            printf "%s\t%d\tSample%d\n" "$bn" "$i" "$i" >> "$GROUPS"
        done
        # Add simple comparisons (group2..N vs group1) only if alt analysis requested and there are >=2 groups
        RUN_ALT=~{if select_first([perform_alt_analysis, true]) then "yes" else "no"}
        if [ "$RUN_ALT" = "yes" ]; then
            if [ $i -ge 2 ]; then
                j=2
                while [ $j -le $i ]; do
                    printf "%d\t1\n" "$j" >> "$COMPS"
                    j=$((j+1))
                done
            fi
        fi

        # Force AltAnalyze to respect perform_alt_analysis for this run
        if [ "$RUN_ALT" = "no" ]; then
            sed -i 's/^perform_alt_analysis:.*/perform_alt_analysis: no/' /usr/src/app/altanalyze/Config/options.txt || true
        fi

        # Run AltAnalyze (folder name is "bam").
        /usr/src/app/AltAnalyze.sh identify bam ~{cpu_cores}

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
