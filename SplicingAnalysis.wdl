version 1.0

task AltAnalyzeSplicing {
    input {
        File bam_file
        File bai_file
        Int cpu_cores = 4
    }

    command {
        set -e
        # AltAnalyze.sh expects the BAMs to live in /mnt/bam inside the
        # container, so create that directory and stage the inputs there.
        mkdir -p /mnt/bam

        # Copy BAM and BAI files to the expected location
        cp ${bam_file} /mnt/bam/
        cp ${bai_file} /mnt/bam/

        # Run AltAnalyze. The second argument is the *name* of the folder
        # relative to /mnt, so keep it as "bam" (do NOT pass a full path).
        /usr/src/app/AltAnalyze.sh identify bam ${cpu_cores}

        # AltAnalyze writes its results to /mnt/altanalyze_output. Copy this
        # directory into the task working directory so that Cromwell/Terra can
        # local-ise it as an output.
        cp -R /mnt/altanalyze_output ./altanalyze_output
    }

    output {
        Directory results = "altanalyze_output"
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
        File bam_file
        File bai_file
        Int cpu_cores = 4
    }

    call AltAnalyzeSplicing {
        input:
            bam_file = bam_file,
            bai_file = bai_file,
            cpu_cores = cpu_cores
    }

    output {
        File splicing_results = AltAnalyzeSplicing.results
    }
}
