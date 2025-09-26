#!/bin/bash
# Single-cell workflow environment configuration
# Copy to env.sh and customize for your Terra workspace
# Usage: source workflows/single_cell/terra_runs/env.sh

# Required identifiers
export NAMESPACE="AltAnalyze3_SNAF"
export WORKSPACE_PROJECT="AltAnalyze3_SNAF"
export WORKSPACE_NAME="AltAnalyze3_SNAF"
export WORKSPACE="${WORKSPACE_PROJECT}/${WORKSPACE_NAME}"

# Workspace bucket (name without gs://)
# Tip: fissfc space_info -w "$WORKSPACE_NAME" -p "$WORKSPACE_PROJECT" | grep bucketName
export WORKSPACE_BUCKET="fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f"

# Single-cell specific settings
export CUMULUS_DEFAULT_VERSION="latest"
export SINGLE_CELL_MAX_COST_USD="50.00"

# Reference genome paths (update these for your workspace)
export REFERENCE_GENOME_HG38="gs://your-bucket/references/hg38/fasta/Homo_sapiens_assembly38.fasta"
export REFERENCE_TRANSCRIPTOME_HG38="gs://your-bucket/references/hg38/gtf/Homo_sapiens.GRCh38.109.gtf"
export REFERENCE_GENOME_HG19="gs://your-bucket/references/hg19/fasta/Homo_sapiens_assembly19.fasta"
export REFERENCE_TRANSCRIPTOME_HG19="gs://your-bucket/references/hg19/gtf/Homo_sapiens.GRCh19.87.gtf"

# Gene lists for quality control
export MT_GENES_HG38="gs://your-bucket/references/hg38/mt_genes.txt"
export RIBO_GENES_HG38="gs://your-bucket/references/hg38/ribo_genes.txt"
export HB_GENES_HG38="gs://your-bucket/references/hg38/hb_genes.txt"

# Helper functions
cumulus_method_ref() {
  local version="$1"
  if [[ -n "$version" && "$version" != "latest" ]]; then
    echo "cumulus/cumulus/${version}"
  else
    echo "cumulus/cumulus"
  fi
}

# Single-cell specific workspace validation
validate_single_cell_workspace() {
  echo "🔍 Validating single-cell workspace configuration..."
  
  # Check workspace access
  if ! fissfc space_info -w "$WORKSPACE_NAME" -p "$WORKSPACE_PROJECT" >/dev/null 2>&1; then
    echo "❌ Cannot access workspace: $WORKSPACE_PROJECT/$WORKSPACE_NAME"
    echo "   Check your authentication and workspace permissions"
    return 1
  fi
  
  # Check reference files exist
  local refs=("$REFERENCE_GENOME_HG38" "$REFERENCE_TRANSCRIPTOME_HG38")
  for ref in "${refs[@]}"; do
    if ! gsutil -q stat "$ref" >/dev/null 2>&1; then
      echo "⚠️  Reference file not found: $ref"
      echo "   Update REFERENCE_GENOME_HG38 and REFERENCE_TRANSCRIPTOME_HG38 in env.sh"
    fi
  done
  
  echo "✅ Single-cell workspace validation complete"
}