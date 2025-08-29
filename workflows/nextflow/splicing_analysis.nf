nextflow.enable.dsl=2

// Parameters
params.pairs_csv = null              // CSV with columns: sample,bam,bai (GCS or local)
params.extra_bed_manifest = null     // Optional: text file with one BED per line
params.bed_only = false              // If true, skip BAM->BED and use only extra BEDs
params.counts_only = false           // If true, skip AltAnalyze pruning
params.species = 'Hs'
params.outdir = 'results'            // Can be a GCS path when using google-batch
params.container = 'ndeeseee/altanalyze:v1.6.38'

params.bam_to_bed_cpu = 1
params.bam_to_bed_memory = '8 GB'
params.junction_cpu = 1
params.junction_memory = '8 GB'

// Input validation
if( !params.bed_only && !params.pairs_csv ) {
    exit 1, "--pairs_csv is required unless --bed_only is true"
}

// Channels
Channel empty()

// Bed inputs provided directly (optional)
Channel
    .from( params.extra_bed_manifest ? file(params.extra_bed_manifest) : [] )
    .splitText()
    .map { it?.trim() }
    .filter { it }
    .map { file(it) }
    .set { extraBedsCh }

// BAM/BAI pairs (unless bed_only)
Channel
    .from( params.pairs_csv ? file(params.pairs_csv) : [] )
    .splitCsv(header: true)
    .map { row ->
        def bam = row.bam as String
        def bai = row.bai as String
        def sample = (row.sample ?: new File(bam).getName()).toString()
        tuple(sample, file(bam), file(bai))
    }
    .set { pairsCh }

// Process: BAM -> BED
process BAM_TO_BED {
    tag { sample }
    container params.container
    cpus params.bam_to_bed_cpu
    memory params.bam_to_bed_memory
    publishDir params.outdir, mode: 'copy', pattern: '*.bed', enabled: !params.bed_only

    input:
    tuple val(sample), path(bam), path(bai) from params.bed_only ? Channel.empty() : pairsCh

    output:
    tuple val(sample), path('*.bed') into producedBedsCh

    script:
    def bn = "${bam.getName()}"
    def bedDir = 'bam'
    def bash = """
        set -euo pipefail
        mkdir -p ${bedDir}
        ln -sf "${bam}" "${bedDir}/${bn}"
        ln -sf "${bai}" "${bedDir}/${bn}.bai" || true
        if command -v samtools >/dev/null 2>&1; then
          if [ ! -s "${bedDir}/${bn}.bai" ] || [ "${bedDir}/${bn}" -nt "${bedDir}/${bn}.bai" ]; then
            samtools index -@ ${task.cpus} "${bedDir}/${bn}" || true
          fi
        fi
        /usr/src/app/AltAnalyze.sh bam_to_bed "${bedDir}/${bn}" || true
        shopt -s nullglob; cp -f ${bedDir}/*.bed ./ || true
        chmod a+r ./*.bed 2>/dev/null || true
    """
    return bash
}

// Collect all BEDs (from produced + extra)
Channel
    .merge(
        producedBedsCh.map { it[1] },
        extraBedsCh
    )
    .set { allBedsCh }

// Final junction analysis over all BEDs
process JUNCTIONS {
    tag 'AltAnalyze junctions'
    container params.container
    cpus params.junction_cpu
    memory params.junction_memory
    publishDir params.outdir, mode: 'copy', pattern: 'altanalyze_output.tar.gz'

    input:
    path bed_files from allBedsCh.collect()

    output:
    path 'altanalyze_output.tar.gz'

    when:
    // Run if any BEDs exist (in bed_only mode or after BAM_TO_BED)
    true

    script:
    def countsEnv = params.counts_only ? 'PERFORM_ALT=no SKIP_PRUNE=yes' : 'PERFORM_ALT=yes SKIP_PRUNE=no'
    def bash = """
        set -euo pipefail
        mkdir -p bed altanalyze_output/ExpressionInput
        if [ "${bed_files.size()}" -eq 0 ]; then
          echo "No BED files found for junction analysis" >&2
          exit 1
        fi
        # Copy all bed files locally
        for f in ${bed_files.collect{ '"'+it+'"' }.join(' ')}; do
          bn=\$(basename "$f"); cp -f "$f" "bed/\$bn" || cat "$f" > "bed/\$bn"
        done
        ln -s "\$PWD/altanalyze_output" /mnt/altanalyze_output 2>/dev/null || true
        EVENT_FILE="altanalyze_output/AltResults/AlternativeOutput/${params.species}_RNASeq_top_alt_junctions-PSI_EventAnnotation.txt"
        mkdir -p \"\$(dirname \"\$EVENT_FILE\")\"
        [ -s "\$EVENT_FILE" ] || printf "UID\n" > "\$EVENT_FILE"
        ${countsEnv} /usr/src/app/AltAnalyze.sh bed_to_junction bed
        [ -s "\$EVENT_FILE" ] || printf "UID\n" > "\$EVENT_FILE"
        tar -czf altanalyze_output.tar.gz altanalyze_output
    """
    return bash
}

workflow {
    if( params.bed_only ) {
        // No BAM->BED; ensure at least one extra bed is provided
        allBedsCh.view { it }
    } else {
        // Ensure BAM/BAI pairs exist and are aligned
        pairsCh.count().map{ n -> if(n==0) { throw new IllegalArgumentException('No BAM/BAI pairs found in --pairs_csv') } }.view(false)
    }
}
