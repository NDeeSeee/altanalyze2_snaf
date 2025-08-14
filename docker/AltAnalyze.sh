#!/bin/bash

##############################################################################
# AltAnalyze Containerized Wrapper Script
##############################################################################
# Description: Enhanced version of AltAnalyze.sh with better error handling,
#              configurable parameters, and cross-platform support
# Usage: AltAnalyze.sh <mode> [arguments...]
##############################################################################

set -euo pipefail

# Configuration variables - can be overridden by environment
ALTANALYZE_ROOT="${ALTANALYZE_ROOT:-/usr/src/app/altanalyze}"
SPECIES="${SPECIES:-Hs}"
PLATFORM="${PLATFORM:-RNASeq}"
VERSION="${VERSION:-EnsMart91}"
WORKING_DIR="${WORKING_DIR:-/mnt}"
PYTHON_CMD="${PYTHON_CMD:-python3}"

# Logging functions
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

log_warn() {
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

# Function to check required dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check Python
    if ! command -v "${PYTHON_CMD}" &> /dev/null; then
        missing_deps+=("${PYTHON_CMD}")
    fi
    
    # Check GNU Parallel (for identify mode)
    if [[ "$1" == "identify" ]] && ! command -v parallel &> /dev/null; then
        missing_deps+=("parallel")
    fi
    
    # Check AltAnalyze installation
    if [[ ! -f "${ALTANALYZE_ROOT}/AltAnalyze.py" ]]; then
        missing_deps+=("AltAnalyze (${ALTANALYZE_ROOT}/AltAnalyze.py)")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

# Function to validate file existence
validate_file() {
    local file_path="$1"
    local description="$2"
    
    if [[ ! -f "${file_path}" ]]; then
        log_error "${description} not found: ${file_path}"
        return 1
    fi
    
    return 0
}

# Function to validate directory existence
validate_directory() {
    local dir_path="$1"
    local description="$2"
    
    if [[ ! -d "${dir_path}" ]]; then
        log_error "${description} not found: ${dir_path}"
        return 1
    fi
    
    return 0
}

# Function to show usage information
show_usage() {
    cat << EOF
Usage: $0 <mode> [arguments...]

Modes:
  bam_to_bed <bam_file>
    Convert BAM file to BED format
    
  bed_to_junction <bed_folder>
    Analyze junctions from BED files
    
  identify <bam_folder> <cores>
    Full pipeline: BAM -> BED -> junction analysis with parallelization
    
  DE <output_folder> <group_file>
    Differential expression analysis
    
  GO <gene_list_file>
    Gene ontology enrichment analysis
    
  DAS <output_folder> <group_file>
    Differential alternative splicing analysis

Environment Variables:
  SPECIES          Species code (default: Hs)
  PLATFORM         Analysis platform (default: RNASeq)
  VERSION          Ensembl version (default: EnsMart91)
  ALTANALYZE_ROOT  AltAnalyze installation path
  PYTHON_CMD       Python command (default: python3)

Examples:
  $0 bam_to_bed bam/sample.bam
  $0 bed_to_junction bed_folder
  $0 identify bam_folder 4
  SPECIES=Mm $0 bam_to_bed bam/mouse_sample.bam
EOF
}

# BAM to BED conversion function
run_bam_to_bed() {
    local bam_file="$1"
    
    log_info "Converting BAM to BED: ${bam_file}"
    
    # Validate input file
    validate_file "${bam_file}" "BAM file" || return 1
    
    # Junction BED conversion
    log_info "Creating junction BED file"
    "${PYTHON_CMD}" "${ALTANALYZE_ROOT}/import_scripts/BAMtoJunctionBED.py" \
        --i "${bam_file}" \
        --species "${SPECIES}" \
        --r "${ALTANALYZE_ROOT}/AltDatabase/${VERSION}/ensembl/${SPECIES}/${SPECIES}_Ensembl_exon.txt" || {
        log_error "Junction BED conversion failed"
        return 1
    }
    
    # Exon BED conversion
    log_info "Creating exon BED file"
    "${PYTHON_CMD}" "${ALTANALYZE_ROOT}/import_scripts/BAMtoExonBED.py" \
        --i "${bam_file}" \
        --r "${ALTANALYZE_ROOT}/AltDatabase/${VERSION}/ensembl/${SPECIES}/${SPECIES}.bed" \
        --s "${SPECIES}" || {
        log_error "Exon BED conversion failed"
        return 1
    }
    
    log_info "BAM to BED conversion completed successfully"
    return 0
}

# BED to junction analysis function
run_bed_to_junction() {
    local bed_folder="$1"
    local task="original"
    
    log_info "Running BED to junction analysis: ${bed_folder}"
    
    # Validate input directory
    validate_directory "${bed_folder}" "BED folder" || return 1
    
    # Create output directory structure
    mkdir -p altanalyze_output/ExpressionInput
    
    # Build group file
    log_info "Building group file"
    local group_file="altanalyze_output/ExpressionInput/groups.${task}.txt"
    > "${group_file}"  # Clear file
    
    cd "${bed_folder}"
    local count=0
    for file in *__junction.bed; do
        if [[ -f "${file}" ]]; then
            local stream
            stream=$(echo "${file}" | sed 's/__junction.bed/.bed/g')
            if (( count % 2 == 0 )); then
                stream+='\t1\texp'
            else
                stream+='\t2\tctl'
            fi
            echo -e "${stream}" >> "../${group_file}"
            ((count++))
        fi
    done
    cd ..
    
    if [[ ${count} -eq 0 ]]; then
        log_error "No junction BED files found in ${bed_folder}"
        return 1
    fi
    
    log_info "Found ${count} junction BED files"
    
    # Build comparison file
    log_info "Building comparison file"
    local comp_file="altanalyze_output/ExpressionInput/comps.${task}.txt"
    echo -e '1\t2' > "${comp_file}"
    
    # Run AltAnalyze
    log_info "Running AltAnalyze multipath-PSI analysis"
    "${PYTHON_CMD}" "${ALTANALYZE_ROOT}/AltAnalyze.py" \
        --species "${SPECIES}" \
        --platform "${PLATFORM}" \
        --version "${VERSION}" \
        --bedDir "${WORKING_DIR}/${bed_folder}" \
        --output "${WORKING_DIR}/altanalyze_output" \
        --groupdir "${WORKING_DIR}/${group_file}" \
        --compdir "${WORKING_DIR}/${comp_file}" \
        --expname "${task}" \
        --runGOElite no || {
        log_error "AltAnalyze analysis failed"
        return 1
    }
    
    # Run pruning step if prune script exists
    if [[ -f "/usr/src/app/prune.py" ]]; then
        log_info "Running junction count matrix pruning"
        "${PYTHON_CMD}" /usr/src/app/prune.py || {
            log_warn "Pruning step failed but continuing"
        }
    else
        log_warn "Prune script not found, skipping pruning step"
    fi
    
    log_info "BED to junction analysis completed successfully"
    return 0
}

# Full identify pipeline function
run_identify() {
    local bam_folder="$1"
    local cores="$2"
    
    log_info "Running full identify pipeline: ${bam_folder} with ${cores} cores"
    
    # Validate inputs
    validate_directory "${bam_folder}" "BAM folder" || return 1
    
    if ! [[ "${cores}" =~ ^[0-9]+$ ]] || [[ "${cores}" -lt 1 ]]; then
        log_error "Invalid cores value: ${cores}. Must be a positive integer."
        return 1
    fi
    
    # Check for GNU Parallel
    if ! command -v parallel &> /dev/null; then
        log_error "GNU Parallel not found. Required for identify mode."
        return 1
    fi
    
    # BAM to BED conversion function for parallel execution
    run_bam_to_bed_parallel() {
        local bam_file="$1"
        export SPECIES ALTANALYZE_ROOT PYTHON_CMD
        
        log_info "Processing ${bam_file} in parallel"
        
        # Junction BED
        "${PYTHON_CMD}" "${ALTANALYZE_ROOT}/import_scripts/BAMtoJunctionBED.py" \
            --i "${g_bam_folder}/${bam_file}" \
            --species "${SPECIES}" \
            --r "${ALTANALYZE_ROOT}/AltDatabase/${VERSION}/ensembl/${SPECIES}/${SPECIES}_Ensembl_exon.txt"
        
        # Exon BED
        "${PYTHON_CMD}" "${ALTANALYZE_ROOT}/import_scripts/BAMtoExonBED.py" \
            --i "${g_bam_folder}/${bam_file}" \
            --r "${ALTANALYZE_ROOT}/AltDatabase/${VERSION}/ensembl/${SPECIES}/${SPECIES}.bed" \
            --s "${SPECIES}"
        
        return 0
    }
    
    # Export function for parallel
    export -f run_bam_to_bed_parallel
    export g_bam_folder="${bam_folder}"
    export SPECIES ALTANALYZE_ROOT PYTHON_CMD VERSION
    
    # Collect BAM file names
    cd "${bam_folder}"
    find . -name "*.bam" -type f -printf "%f\n" > ../samples.txt
    cd ..
    
    local bam_count
    bam_count=$(wc -l < samples.txt)
    if [[ ${bam_count} -eq 0 ]]; then
        log_error "No BAM files found in ${bam_folder}"
        return 1
    fi
    
    log_info "Found ${bam_count} BAM files, processing with ${cores} cores"
    
    # Run BAM to BED conversion in parallel
    log_info "Starting parallel BAM to BED conversion"
    cat samples.txt | parallel -P "${cores}" run_bam_to_bed_parallel {} || {
        log_error "Parallel BAM to BED conversion failed"
        return 1
    }
    
    # Move BED files to bed folder
    log_info "Organizing BED files"
    mkdir -p bed
    cd "${bam_folder}"
    find . -name "*.bed" -type f -exec mv {} ../bed/ \; 2>/dev/null || true
    cd ..
    
    # Run BED to junction analysis
    run_bed_to_junction "bed" || return 1
    
    # Cleanup temporary files
    rm -f samples.txt
    
    log_info "Full identify pipeline completed successfully"
    return 0
}

# Main execution logic
main() {
    # Change to working directory
    cd "${WORKING_DIR}"
    log_info "Working directory: $(pwd)"
    log_info "Species: ${SPECIES}, Platform: ${PLATFORM}, Version: ${VERSION}"
    
    # Check if help requested
    if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        show_usage
        exit 0
    fi
    
    local mode="$1"
    
    # Check dependencies
    if ! check_dependencies "${mode}"; then
        exit 1
    fi
    
    # Process based on mode
    case "${mode}" in
        "bam_to_bed")
            if [[ $# -lt 2 ]]; then
                log_error "bam_to_bed mode requires BAM file argument"
                show_usage
                exit 1
            fi
            
            bam_file="${WORKING_DIR}/$2"
            log_info "Running bam_to_bed mode with file: ${bam_file}"
            run_bam_to_bed "${bam_file}"
            ;;
            
        "bed_to_junction")
            if [[ $# -lt 2 ]]; then
                log_error "bed_to_junction mode requires BED folder argument"
                show_usage
                exit 1
            fi
            
            bed_folder="${WORKING_DIR}/$2"
            log_info "Running bed_to_junction mode with folder: ${bed_folder}"
            run_bed_to_junction "$2"  # Pass relative path
            ;;
            
        "identify")
            if [[ $# -lt 3 ]]; then
                log_error "identify mode requires BAM folder and cores arguments"
                show_usage
                exit 1
            fi
            
            bam_folder="${WORKING_DIR}/$2"
            cores="$3"
            log_info "Running identify mode with folder: ${bam_folder}, cores: ${cores}"
            run_identify "$2" "${cores}"  # Pass relative path
            ;;
            
        "DE")
            if [[ $# -lt 3 ]]; then
                log_error "DE mode requires output folder and group file arguments"
                show_usage
                exit 1
            fi
            
            output_folder="${WORKING_DIR}/$2"
            group_file="${WORKING_DIR}/$3"
            log_info "Running DE analysis with output: ${output_folder}, groups: ${group_file}"
            
            validate_directory "${output_folder}" "Output folder" || exit 1
            validate_file "${group_file}" "Group file" || exit 1
            
            "${PYTHON_CMD}" "${ALTANALYZE_ROOT}/stats_scripts/metaDataAnalysis.py" \
                --p "${PLATFORM}" --s "${SPECIES}" --adjp yes --pval 1 --f 1 \
                --i "${output_folder}/ExpressionInput/exp.original-steady-state.txt" \
                --m "${group_file}"
            ;;
            
        "GO")
            if [[ $# -lt 2 ]]; then
                log_error "GO mode requires gene list file argument"
                show_usage
                exit 1
            fi
            
            gene_list_file="${WORKING_DIR}/$2"
            log_info "Running GO analysis with gene list: ${gene_list_file}"
            
            validate_file "${gene_list_file}" "Gene list file" || exit 1
            
            # BioMarkers analysis
            mkdir -p GO_Elite_result_BioMarkers
            "${PYTHON_CMD}" "${ALTANALYZE_ROOT}/GO_Elite.py" \
                --species "${SPECIES}" --mod Ensembl --pval 0.05 --num 3 \
                --input "${gene_list_file}" \
                --output "${WORKING_DIR}/GO_Elite_result_BioMarkers" \
                --dataToAnalyze BioMarkers
            
            # Gene Ontology analysis
            mkdir -p GO_Elite_result_GeneOntology
            "${PYTHON_CMD}" "${ALTANALYZE_ROOT}/GO_Elite.py" \
                --species "${SPECIES}" --mod Ensembl --pval 0.05 --num 3 \
                --input "${gene_list_file}" \
                --output "${WORKING_DIR}/GO_Elite_result_GeneOntology" \
                --dataToAnalyze GeneOntology
            ;;
            
        "DAS")
            if [[ $# -lt 3 ]]; then
                log_error "DAS mode requires output folder and group file arguments"
                show_usage
                exit 1
            fi
            
            output_folder="${WORKING_DIR}/$2"
            group_file="${WORKING_DIR}/$3"
            log_info "Running DAS analysis with output: ${output_folder}, groups: ${group_file}"
            
            validate_directory "${output_folder}" "Output folder" || exit 1
            validate_file "${group_file}" "Group file" || exit 1
            
            "${PYTHON_CMD}" "${ALTANALYZE_ROOT}/stats_scripts/metaDataAnalysis.py" \
                --p PSI --dPSI 0 --pval 1 --adjp no \
                --i "${output_folder}/AltResults/AlternativeOutput/${SPECIES}_RNASeq_top_alt_junctions-PSI_EventAnnotation.txt" \
                --m "${group_file}"
            ;;
            
        *)
            log_error "Invalid mode: ${mode}"
            show_usage
            exit 1
            ;;
    esac
    
    log_info "AltAnalyze.sh completed successfully"
}

# Run main function with all arguments
main "$@"