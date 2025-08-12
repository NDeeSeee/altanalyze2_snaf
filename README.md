# AltAnalyze2 SNAF Workflows

This repository contains two WDL workflows and supporting container code:

- Splicing analysis with AltAnalyze: `splicing_analysis.wdl`
- STAR 2-pass alignment: `star_2.4_alignment/star_alignment.wdl`

### Dockstore configuration

The root `.dockstore.yml` registers both workflows for automatic discovery:

- `splicing_analysis` with `primaryDescriptorPath: /splicing_analysis.wdl`
- `star_2pass_alignment` with `primaryDescriptorPath: /star_2.4_alignment/star_alignment.wdl`

You can import this repo into Dockstore to run the workflows directly.

### Splicing analysis (AltAnalyze)

- WDL: `splicing_analysis.wdl`
- Example inputs: `splicing_analysis_test.json`

Required inputs:
- `SplicingAnalysis.bam_files`: array of BAMs
- `SplicingAnalysis.bai_files`: corresponding BAI indexes

Optional:
- `SplicingAnalysis.cpu_cores` (default 4)
- `SplicingAnalysis.perform_alt_analysis` (Boolean, defaults based on sample count)

Output:
- `splicing_results`: `altanalyze_output.tar.gz` containing AltAnalyze results

### STAR 2-pass alignment

- WDL: `star_2.4_alignment/star_alignment.wdl`
- Container: `ndeeseee/star-aligner:latest`
- Script: `star_2.4_alignment/star_alignment.sh`
- Example inputs: `star_2.4_alignment/star_alignment_test.json`

Output:
- `{sample}.bam` and optional `{sample}_Log.final.out`

### Development

- Shell scripts are linted with ShellCheck via GitHub Actions.
- To run locally: `shellcheck **/*.sh`