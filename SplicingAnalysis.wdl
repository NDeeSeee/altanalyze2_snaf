version 1.0

task AltAnalyzeSplicing {
    input {
        File bam_file
        File bai_file
        Int cpu_cores = 4
    }

    command {
        set -e
        # Create bam directory as expected by AltAnalyze.sh
        mkdir -p bam
        
        # Copy BAM and BAI files to bam directory
        cp ${bam_file} bam/
        cp ${bai_file} bam/
        
        # Run AltAnalyze.sh with correct parameters
        # Mode: identify, BAM folder: bam, Cores: cpu_cores
        /usr/src/app/AltAnalyze.sh identify bam ${cpu_cores}
    }

    output {
        File results = "altanalyze_output"
    }

    runtime {
        docker: "frankligy123/altanalyze:0.7.0.1"
        cpu: ${cpu_cores}
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
