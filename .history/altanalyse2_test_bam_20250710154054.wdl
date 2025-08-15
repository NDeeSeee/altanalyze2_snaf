version 1.0

task AltAnalyzeSplicing {
  input {
    File bam_file
  }

  command <<<
    set -e
    # Copy BAM into working directory
    cp "${bam_file}" ./
    # Run AltAnalyze on the BAM
    altanalyze identify bam \
      --input $(basename "${bam_file}") \
      --out altanalyze_output
  >>>

  output {
    Directory results = "altanalyze_output"
  }

  runtime {
    # Pulls the public AltAnalyze image from DockerHub
    docker: "frankligy123/altanalyze:0.7.0.1"
    cpu: 4
    memory: "16 GB"
    disks: "local-disk 50 HDD"
  }
}

workflow SplicingAnalysis {
  input {
    File bam_file
  }

  call AltAnalyzeSplicing {
    input: bam_file = bam_file
  }

  output {
    Directory splicing_results = AltAnalyzeSplicing.results
  }
}