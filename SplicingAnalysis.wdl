version 1.0

task AltAnalyzeSplicing {
    input {
        File bam_file
        File bai_file
    }

    command {
        set -e
        cp ${bam_file} ./
        cp ${bai_file} ./
        altanalyze identify bam \
            --input ${basename(bam_file)} \
            --out altanalyze_output
    }

    output {
        File results = "altanalyze_output"
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
    }

    call AltAnalyzeSplicing { input: bam_file = bam_file, bai_file = bai_file }

    output {
        File splicing_results = AltAnalyzeSplicing.results
    }
}
